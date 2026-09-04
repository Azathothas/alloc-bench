#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

MI_REPO=https://github.com/microsoft/mimalloc
MI_COMMIT=18b08671c9302247bfb682286e6bf3cc1773f801

echo "=== 1. toolchain and sources, the Void way ==="
xbps-install -Suy xbps >/tmp/xbps.log 2>&1 || true
if ! xbps-install -Sy gcc make cmake git binutils musl-devel file >>/tmp/xbps.log 2>&1; then
    echo "xbps-install failed. What it said:" >&2
    tail -15 /tmp/xbps.log | sed 's/^/    /' >&2
    echo "   On a TLS-inspected network this is usually trust: xbps verifies" >&2
    echo "    the repository over HTTPS and reads the system store." >&2
    exit 2
fi
echo "musl:  $(xbps-query -p pkgver musl 2>/dev/null || echo '(not queryable)')"
echo "gcc:   $(gcc --version | head -1)"
print_conditions

trust_extra_ca          # again, now that ca-certificates is installed
git init -q /tmp/mimalloc 2>/dev/null
git -C /tmp/mimalloc remote add origin "$MI_REPO" 2>/dev/null
git -C /tmp/mimalloc fetch -q --depth 1 origin "$MI_COMMIT" 2>/tmp/fetch.log \
    || { echo "could not fetch $MI_REPO at $MI_COMMIT:" >&2
         sed 's/^/    /' /tmp/fetch.log >&2; exit 2; }
git -C /tmp/mimalloc checkout -q FETCH_HEAD
echo "mimalloc: $(git -C /tmp/mimalloc rev-parse HEAD)"
echo

echo "=== 2. can this compiler produce a static-PIE at all? ==="
echo " Probed, not assumed. A static-PIE needs Scrt1.o and rcrt1.o and a"
echo "   linker that will take -static-pie; a distribution that ships neither"
echo "   gives you a plain static binary while accepting the flag."
echo
echo 'int main(void){return 0;}' > /tmp/tiny.c
LINKMODE=static
if cc -static-pie -O0 -o /tmp/tiny /tmp/tiny.c >/tmp/pie.log 2>&1; then
    if [ "$(elf_kind /tmp/tiny)" = "static-pie" ]; then
        LINKMODE=static-pie
        echo "  -static-pie:  supported, and it really produces a DYN image"
    else
        echo "  -static-pie:  ACCEPTED but produced a $(elf_kind /tmp/tiny) binary."
        echo "               Using plain -static, and saying so, rather than"
        echo "               publishing a non-PIE binary under a PIE label."
    fi
else
    echo "  -static-pie:  rejected by this toolchain:"
    tail -3 /tmp/pie.log | sed 's/^/       /'
    echo "               Falling back to -static."
fi
echo "  link mode for this run: $LINKMODE"
echo

echo "=== 3. build mimalloc as a static, position-independent archive ==="
cmake -S /tmp/mimalloc -B /tmp/mi-build \
    -DCMAKE_BUILD_TYPE=Release \
    -DMI_OVERRIDE=ON \
    -DMI_BUILD_STATIC=ON \
    -DMI_BUILD_SHARED=OFF \
    -DMI_BUILD_OBJECT=OFF \
    -DMI_BUILD_TESTS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON >/tmp/cmake.log 2>&1 \
    || { echo "cmake configure failed:"; tail -15 /tmp/cmake.log; exit 2; }
cmake --build /tmp/mi-build -j "$(nproc)" >/tmp/build.log 2>&1 \
    || { echo "cmake build failed:"; tail -15 /tmp/build.log; exit 2; }
MI_A=$(find /tmp/mi-build -name 'libmimalloc*.a' -type f | head -1)
[ -n "$MI_A" ] || { echo "no static archive was produced"; find /tmp/mi-build -name '*.a' | head; exit 1; }
echo "archive: $MI_A ($(wc -c < "$MI_A") bytes)"
echo

echo "=== 4. find this distribution's libc.a -- it is NOT always /usr/lib ==="
LIBC=""
for cand in /usr/lib/libc.a /usr/lib64/libc.a /lib/libc.a; do
    [ -f "$cand" ] && { LIBC=$cand; break; }
done
if [ -z "$LIBC" ]; then
    # Ask the compiler rather than guessing. It knows where it will look.
    LIBC=$(cc -print-file-name=libc.a 2>/dev/null)
    case "$LIBC" in libc.a|"") LIBC="" ;; esac
fi
[ -n "$LIBC" ] || { echo "no libc.a on this system: install the static libc package" >&2; exit 2; }
echo "libc.a:  $LIBC   (found via $( [ -f /usr/lib/libc.a ] && echo 'the usual path' || echo 'cc -print-file-name'))"
echo

echo "=== 4b. the same program, built BEFORE the surgery, kept as the control ==="
cc "-$LINKMODE" -O2 -pthread -o /tmp/probe-before /examples/allocprobe.c \
    || { echo "the reference build failed" >&2; exit 2; }
printf '  mallocng internals in the untouched binary: %s\n' \
    "$(nm --defined-only /tmp/probe-before 2>/dev/null | grep -cE ' [TtWw] (nontrivial_free|get_meta)$')"
echo

echo "=== 5. the surgery, byte for byte the same script as example 30 ==="
sh /examples/musl-libc-surgery.sh "$MI_A" "$LIBC" || exit 1
echo

echo "=== 6. build, with no allocator flags ==="
echo "  cc -$LINKMODE -O2 -pthread -o allocprobe allocprobe.c"
cc "-$LINKMODE" -O2 -pthread -o /tmp/probe /examples/allocprobe.c \
    || { echo "the link failed" >&2; exit 1; }
ls -l /tmp/probe | sed 's/^/  /'
echo

echo "=== 7. verify ==="
verify_reset
want_elf /tmp/probe "$LINKMODE"
want_symbol /tmp/probe mi_malloc mi_free malloc free
want_displaced /tmp/probe-before /tmp/probe nontrivial_free get_meta
if readelf -d /tmp/probe 2>/dev/null | grep -q 'NEEDED'; then
    _bad "the 'static' binary has NEEDED entries"
else
    _ok "no NEEDED entries"
fi
want_run "stress, 4 threads, 60 000 iterations" /tmp/probe stress 4 60000
want_run "stress, 8 threads (contention)"       /tmp/probe stress 8 30000
want_count /tmp/probe 5000
if [ "$LINKMODE" = static-pie ]; then
    want_aslr /tmp/probe 6 moves
else
    want_aslr /tmp/probe 6 fixed
fi
echo

echo "=== 8. restore ==="
cp "$LIBC.orig" "$LIBC"
echo "  $LIBC restored"
echo

echo "=== what this example establishes ==="
echo " The libc.a surgery is a MUSL technique and not an Alpine one: the same"
echo "   script, unchanged, works on a distribution that shares no packaging,"
echo "   no toolchain configuration and no patch set with Alpine."
echo " It also shows the honest handling of a toolchain difference: the link"
echo "   mode is probed and reported rather than assumed, because a non-PIE"
echo "   binary published under a PIE label is the exact failure this"
echo "   repository's identity oracle exists to prevent."
verify_summary
