#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

MI_REPO=https://github.com/microsoft/mimalloc
MI_COMMIT=18b08671c9302247bfb682286e6bf3cc1773f801

echo "=== 1. toolchain: clang, LLVM binutils, and the STATIC libc package ==="
echo "  /usr/lib/libc.a before installing anything: $( [ -f /usr/lib/libc.a ] && echo yes || echo ' no')"
apk update >/tmp/apk.log 2>&1 || true
if ! apk add chimerautils base-devel base-devel-static clang lld cmake ninja gmake git curl \
        >>/tmp/apk.log 2>&1; then
    echo "apk add failed. What it said:" >&2
    tail -12 /tmp/apk.log | sed 's/^/    /' >&2
    exit 2
fi
trust_extra_ca
print_conditions
echo "cc is really: $(cc --version 2>/dev/null | head -1)"
echo "ar is really: $(ar --version 2>/dev/null | head -1)"
echo "nm is really: $(nm --version 2>/dev/null | head -1)"
echo

echo "=== 2. where is libc.a? ==="
LIBC=$(cc -print-file-name=libc.a 2>/dev/null)
case "$LIBC" in libc.a|"") LIBC="" ;; esac
[ -n "$LIBC" ] && [ -f "$LIBC" ] || {
    echo "no libc.a even after base-devel-static; the package layout changed" >&2; exit 2; }
echo "  /usr/lib/libc.a now exists?    $( [ -f /usr/lib/libc.a ] && echo yes || echo no)"
echo "  cc -print-file-name=libc.a ->  $LIBC"
echo "  ls -ld /lib:                   $(ls -ld /lib)"
echo "   /lib is a symlink to usr/lib, so the two paths are the same file."
echo "     Asking the compiler is still the right move -- it is what makes this"
echo "     script portable to the distribution where they are NOT the same."
echo "  using: $LIBC ($(wc -c < "$LIBC") bytes, $(ar t "$LIBC" | wc -l) members)"
echo
echo "   llvm-nm's archive member headers, the thing most likely to break a"
echo "    parser written against GNU binutils. On this version they are BARE,"
echo "    the same as GNU nm; musl-libc-surgery.sh normalises both forms:"
nm --defined-only "$LIBC" 2>/dev/null | grep -m3 ':$' | sed 's/^/       /'
echo

echo "=== 3.  WHAT IS ALREADY IN THIS libc, WHICH IS THE WHOLE STORY ==="
echo "  members of libc.a matching 'mimalloc':"
ar t "$LIBC" 2>/dev/null | grep 'mimalloc' | sed 's/^/    /' || echo "    (none)"
echo
echo "  what that member defines (a selection of 85 symbols):"
ar p "$LIBC" mimalloc.o > /tmp/mi-distro.o 2>/dev/null || true
if [ -s /tmp/mi-distro.o ]; then
    nm --defined-only /tmp/mi-distro.o 2>/dev/null | awk '
        $3 ~ /^(__libc_malloc_impl|__malloc_donate|__malloc_init|__malloc_tls_default|__malloc_tls_teardown|_mi_heap_main|_mi_heap_empty|aligned_alloc|malloc_usable_size)$/ {
            print "    " $2 " " $3 }' | sort -u
fi
echo
echo "  and mallocng -- the allocator upstream musl ships -- is NOT here:"
printf '    nontrivial_free in libc.a: %s\n' \
    "$(nm --defined-only "$LIBC" 2>/dev/null | grep -cE ' [TtWw] nontrivial_free$')"
printf '    get_meta in libc.a:        %s\n' \
    "$(nm --defined-only "$LIBC" 2>/dev/null | grep -cE ' [TtWw] get_meta$')"
echo
echo "   SO THE 'SYSTEM ALLOCATOR' ON CHIMERA IS mimalloc. Any measurement"
echo "     that calls this distribution's control 'musl's allocator' is naming"
echo "     the wrong thing, and any ELF check that tries to tell your mimalloc"
echo "     from the distribution's cannot: they are the same implementation."
echo
echo "   And this is the symbol that decides the rest of this example:"
echo "    who references __malloc_tls_default, which mimalloc.o defines?"
nm "$LIBC" 2>/dev/null | awk '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    $1 == "U" && $2 == "__malloc_tls_default" { print "    " m }' | sort -u
echo "     Threading code. Not allocation code."
echo

