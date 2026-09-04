#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

MI_REPO=https://github.com/microsoft/mimalloc
MI_COMMIT=18b08671c9302247bfb682286e6bf3cc1773f801

echo "=== 1. toolchain and sources ==="
apk add --no-cache build-base cmake git binutils file >/dev/null 2>&1 \
    || { echo "apk add failed -- on a TLS-inspected network this is a TRUST problem," >&2
         echo "and apk reports it as 'no such package'. docs/AGENTS.md" >&2; exit 2; }
echo "musl:  $(apk info -v musl 2>/dev/null | head -1)"
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

echo "=== 2. build the replacement as a STATIC, POSITION-INDEPENDENT archive ==="
echo " Both properties are load-bearing:"
echo "   MI_OVERRIDE=ON               -> the archive defines malloc/free, not"
echo "                                   only mi_malloc/mi_free. Without it"
echo "                                   there is nothing to replace musl WITH."
echo "   POSITION_INDEPENDENT_CODE=ON -> a static-PIE cannot contain non-PIC"
echo "                                   objects. Without it the final link"
echo "                                   fails on a relocation you did not write."
echo
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
echo "it defines the plain names, which is what makes it a REPLACEMENT:"
nm --defined-only "$MI_A" 2>/dev/null | awk '$3 ~ /^(malloc|free|calloc|realloc)$/ {print "   " $2 " " $3}' | sort -u
echo

echo "=== 2b. the same program, built BEFORE the surgery, kept as the control ==="
cc -static-pie -O2 -pthread -o /tmp/probe-before /examples/allocprobe.c \
    || { echo "the reference build failed" >&2; exit 2; }
printf '  mallocng internals in the untouched binary: %s\n' \
    "$(nm --defined-only /tmp/probe-before 2>/dev/null | grep -cE ' [TtWw] (nontrivial_free|get_meta)$')"
printf '  mimalloc internals in the untouched binary: %s\n' \
    "$(nm --defined-only /tmp/probe-before 2>/dev/null | grep -cE ' [TtWw] (mi_malloc|mi_free)$')"
echo

echo "=== 3.  THE ARCHIVE ON THE LINK LINE, RUN SO YOU CAN SEE WHAT IT DOES ==="
echo "\`cc -static-pie prog.c libmimalloc.a\` -- the obvious approach."
echo
echo "For a small C program the linker satisfies malloc from the first archive"
echo "that defines it and never extracts musl's malloc.lo, so this links and the"
echo "binary works. For ripgrep it fails with \`multiple definition\` on nine"
echo "symbols: Rust's std drags in musl objects referencing __libc_malloc, and"
echo "then both archives are extracted."
echo
set +e
cc -static-pie -O2 -pthread -o /tmp/naive /examples/allocprobe.c "$MI_A" >/tmp/naive.log 2>&1
naive_rc=$?
set -e
echo "  exit status: $naive_rc"
dupes=$(grep -c 'multiple definition' /tmp/naive.log 2>/dev/null || echo 0)
echo "  'multiple definition' errors: $dupes"
grep 'multiple definition' /tmp/naive.log 2>/dev/null \
    | sed 's/.*multiple definition of //' | sort -u | head -12 | sed 's/^/     /'
if [ "$naive_rc" -eq 0 ]; then
    echo
    echo "  It linked. So look at what it produced, rather than stopping here:"
    printf '    mimalloc symbols:      %s\n' \
        "$(nm --defined-only /tmp/naive 2>/dev/null | grep -cE ' (mi_malloc|mi_free)$')"
    printf '    musl allocator inside: %s\n' \
        "$(nm --defined-only /tmp/naive 2>/dev/null | grep -cE ' (nontrivial_free|get_meta)$')"
    printf '    definitions of malloc: %s\n' \
        "$(nm --defined-only /tmp/naive 2>/dev/null | grep -cE ' [TtWw] malloc$')"
    echo
    echo "   SO WHY NOT JUST DO THIS? Whether it works is a property of YOUR"
    echo "     PROGRAM, not of the technique: it depends on which libc.a members"
    echo "     your program drags in, and that changes when you add a call to"
    echo "     getaddrinfo. An image whose allocator replacement works for one"
    echo "     binary and silently does not for the next is worse than none."
    echo "      The surgery removes the dependence -- musl'\''s members are not"
    echo "     in the archive at all, so there is nothing for the linker to pick."
