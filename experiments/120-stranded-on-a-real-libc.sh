#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/experiments/out/120-stranded-on-a-real-libc.txt"
RUNNER="$ROOT/target/release/alloc-runner"
mkdir -p "$ROOT/experiments/out"

command -v docker >/dev/null 2>&1 || { echo "no docker on PATH" >&2; exit 2; }
[ -x "$RUNNER" ] || { echo "no $RUNNER -- cargo build --release -p alloc-runner" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-120.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

CA=""
for c in "$ROOT"/images/extra-ca/*.crt; do
    [ -f "$c" ] && { CA=$c; break; }
done

cat > "$W/splice.sh" <<'SPLICE'
set -u
# shellcheck disable=SC1091
. /examples/verify.sh
trust_extra_ca >/dev/null
eval "$SETUP" || { echo "setup failed" >&2; exit 2; }

LIBC=$(cc -print-file-name=libc.a 2>/dev/null)
case "$LIBC" in libc.a|"") LIBC=/usr/lib/libc.a ;; esac
[ -f "$LIBC" ] || { echo "no libc.a at $LIBC" >&2; exit 2; }
echo "libc.a: $LIBC ($(ar t "$LIBC" | wc -l) members)"

ALLOC_SYMS='malloc free calloc realloc aligned_alloc posix_memalign malloc_usable_size'
MEMBERS=$(nm --defined-only "$LIBC" 2>/dev/null | awk -v syms="$ALLOC_SYMS" '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    NF >= 3 {
        n = split(syms, want, " ")
        for (i = 1; i <= n; i++)
            if ($3 == want[i] && $2 ~ /^[TtWwDdBb]$/) { print m; next }
    }' | sort -u)
echo "members deleted: $(printf '%s ' $MEMBERS)"

cat > /tmp/plain.c <<'C'
#include <stddef.h>
static char pool[1 << 20];
static size_t used;
void *malloc(size_t n) { n = (n + 15) & ~(size_t)15;
    if (used + n > sizeof pool) return 0; void *p = pool + used; used += n; return p; }
void free(void *p) { (void)p; }
void *calloc(size_t a, size_t b) { size_t n = a * b; char *p = malloc(n);
    if (p) for (size_t i = 0; i < n; i++) p[i] = 0; return p; }
void *realloc(void *p, size_t n) { (void)p; return malloc(n); }
void *aligned_alloc(size_t a, size_t n) { (void)a; return malloc(n); }
int posix_memalign(void **r, size_t a, size_t n) { (void)a; *r = malloc(n); return *r ? 0 : 12; }
size_t malloc_usable_size(void *p) { (void)p; return 0; }
C
cat > /tmp/aliases.c <<'C'
#include <stddef.h>
void *malloc(size_t); void free(void *); void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void *__libc_malloc(size_t n) { return malloc(n); }
void __libc_free(void *p) { free(p); }
void *__libc_calloc(size_t a, size_t b) { return calloc(a, b); }
void *__libc_realloc(void *p, size_t n) { return realloc(p, n); }
C
cc -c -O0 -o /tmp/plain.o /tmp/plain.c   || exit 2
cc -c -O0 -o /tmp/aliases.o /tmp/aliases.c || exit 2
ar rcs /tmp/plain.a /tmp/plain.o                 || exit 2
ar rcs /tmp/full.a  /tmp/plain.o /tmp/aliases.o  || exit 2

cp "$LIBC" /out/before.a
for variant in plain full; do
    {
        echo "CREATE /out/after-$variant.a"
        echo "ADDLIB /out/before.a"
        for m in $MEMBERS; do echo "DELETE $m"; done
        echo "ADDLIB /tmp/$variant.a"
        echo "SAVE"
        echo "END"
    } > /tmp/$variant.mri
    ar -M < /tmp/$variant.mri || { echo "ar -M failed for $variant" >&2; exit 2; }
    echo "after-$variant.a: $(ar t "/out/after-$variant.a" | wc -l) members"
done
SPLICE

run_one() {   # $1 = label, $2 = image, $3 = setup command
    label=$1; image=$2; setup=$3
    mkdir -p "$W/$label"
    echo "=== $label ($image) ==="
    set -- --rm -v "$ROOT/examples:/examples:ro" -v "$W/$label:/out" \
        -e "SETUP=$setup"
    [ -n "$CA" ] && set -- "$@" -v "$CA:/tmp/extra-ca.crt:ro"
    if ! docker run "$@" -v "$W/splice.sh:/splice.sh:ro" "$image" sh /splice.sh 2>&1 \
        | sed 's/^/  /'; then
        echo "   the splice could not be produced"
        return 2
    fi
    return 0
}

rc=0
{
    echo "=== conditions ==="
    echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:   $(uname -srm)"
    echo "runner: $RUNNER"
    echo

    run_one alpine alpine:latest \
        'apk add --no-cache build-base musl-dev binutils >/dev/null 2>&1' || rc=2
    echo
    run_one chimera chimeralinux/chimera:latest \
        'apk update >/dev/null 2>&1; apk add chimerautils base-devel base-devel-static clang lld >/dev/null 2>&1' || rc=2
    echo

    echo "=== what the splice broke, derived rather than listed ==="
    for label in alpine chimera; do
        for variant in plain full; do
            a="$W/$label/after-$variant.a"
            b="$W/$label/before.a"
            if [ ! -f "$a" ] || [ ! -f "$b" ]; then
                echo "   $label/$variant: archives were not produced"
                rc=1
                continue
            fi
            got=$("$RUNNER" ar-unresolved --archive "$a" --baseline "$b" 2>&1)
            n=$(printf '%s' "$got" | grep -c . || true)
            printf '  %-8s %-6s -> %s symbol(s): %s\n' \
                "$label" "$variant" "$n" "$(printf '%s' "$got" | tr '\n' ' ')"
        done
    done
    echo

    echo "=== the assertions ==="
    assert() {   # $1 = name, $2 = 0/1
        if [ "$2" -eq 0 ]; then echo "  PASS  $1"; else echo "   FAIL  $1"; rc=1; fi
    }
    ap=$("$RUNNER" ar-unresolved --archive "$W/alpine/after-plain.a"  --baseline "$W/alpine/before.a" 2>/dev/null || true)
    af=$("$RUNNER" ar-unresolved --archive "$W/alpine/after-full.a"   --baseline "$W/alpine/before.a" 2>/dev/null || true)
    cp_=$("$RUNNER" ar-unresolved --archive "$W/chimera/after-plain.a" --baseline "$W/chimera/before.a" 2>/dev/null || true)
    cf=$("$RUNNER" ar-unresolved --archive "$W/chimera/after-full.a"  --baseline "$W/chimera/before.a" 2>/dev/null || true)

    printf '%s' "$ap" | grep -q '__libc_malloc' && assert "alpine/plain names musl's internal aliases" 0 \
        || assert "alpine/plain names musl's internal aliases (got: $(printf '%s' "$ap" | tr '\n' ' '))" 1
    [ -z "$af" ] && assert " alpine/full is EMPTY -- synthesis closes it, so the check can refuse" 0 \
        || assert " alpine/full is EMPTY (got: $(printf '%s' "$af" | tr '\n' ' '))" 1
    printf '%s' "$cp_" | grep -q '__malloc_tls_default' && assert "chimera/plain names __malloc_tls_default" 0 \
        || assert "chimera/plain names __malloc_tls_default (got: $(printf '%s' "$cp_" | tr '\n' ' '))" 1
    [ -n "$cf" ] && assert " chimera/full STILL reports -- synthesis does not rescue it" 0 \
        || assert " chimera/full still reports (it came back empty, which contradicts T-018)" 1

    echo
    echo "exit: $rc"
} > "$OUT" 2>&1

cat "$OUT"
exit $rc