echo "=== 4. can this toolchain produce a static-PIE? ==="
echo 'int main(void){return 0;}' > /tmp/tiny.c
LINKMODE=static
if cc -static-pie -O0 -o /tmp/tiny /tmp/tiny.c >/tmp/pie.log 2>&1 \
   && [ "$(elf_kind /tmp/tiny)" = "static-pie" ]; then
    LINKMODE=static-pie
    echo "  -static-pie:  supported, and it produces a DYN image"
else
    echo "  -static-pie:  not usable here; falling back to -static and saying so"
    tail -3 /tmp/pie.log 2>/dev/null | sed 's/^/       /'
fi
echo "  link mode for this run: $LINKMODE"
echo

echo "=== 5. build upstream mimalloc, with a generator that exists here ==="
git init -q /tmp/mimalloc 2>/dev/null
git -C /tmp/mimalloc remote add origin "$MI_REPO" 2>/dev/null
git -C /tmp/mimalloc fetch -q --depth 1 origin "$MI_COMMIT" 2>/tmp/fetch.log \
    || { echo "could not fetch $MI_REPO at $MI_COMMIT:" >&2
         sed 's/^/    /' /tmp/fetch.log >&2; exit 2; }
git -C /tmp/mimalloc checkout -q FETCH_HEAD
echo "mimalloc: $(git -C /tmp/mimalloc rev-parse HEAD)"

cmake -S /tmp/mimalloc -B /tmp/mi-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DMI_OVERRIDE=ON \
    -DMI_BUILD_STATIC=ON \
    -DMI_BUILD_SHARED=OFF \
    -DMI_BUILD_OBJECT=OFF \
    -DMI_BUILD_TESTS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON >/tmp/cmake.log 2>&1 \
    || { echo "cmake configure failed:"; tail -15 /tmp/cmake.log; exit 2; }
cmake --build /tmp/mi-build >/tmp/build.log 2>&1 \
    || { echo "cmake build failed:"; tail -15 /tmp/build.log; exit 2; }
MI_A=$(find /tmp/mi-build -name 'libmimalloc*.a' -type f | head -1)
[ -n "$MI_A" ] || { echo "no static archive"; find /tmp/mi-build -name '*.a' | head; exit 1; }
echo "archive: $MI_A ($(wc -c < "$MI_A") bytes)"
echo

echo "=== 6.  THE SURGERY, AND IT REFUSES ==="
echo "The same unedited script examples 30 and 40 run to completion."
echo
set +e
sh /examples/musl-libc-surgery.sh "$MI_A" "$LIBC"
surgery_rc=$?
set -e
echo
echo "  exit status: $surgery_rc   (0 spliced, 1 failed, 2 could not run, 3 refused)"
verify_reset
if [ "$surgery_rc" -eq 3 ]; then
    _ok "the script refused with a reason and named the symbol, rather than"
    echo "        producing a libc.a that fails to link three steps later"
else
    _bad "expected exit 3 (refused with a reason); got $surgery_rc"
fi
echo