fi
echo

echo "=== 4. the surgery: delete musl's members, add mimalloc's ==="
sh /examples/musl-libc-surgery.sh "$MI_A" /usr/lib/libc.a || exit 1
echo

echo "=== 5. build a static-PIE binary WITH NO ALLOCATOR FLAGS AT ALL ==="
echo "  cc -static-pie -O2 -pthread -o allocprobe allocprobe.c"
echo " Read that command again: there is nothing allocator-shaped in it. That"
echo "   is the entire claim of this mechanism."
echo
cc -static-pie -O2 -pthread -o /tmp/probe-pie /examples/allocprobe.c \
    || { echo "the static-PIE link failed" >&2; exit 1; }

cc -static -no-pie -O2 -pthread -o /tmp/probe-static /examples/allocprobe.c \
    || { echo "the plain static link failed" >&2; exit 1; }
echo "  cc -static -no-pie …        # the contrast. -no-pie is REQUIRED:"
echo "                              # Alpine's gcc is --enable-default-pie, so"
echo "                              # -static alone still gives you a PIE."
ls -l /tmp/probe-pie /tmp/probe-static | sed 's/^/  /'
echo

echo "=== 6. is it the binary it claims to be? ==="
verify_reset
want_elf /tmp/probe-pie static-pie
want_elf /tmp/probe-static static

echo "  -- the replacement is IN it:"
want_symbol /tmp/probe-pie mi_malloc mi_free malloc free

echo "  -- and musl's own allocator is GONE (present before, absent after):"
want_displaced /tmp/probe-before /tmp/probe-pie nontrivial_free get_meta

echo "  -- it depends on nothing:"
if readelf -d /tmp/probe-pie 2>/dev/null | grep -q 'NEEDED'; then
    _bad "the 'static' binary has NEEDED entries"
else
    _ok "no NEEDED entries: nothing to install alongside it"
fi
echo

echo "=== 7. does it WORK, and does it stay up? ==="
want_run "stress, 4 threads, 60 000 iterations" /tmp/probe-pie stress 4 60000
want_run "stress, 8 threads (contention)"       /tmp/probe-pie stress 8 30000
want_run "the plain static build too"           /tmp/probe-static stress 4 30000
want_count /tmp/probe-pie 5000
want_count /tmp/probe-static 5000
echo

echo "=== 8. static-PIE vs static, observed rather than assumed ==="
echo " Both are 'statically linked'. Only one of them moves. This is measured"
echo "  from the running process, not read off the ELF header, because the two"
echo "  have disagreed here before (docs/AGENTS.md, the first aarch64 run)."
echo
want_aslr /tmp/probe-pie 6 moves
want_aslr /tmp/probe-static 6 fixed
echo

echo "=== 9. restore, so the image is left as it was found ==="
cp /usr/lib/libc.a.orig /usr/lib/libc.a
echo "  libc.a restored from libc.a.orig"
echo "   In a real image you would NOT restore it: the whole point is that"
echo "    every later build in that image inherits the replacement. Restoring"
echo "    here keeps this example re-runnable."
echo

echo "=== what this example establishes ==="
echo " musl's allocator can be replaced inside libc.a, and afterwards an"
echo "   ordinary \`cc -static-pie\` produces a binary that contains the"
echo "   replacement, does NOT contain musl's, runs a multi-threaded allocation"
echo "   stress clean, returns the right answer, and still gets ASLR."
echo " It does not establish a speed. This repository measures that, and its"
echo "   headline finding is that the ANSWER DEPENDS ON THE MACHINE: the same"
echo "   comparison has produced three different orderings on three CPUs"
echo "   (docs/AGENTS.md). Measure on yours."
verify_summary
