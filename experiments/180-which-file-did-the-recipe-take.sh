#!/bin/sh
set -u

OUT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/out" 2>/dev/null && pwd) || {
    echo "experiments/out is missing" >&2
    exit 2
}
TRANSCRIPT="$OUT_DIR/180-which-file-did-the-recipe-take.txt"
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

command -v cc >/dev/null 2>&1 || { echo "no cc" >&2; exit 2; }
command -v od >/dev/null 2>&1 || { echo "no od" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-180.$$"
trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W/out/lib" || exit 2

SRC="$W"; OUT="$W/out"
export SRC OUT
# shellcheck source=/dev/null
. "$ROOT/allocators/lib.sh"
set +e
command -v pick_elf_so >/dev/null 2>&1 || {
    echo "allocators/lib.sh did not define pick_elf_so" >&2
    exit 2
}

rc=0
fail() { rc=1; echo " $1"; }
pass() { echo " $1"; }

old_selector() { find -L "$1" -type f -name 'libtcmalloc*.so*' 2>/dev/null | head -1; }

new_selector() { new_selector_loud "$1" 2>/dev/null; }
new_selector_loud() {
    {
        find -L "$1" -type f -name 'libtcmalloc*.so' 2>/dev/null | sort
        find -L "$1" -type f -name '*.so' 2>/dev/null | sort
    } | pick_elf_so
}

{
    echo "=== conditions ==="
    echo "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:  $(uname -srm)"
    echo "cc:    $(cc --version 2>/dev/null | head -1)"
    echo "tree:  $ROOT at $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo

    mkdir -p "$W/bin" || exit 2
    echo 'int probe_symbol(void){return 42;}' > "$W/probe.c"
    cc -shared -fPIC -o "$W/bin/libtcmalloc_allocbench.so" "$W/probe.c" 2>/dev/null || {
        echo "could not build a shared object here" >&2; exit 2; }
    cc -c -fPIC -o "$W/bin/libtcmalloc_lookalike.so" "$W/probe.c" 2>/dev/null || {
        echo "could not build a relocatable object here" >&2; exit 2; }

    printf -- '-o bazel-out/k8-opt/bin/libtcmalloc_allocbench.so\n--whole-archive\n' \
        > "$W/bin/libtcmalloc_allocbench.so-2.params"
    printf 'placeholder\n' > "$W/bin/libtcmalloc_allocbench.so.jdeps"

    echo "=== what is in the planted bazel-bin ==="
    for f in "$W"/bin/*; do
        printf '  %-45s %s\n' "$(basename "$f")" "$(elf_kind "$f")"
    done
    echo

    echo "=== case 1: does the OLD selector's glob match a non-library at all? ==="
    matched=$(find -L "$W/bin" -type f -name 'libtcmalloc*.so*' | sort | sed 's#.*/##')
    echo "  files matching 'libtcmalloc*.so*':"
    printf '%s\n' "$matched" | sed 's/^/    /'
    nmatch=$(printf '%s\n' "$matched" | grep -c .)
    if [ "$nmatch" -gt 1 ]; then
        pass "the glob matches $nmatch files, only one of which is a library."
        echo "      So which one \`head -1\` returns is decided by directory order,"
        echo "        not by the recipe. That is the defect."
    else
        fail "the glob matched $nmatch file(s); this probe's premise does not hold here"
    fi
    echo

    echo "=== case 2: can the OLD selector actually take the wrong file? ==="
    took_bad=0
    for first in libtcmalloc_allocbench.so-2.params libtcmalloc_allocbench.so; do
        d="$W/order-$first"
        mkdir -p "$d"
        cp "$W/bin/$first" "$d/"
        for f in "$W"/bin/*; do
            [ "$(basename "$f")" = "$first" ] || cp "$f" "$d/"
        done
        got=$(old_selector "$d" | sed 's#.*/##')
        kind=$(elf_kind "$d/$got")
        printf '  %-46s old selector took: %-38s (%s)\n' "$first created first," "$got" "$kind"
        [ "$kind" = "elf-shared" ] || took_bad=1
    done
    if [ "$took_bad" -eq 1 ]; then
        pass "the OLD selector takes a NON-LIBRARY, and ships it as the allocator."
        echo "      READ THIS PRECISELY. What is demonstrated is that the old selector"
        echo "       returns a file that is not a shared object. It is NOT demonstrated"
        echo "       that the answer CHANGES between the two arrangements above --"
        echo "       creation order is not readdir order, and a probe cannot dictate"
        echo "       what a filesystem enumerates first. The order-dependence is an"
        echo "       argument from \`head -1\` over an unsorted \`find\`, and the fix"
        echo "       removes both the ambiguity and the ordering question together."
    else
        echo "   Both orders happened to yield the library on this filesystem, so this"
        echo "    case did not fire. The glob in case 1 is still ambiguous and the"
        echo "    defect stands on that; a probe that cannot force the order cannot"
        echo "    turn a latent ambiguity into a demonstration on every filesystem."
    fi
    echo

    echo "=== case 3: does the NEW selector take the library under BOTH orders? ==="
    for first in libtcmalloc_allocbench.so-2.params libtcmalloc_allocbench.so; do
        d="$W/order-$first"
        got=$(new_selector "$d" | sed 's#.*/##')
        kind=$(elf_kind "$d/$got")
        printf '  %-46s new selector took: %-38s (%s)\n' "$first created first," "$got" "$kind"
        if [ "$kind" = "elf-shared" ] && [ "$got" = "libtcmalloc_allocbench.so" ]; then
            :
        else
            fail "the new selector took '$got' ($kind) when $first was created first"
        fi
    done
    [ "$rc" -eq 0 ] && pass "the NEW selector is order-independent and takes the ELF shared object."
    echo

    echo "=== case 4: a relocatable .o wearing a .so name is REFUSED, not shipped ==="
    d="$W/only-lookalike"
    mkdir -p "$d"
    cp "$W/bin/libtcmalloc_lookalike.so" "$d/"
    cp "$W/bin/libtcmalloc_allocbench.so-2.params" "$d/"
    old_got=$(old_selector "$d" | sed 's#.*/##')
    new_got=$(new_selector "$d"); new_rc=$?
    echo "  old selector took : ${old_got:-<nothing>} ($(elf_kind "$d/${old_got:-nonexistent}"))"
    echo "  new selector took : ${new_got:-<nothing>}  (exit $new_rc)"
    if [ "$new_rc" -ne 0 ] && [ -z "$new_got" ]; then
        pass "the new selector REFUSES rather than shipping an ET_REL object."
    else
        fail "the new selector accepted '$new_got', which is not a shared object"
    fi
    echo "  and it says why, on stderr:"
    new_selector_loud "$d" 2>&1 >/dev/null | sed 's/^/    /'
    echo

    echo "=== case 5: can the guard itself fail? ==="
    d="$W/mutation"
    mkdir -p "$d"
    printf 'not an elf at all\n' > "$d/libtcmalloc_text.so"
    if new_selector "$d" >/dev/null 2>&1; then
        fail "pick_elf_so ACCEPTED a plain text file -- the guard cannot fail"
    else
        pass "pick_elf_so refuses a tree with no shared object in it."
    fi
    cp "$W/bin/libtcmalloc_allocbench.so" "$d/"
    if new_selector "$d" >/dev/null 2>&1; then
        pass "and accepts as soon as a real one is present -- so it is not refusing everything."
    else
        fail "pick_elf_so refused a tree that DOES contain a shared object"
    fi
    echo

    echo "=== case 6: the ARCHIVE selector, which is the path most cells take ==="
    d="$W/archives"
    mkdir -p "$d"
    "${AR:-ar}" rcs "$d/liballoc_real.a" "$W/bin/libtcmalloc_lookalike.so" 2>/dev/null || {
        echo "  (could not build an archive here)"; }
    printf 'GNU ld script: INPUT(-lfoo)\n' > "$d/liballoc_script.a"
    cp "$W/bin/libtcmalloc_allocbench.so" "$d/liballoc_elf.a"
    for f in "$d"/*.a; do printf '  %-28s %s\n' "$(basename "$f")" "$(ar_kind "$f")"; done
    old_a=$(find "$d" -name 'liballoc*.a' | head -1 | sed 's#.*/##')
    new_a=$(find "$d" -name 'liballoc*.a' | sort | pick_ar 2>/dev/null | sed 's#.*/##')
    echo "  old selector took : ${old_a:-<nothing>} ($(ar_kind "$d/${old_a:-nonexistent}"))"
    echo "  new selector took : ${new_a:-<nothing>} ($(ar_kind "$d/${new_a:-nonexistent}"))"
    if [ "$(ar_kind "$d/${new_a:-nonexistent}")" = "ar-archive" ]; then
        pass "pick_ar takes the real archive and passes over the linker script and the ELF."
    else
        fail "pick_ar took '${new_a:-<nothing>}', which is not an archive"
    fi
    rm -f "$d/liballoc_real.a"
    if find "$d" -name 'liballoc*.a' | sort | pick_ar >/dev/null 2>&1; then
        fail "pick_ar ACCEPTED a tree with no archive in it -- the guard cannot fail"
    else
        pass "and refuses when no candidate is an archive."
    fi
    echo

    echo "=== elf_kind and ar_kind tell their states apart ==="
    printf '  %-24s %s\n' "a shared object:"   "$(elf_kind "$W/bin/libtcmalloc_allocbench.so")"
    printf '  %-24s %s\n' "a relocatable .o:"  "$(elf_kind "$W/bin/libtcmalloc_lookalike.so")"
    printf '  %-24s %s\n' "a text file:"       "$(elf_kind "$W/bin/libtcmalloc_allocbench.so-2.params")"
    printf '  %-24s %s\n' "a file that is not there:" "$(elf_kind "$W/bin/nonexistent")"
    printf '  %-24s %s\n' "ar_kind on a .so:" "$(ar_kind "$W/bin/libtcmalloc_allocbench.so")"
    echo

    echo "=== what this probe cannot tell you ==="
    echo "- WHICH file run 33749457837 actually copied. That artefact expired"
    echo "  before the diagnosis; the .params file is an inference from the glob"
    echo "  and the 'file format not recognized' message. The fix does not rest"
    echo "  on it."
    echo "- whether tcmalloc's number reproduces. That needs another dispatch"
    echo "  with this fix in the tree."
} > "$TRANSCRIPT" 2>&1

cat "$TRANSCRIPT"
exit "$rc"