echo "=== 7.  AND WHAT THE REFUSAL PREVENTED ==="
echo "A guard that is never seen to fire is a comment. So the deletion is done"
echo "anyway here -- ignoring the refusal -- and the link is attempted."
echo
MEMBERS=$(nm --defined-only "$LIBC" 2>/dev/null | awk '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    NF >= 3 && $2 ~ /^[TtWwDdBb]$/ &&
        $3 ~ /^(malloc|free|calloc|realloc|aligned_alloc|posix_memalign|malloc_usable_size)$/ { print m }
' | sort -u)
echo "  members that would be deleted:"
printf '%s\n' "$MEMBERS" | sed 's/^/    /'
cp "$LIBC" "$LIBC.orig"
{
    echo "CREATE $LIBC.forced"
    echo "ADDLIB $LIBC.orig"
    for m in $MEMBERS; do echo "DELETE $m"; done
    echo "ADDLIB $MI_A"
    echo "SAVE"
    echo "END"
} > /tmp/forced.mri
if ar -M < /tmp/forced.mri 2>/tmp/forced.log && [ -s "$LIBC.forced" ]; then
    cp "$LIBC.forced" "$LIBC"
    echo "  the archive spliced cleanly: $(ar t "$LIBC" | wc -l) members"
    echo "  definitions of malloc in it: $(nm --defined-only "$LIBC" 2>/dev/null | grep -cE ' [TtWw] malloc$')"
    echo "   Nothing has gone wrong YET. This is exactly why the check has to"
    echo "    look at references and not only at definitions."
    echo
    echo "  cc -$LINKMODE -O2 -pthread -o /tmp/forced allocprobe.c"
    if cc "-$LINKMODE" -O2 -pthread -o /tmp/forced /examples/allocprobe.c >/tmp/forced-link.log 2>&1; then
        _bad "it linked -- the refusal in section 6 was too strict, and this"
        echo "        example's premise is wrong. Read /tmp/forced-link.log."
    else
        echo "   the linker's own words:"
        grep -oE '(undefined [a-z ]*symbol: [A-Za-z_][A-Za-z0-9_]*|undefined reference to .[^'"'"'\`]+.)' \
            /tmp/forced-link.log 2>/dev/null | sort -u | head -6 | sed 's/^/       /'
        if grep -q '__malloc_tls_default' /tmp/forced-link.log 2>/dev/null; then
            _ok "the link fails on __malloc_tls_default -- the symbol section 6 named"
        else
            _bad "the link failed, but not on the symbol the guard predicted"
        fi
    fi
    cp "$LIBC.orig" "$LIBC"
    rm -f "$LIBC.forced"
    echo "  $LIBC restored"
else
    _bad "the forced splice could not be built: $(head -2 /tmp/forced.log | tr '\n' ' ')"
fi
echo

echo "=== 8.  WHAT YOU DO ON CHIMERA INSTEAD: NOTHING ==="
echo "The allocator the surgery would have installed is the one the"
echo "distribution already ships. So build the ordinary way and check."
echo
echo "  cc -$LINKMODE -O2 -pthread -o allocprobe allocprobe.c   # no flags"
cc "-$LINKMODE" -O2 -pthread -o /tmp/probe /examples/allocprobe.c \
    || { echo "the link failed" >&2; exit 1; }
ls -l /tmp/probe | sed 's/^/  /'
echo
want_elf /tmp/probe "$LINKMODE"
want_symbol /tmp/probe malloc free
want_symbol /tmp/probe _mi_heap_main

echo "   no negative control is run on this binary, and that is the point:"
echo "    the allocator the surgery would have installed is the one already"
echo "    here, so no symbol can tell 'displaced' from 'never replaced'."
printf '    mallocng markers in this binary: %s (they were 0 in libc.a too)\n' \
    "$(nm --defined-only /tmp/probe 2>/dev/null | grep -cE ' [TtWw] (nontrivial_free|get_meta)$')"
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

echo "=== what this example establishes ==="
echo " The libc.a surgery is NOT a property of musl alone. It needs a libc"
echo "   whose allocator members are referenced only by allocation code."
echo "   Chimera's are referenced by pthread_create and __init_tls, so the"
echo "   mechanism is unsupported here -- with a named reason, checked by a"
echo "   guard that section 7 shows firing."
echo " What DOES carry across all three musl distributions is the derivation:"
echo "   find libc.a by asking the compiler, read the member list out of the"
echo "   archive, refuse on evidence. Two of those three answered differently"
echo "   here and the script still did the right thing."
echo " And a result that costs nothing: a Chimera static binary is already a"
echo "   mimalloc binary. The verification above is the whole job."
echo " With one caveat this example refuses to hide: on Chimera no ELF check"
echo "   can tell YOUR mimalloc from the DISTRIBUTION'S. They are the same"
echo "   implementation, so the identity oracle every other cell here relies on"
echo "   has nothing to discriminate with."
verify_summary
