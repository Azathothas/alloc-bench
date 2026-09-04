#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

MI_REPO=https://github.com/microsoft/mimalloc
MI_COMMIT=18b08671c9302247bfb682286e6bf3cc1773f801

echo "=== 1. build mimalloc from source, at a pinned commit ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/tmp/apt.log 2>&1 || { echo "apt-get update failed:"; tail -5 /tmp/apt.log; exit 2; }
apt-get install -y -qq --no-install-recommends \
    gcc g++ libc6-dev cmake make git ca-certificates binutils file \
    >>/tmp/apt.log 2>&1 || { echo "apt-get install failed:"; tail -10 /tmp/apt.log; exit 2; }

print_conditions

trust_extra_ca

git init -q /tmp/mimalloc 2>/dev/null
git -C /tmp/mimalloc remote add origin "$MI_REPO" 2>/dev/null
if ! git -C /tmp/mimalloc fetch -q --depth 1 origin "$MI_COMMIT" 2>/tmp/fetch.log; then
    echo "could not fetch $MI_REPO at $MI_COMMIT:" >&2
    sed 's/^/    /' /tmp/fetch.log >&2
    exit 2
fi
git -C /tmp/mimalloc checkout -q FETCH_HEAD
echo "mimalloc: $MI_REPO @ $(git -C /tmp/mimalloc rev-parse HEAD)"

cmake -S /tmp/mimalloc -B /tmp/mi-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DMI_OVERRIDE=ON \
    -DMI_BUILD_SHARED=ON \
    -DMI_BUILD_STATIC=OFF \
    -DMI_BUILD_OBJECT=OFF \
    -DMI_BUILD_TESTS=OFF >/tmp/cmake.log 2>&1 \
    || { echo "cmake configure failed:"; tail -15 /tmp/cmake.log; exit 2; }
cmake --build /tmp/mi-build -j "$(nproc)" >/tmp/build.log 2>&1 \
    || { echo "cmake build failed:"; tail -15 /tmp/build.log; exit 2; }

BUILT=$(find /tmp/mi-build -name 'libmimalloc.so*' -type f | head -1)
[ -n "$BUILT" ] || { echo "the build produced no libmimalloc.so"; find /tmp/mi-build -name '*.so*' | head; exit 1; }
LIB=/usr/local/lib/libmimalloc-EXAMPLE20.so
cp "$BUILT" "$LIB"
echo "built:    $BUILT -> $LIB ($(wc -c < "$LIB") bytes)"
echo

echo "=== 2. does the library you just built actually export an allocator? ==="
echo " nm -D, not nm. The DYNAMIC symbol table is what ld.so resolves"
echo "   against; a library can define malloc in .symtab and export nothing."
echo
verify_reset
for s in malloc free calloc realloc posix_memalign; do
    if nm -D --defined-only "$LIB" 2>/dev/null | grep -qE "[[:space:]][TWi][[:space:]]+$s\$"; then
        _ok "exports $s"
    else
        _bad "does NOT export $s -- check MI_OVERRIDE; LD_PRELOAD would do nothing"
    fi
done
echo "  mimalloc's own prefixed API is there too, which is how you know it is mimalloc:"
nm -D --defined-only "$LIB" 2>/dev/null | awk '$3 ~ /^mi_(malloc|free|realloc|version)$/ {print "     " $2 " " $3}' | sort -u
echo

echo "=== 3. run the subject under it ==="
cc -O2 -pthread -o /tmp/allocprobe /examples/allocprobe.c \
    || { echo "the probe did not build" >&2; exit 2; }
want_elf /tmp/allocprobe dynamic
want_resident     "$LIB" env LD_PRELOAD="$LIB" /tmp/allocprobe stress 4 40000
want_not_resident "$LIB" /tmp/allocprobe stress 1 100
want_run "stress, 4 threads, 40 000 iterations" env LD_PRELOAD="$LIB" /tmp/allocprobe stress 4 40000
want_run "stress, 8 threads (contention)"       env LD_PRELOAD="$LIB" /tmp/allocprobe stress 8 20000
LD_PRELOAD=$LIB; export LD_PRELOAD
want_count /tmp/allocprobe 5000
unset LD_PRELOAD
echo

echo "=== 4. the check that the ENVIRONMENT VARIABLE is not the evidence ==="
echo " mimalloc will tell you about itself if asked. MIMALLOC_VERBOSE=1 prints"
echo "   its banner from inside the process -- a second, independent witness"
echo "   that does not depend on reading /proc:"
echo
LD_PRELOAD=$LIB MIMALLOC_VERBOSE=1 /tmp/allocprobe count 200 2>&1 \
    | grep -iE 'mimalloc|version' | head -3 | sed 's/^/     /'
echo
echo " Not every allocator has such a banner, which is why residency is the"
echo "  check the harness relies on: it works for all of them."
echo

echo "=== what this example establishes ==="
echo " An allocator built from source at a pinned commit can be preloaded into"
echo "   an unmodified dynamic binary on Ubuntu, and both the export check and"
echo "   the residency check confirm it is the file that was built here."
echo " It does not establish that it is faster. On glibc this project measured"
echo "   preloaded mimalloc at 1.194x the control -- 19.4% SLOWER, outside its"
echo "   own 2.9% MAD -- in results/published/2026-09-03-preload-x86_64-all-eight/."
verify_summary
