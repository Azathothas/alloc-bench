#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/experiments/out/130-libc-surgery-after-the-guard.txt"
RUNNER="$ROOT/target/x86_64-unknown-linux-musl/release/alloc-runner"
mkdir -p "$ROOT/experiments/out"

command -v docker >/dev/null 2>&1 || { echo "no docker on PATH" >&2; exit 2; }
[ -x "$RUNNER" ] || {
    echo "no $RUNNER" >&2
    echo "cargo build --release -p alloc-runner --target x86_64-unknown-linux-musl" >&2
    exit 2
}

CA=""
for c in "$ROOT"/images/extra-ca/*.crt; do
    [ -f "$c" ] && { CA=$c; break; }
done

W="${TMPDIR:-/tmp}/alloc-bench-130.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

cat > "$W/probe.sh" <<'PROBE'
set -u
# shellcheck disable=SC1091
. /examples/verify.sh
trust_extra_ca >/dev/null
eval "$SETUP" || { echo "setup failed" >&2; exit 2; }

echo "  cc:   $(cc --version 2>/dev/null | head -1)"
echo "  ar:   $(ar --version 2>&1 | head -1)"
LIBC=$(cc -print-file-name=libc.a 2>/dev/null)
case "$LIBC" in libc.a|"") LIBC=/usr/lib/libc.a ;; esac
echo "  libc: $LIBC ($(ar t "$LIBC" | wc -l | tr -d ' ') members)"
before_members=$(ar t "$LIBC" | wc -l | tr -d ' ')
before_bytes=$(wc -c < "$LIBC")

cat > /tmp/plain.c <<'C'
#include <stddef.h>
static char pool[4 << 20];
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
int standin_marker(void) { return 4242; }
C
cc -c -O0 -o /tmp/plain.o /tmp/plain.c || { echo "stand-in build failed" >&2; exit 2; }
ar rcs /tmp/plain.a /tmp/plain.o        || { echo "stand-in archive failed" >&2; exit 2; }

echo
echo "  -- running scripts/build/libc-surgery.sh, unmodified"
set +e
sh /repo/scripts/build/libc-surgery.sh /tmp/plain.a /repo-runner >/tmp/surgery.log 2>&1
rc=$?
set -e
sed 's/^/     /' /tmp/surgery.log
echo "  exit status: $rc"
echo "SURGERY_RC=$rc"

after_members=$(ar t "$LIBC" | wc -l | tr -d ' ')
after_bytes=$(wc -c < "$LIBC")
echo "  libc.a members: $before_members -> $after_members   bytes: $before_bytes -> $after_bytes"
[ "$before_bytes" = "$after_bytes" ] && echo "LIBC_UNCHANGED=1" || echo "LIBC_UNCHANGED=0"

if [ "$rc" -eq 0 ]; then
    echo
    echo "  -- link and RUN something against the spliced archive"
    printf '#include <stdlib.h>\n#include <string.h>\nint standin_marker(void);\nint main(void){for(int i=0;i<64;i++){char*p=malloc(1024);if(!p)return 1;memset(p,i,1024);free(p);}char*q=calloc(16,16);if(!q)return 3;return standin_marker()==4242?0:2;}\n' > /tmp/t.c
    if cc -static -no-pie -O1 -o /tmp/t /tmp/t.c >/tmp/link.log 2>&1; then
        echo "     it links"
        if /tmp/t; then echo "RUN_OK=1"; echo "     and it runs, exit 0"
        else echo "RUN_OK=0"; echo "      it links but exits $?"; fi
        echo "     standin_marker in the binary: $(nm --defined-only /tmp/t 2>/dev/null | grep -cE ' [TtWw] standin_marker$')"
        echo "     mallocng internals left:      $(nm --defined-only /tmp/t 2>/dev/null | grep -cE ' [TtWw] (nontrivial_free|get_meta)$')"
    else
        echo "RUN_OK=0"
        echo "      it does not link:"
        grep -oE "undefined [a-z ]*symbol: [A-Za-z_][A-Za-z0-9_]*|undefined reference to .[^'\`]+." /tmp/link.log \
            | sort -u | head -6 | sed 's/^/       /'
    fi
fi
PROBE

rc=0
ok()  { echo "  PASS  $1"; }
bad() { echo "   FAIL  $1"; rc=1; }

run_one() {   # $1 = label, $2 = image, $3 = setup
    mkdir -p "$W/$1"
    set -- --rm \
        -v "$ROOT/examples:/examples:ro" \
        -v "$ROOT/scripts:/repo/scripts:ro" \
        -v "$RUNNER:/repo-runner:ro" \
        -v "$W/probe.sh:/probe.sh:ro" \
        -e "SETUP=$3" "$2"
    [ -n "$CA" ] && set -- -v "$CA:/tmp/extra-ca.crt:ro" "$@"
    docker run "$@" sh /probe.sh 2>&1
}

{
    echo "=== conditions ==="
    echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:   $(uname -srm)"
    echo "runner: $RUNNER (musl static-PIE, so it starts in these images)"
    echo

    echo "=== alpine: the script must COMPLETE and the result must RUN ==="
    run_one alpine alpine:latest \
        'apk add --no-cache build-base musl-dev binutils >/dev/null 2>&1' > "$W/alpine.log" 2>&1
    sed 's/^/  /' "$W/alpine.log"
    echo
    grep -q 'SURGERY_RC=0' "$W/alpine.log" \
        && ok "the real script exits 0 on Alpine" \
        || bad "the real script did not exit 0 on Alpine"
    grep -q 'nothing stranded' "$W/alpine.log" \
        && ok "and the new guard reports nothing stranded" \
        || bad "the new guard did not report on Alpine"
    grep -q 'RUN_OK=1' "$W/alpine.log" \
        && ok " a program linked against the spliced libc.a RUNS and returns 0" \
        || bad "the spliced libc.a did not produce a working binary"
    echo

    echo "=== chimera: the script must REFUSE, and leave libc.a alone ==="
    run_one chimera chimeralinux/chimera:latest \
        'apk update >/dev/null 2>&1; apk add chimerautils base-devel base-devel-static clang lld >/dev/null 2>&1' \
        > "$W/chimera.log" 2>&1
    sed 's/^/  /' "$W/chimera.log"
    echo
    grep -q 'SURGERY_RC=1' "$W/chimera.log" \
        && ok "the real script exits 1 on Chimera" \
        || bad "the real script did not exit 1 on Chimera"
    grep -q '__malloc_tls_default' "$W/chimera.log" \
        && ok "and it NAMES __malloc_tls_default rather than failing at link time" \
        || bad "it did not name the stranded symbol"
    grep -q 'LIBC_UNCHANGED=1' "$W/chimera.log" \
        && ok " libc.a is byte-identical afterwards -- it refused before writing" \
        || bad "libc.a was modified despite the refusal"
    echo

    echo "exit: $rc"
} > "$OUT" 2>&1

cat "$OUT"
exit $rc
