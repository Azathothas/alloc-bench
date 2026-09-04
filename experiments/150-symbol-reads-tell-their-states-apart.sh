#!/bin/sh
set -u

OUT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/out" 2>/dev/null && pwd) || {
    echo "experiments/out is missing" >&2
    exit 2
}
OUT="$OUT_DIR/150-symbol-reads-tell-their-states-apart.txt"
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

command -v cc >/dev/null 2>&1 || { echo "no cc on PATH" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-150-symbol-reads.$$"
trap 'rm -rf "$W"' EXIT INT TERM

rc=0
fail() { rc=1; echo " $1"; }

{
    echo "=== conditions ==="
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host: $(uname -srm)"
    echo "cc:   $(cc --version 2>&1 | head -1)"
    echo "nm:   $(nm --version 2>&1 | head -1)"
    echo "tree: $ROOT at $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo

    rm -rf "$W"; mkdir -p "$W" || exit 2

    # 1. a library that exports the four required symbols.
    cat > "$W/full.c" <<'EOF'
#include <stddef.h>
void *malloc(size_t n)             { (void)n; return 0; }
void  free(void *p)                { (void)p; }
void *realloc(void *p, size_t n)   { (void)p; (void)n; return 0; }
void *calloc(size_t n, size_t m)   { (void)n; (void)m; return 0; }
EOF
    cc -shared -fPIC -o "$W/full.so" "$W/full.c" 2>/dev/null || exit 2

    # 2. a library that exports something else, but not malloc.
    cat > "$W/other.c" <<'EOF'
int  answer(void)      { return 42; }
int  another(void)     { return 43; }
EOF
    cc -shared -fPIC -o "$W/other.so" "$W/other.c" 2>/dev/null || exit 2

    printf '{ local: *; };\n' > "$W/hide.map"
    cc -shared -fPIC -Wl,--version-script="$W/hide.map" \
        -o "$W/empty.so" "$W/full.c" 2>/dev/null || exit 2

    # 4. a file nm cannot read.
    printf 'this is not an ELF shared object at all\n' > "$W/notelf.so"

    printf '  %-12s %-10s %s\n' object bytes 'defined dynamic symbols'
    for o in full other empty; do
        printf '  %-12s %-10s %s\n' "$o.so" "$(wc -c < "$W/$o.so")" \
            "$(nm -D --defined-only "$W/$o.so" 2>/dev/null | grep -c '[^[:space:]]')"
    done
    printf '  %-12s %-10s %s\n' notelf.so "$(wc -c < "$W/notelf.so")" \
        "$(nm -D --defined-only "$W/notelf.so" >/dev/null 2>&1 && echo readable || echo 'nm REFUSES it')"
    echo

    run_finish_so() {   # $1 = object
        d="$W/stage-$(basename "$1" .so)"
        rm -rf "$d"; mkdir -p "$d/lib" "$d/src"
        cp "$1" "$d/lib/liballocbench.so"
        (
            SRC="$d/src"; OUT="$d"
            MODE=preload; PIC=1; LIBC=glibc; TARGET_ARCH=x86_64
            export SRC OUT MODE PIC LIBC TARGET_ARCH
            # shellcheck source=/dev/null
            . "$ROOT/allocators/lib.sh"
            finish_so malloc free realloc calloc
        ) 2>&1
    }

    echo "=== the real finish_so, against each ==="
    for case in "full:0:accepted" "other:1:refused" "empty:1:refused" "notelf:2:could-not-run"; do
        o=${case%%:*}; rest=${case#*:}; want=${rest%%:*}; label=${rest#*:}
        out=$(run_finish_so "$W/$o.so"); got=$?
        printf '\n  --- %s.so (%s) ---\n' "$o" "$label"
        printf '%s\n' "$out" | sed 's/^/      | /' | head -12
        printf '      exit %s (expected %s)\n' "$got" "$want"
        [ "$got" -eq "$want" ] || fail "$o.so: expected exit $want, got $got"
    done

    echo
    echo "=== the two states that used to be one ==="
    e_out=$(run_finish_so "$W/empty.so")
    n_out=$(run_finish_so "$W/notelf.so")
    if printf '%s' "$e_out" | grep -q 'exports NOTHING AT ALL'; then
        echo "   empty.so is named as exporting nothing, in words"
    else
        fail "empty.so produced no 'exports NOTHING AT ALL' line"
    fi
    if printf '%s' "$n_out" | grep -q 'cannot read the dynamic symbol table'; then
        echo "   notelf.so is named as unreadable, and exits 2 rather than 1"
    else
        fail "notelf.so was not reported as unreadable"
    fi
    if [ "$e_out" = "$n_out" ]; then
        fail "the two produce IDENTICAL output -- the defect is back"
    else
        echo "   their output differs, which is the whole point"
    fi

    echo
    echo "=== the archive counterpart, finish() ==="
    command -v ar >/dev/null 2>&1 || { echo "  (no ar on PATH; cannot build archives)"; exit 2; }
    cc -c -o "$W/full.o"  "$W/full.c"  2>/dev/null || exit 2
    cc -c -o "$W/other.o" "$W/other.c" 2>/dev/null || exit 2
    ar rcs "$W/full.a"  "$W/full.o"  2>/dev/null || exit 2
    ar rcs "$W/other.a" "$W/other.o" 2>/dev/null || exit 2
    ar rcs "$W/empty.a"                2>/dev/null || exit 2
    printf 'not an archive\n' > "$W/notar.a"

    run_finish() {   # $1 = archive, $2 = MODE
        d="$W/astage-$(basename "$1" .a)-$2"
        rm -rf "$d"; mkdir -p "$d/lib" "$d/src"
        cp "$1" "$d/lib/liballocbench.a"
        (
            SRC="$d/src"; OUT="$d"
            MODE=$2; PIC=1; LIBC=glibc; TARGET_ARCH=x86_64
            export SRC OUT MODE PIC LIBC TARGET_ARCH
            # shellcheck source=/dev/null
            . "$ROOT/allocators/lib.sh"
            finish malloc free realloc calloc
        ) 2>&1
    }

    for case in "full:override:0:accepted" "other:override:1:refused" \
                "empty:override:1:refused" "notar:override:2:could-not-run"; do
        o=${case%%:*}; r1=${case#*:}; m=${r1%%:*}; r2=${r1#*:}; want=${r2%%:*}; label=${r2#*:}
        out=$(run_finish "$W/$o.a" "$m"); got=$?
        printf '\n  --- %s.a, MODE=%s (%s) ---\n' "$o" "$m" "$label"
        printf '%s\n' "$out" | sed 's/^/      | /' | head -8
        printf '      exit %s (expected %s)\n' "$got" "$want"
        [ "$got" -eq "$want" ] || fail "$o.a/$m: expected exit $want, got $got"
    done

    echo
    echo "=== the check that failed OPEN: MODE=prefixed over an archive defining malloc ==="
    out=$(run_finish "$W/full.a" prefixed); got=$?
    printf '%s\n' "$out" | sed 's/^/      | /' | head -4
    printf '      exit %s (expected 1)\n' "$got"
    [ "$got" -eq 1 ] || fail "prefixed over a malloc-defining archive: expected 1, got $got"
    out=$(run_finish "$W/notar.a" prefixed); got=$?
    printf '      an unreadable archive in prefixed mode: exit %s (expected 2, NOT 0)\n' "$got"
    [ "$got" -eq 2 ] || fail "prefixed over an unreadable archive: expected 2, got $got"

    echo
    echo "=== what this establishes ==="
    echo " \`cmd 2>/dev/null | grep -q\` reads GREP's exit code. A tool that"
    echo "   failed to run reads exactly like a subject that lacks the thing"
    echo "   being looked for, and the second is what gets written down."
    echo " finish and finish_so now read the table ONCE, exit 2 when they"
    echo "   cannot read it at all, and say 'NOTHING AT ALL' in words rather"
    echo "   than printing a header over an empty list."
    echo " And one of the four checks failed OPEN rather than closed: the"
    echo "   prefixed-mode assertion asks whether malloc IS defined, so a"
    echo "   broken nm answered 'no' and let the archive through. That one"
    echo "   would not have failed a build; it would have made two mechanisms"
    echo "   the same experiment and published them as two."
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- what tcmalloc's own shared object contains. Bazel cannot run on this"
    echo "  host, and case 3 is a library shaped LIKE the one that run produced,"
    echo "  not that library. docs/history/todo/mechanisms.md T-003 names the dispatch that"
    echo "  would answer it."
    echo "- whether an exported malloc actually interposes. Nothing a build step"
    echo "  can see establishes that; alloc-runner preload-check does, against"
    echo "  the running process."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
