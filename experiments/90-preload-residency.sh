#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/experiments/out/90-preload-residency.txt"
RUNNER="$ROOT/target/release/alloc-runner"

command -v cc >/dev/null 2>&1 || { echo "no cc on PATH" >&2; exit 2; }
[ -x "$RUNNER" ] || { echo "alloc-runner is not built: cargo build --release -p alloc-runner" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-90-preload.$$"
trap 'rm -rf "$W"' EXIT INT TERM
mkdir -p "$W/corpus" || exit 2

rc=0
fail() { rc=1; echo " $1"; }

{
    echo "=== conditions ==="
    echo "date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:    $(uname -srm)"
    echo "cc:      $(cc --version 2>/dev/null | head -1)"
    echo "runner:  $RUNNER"
    echo "scratch: $W"
    echo

    # A corpus small enough to generate in a second. preload-check runs the
    # subject over it; the subject ignores the arguments, because the probe is
    # about what the LOADER did rather than about searching anything.
    "$RUNNER" gen-corpus --out "$W/corpus" --profile smoke --seed 1 >/dev/null 2>&1 \
        || { echo "could not generate a corpus"; exit 2; }

    cat > "$W/subject.c" <<'EOS'
#include <time.h>
int main(void) { struct timespec t = {0, 300000000L}; nanosleep(&t, 0); return 0; }
EOS
    cc -o "$W/subject" "$W/subject.c" 2>"$W/cc0.log" \
        || { echo "could not build the subject:"; cat "$W/cc0.log"; exit 2; }
    SUBJECT="$W/subject"
    echo "subject: $SUBJECT, sleeps 300 ms; interpreter $(readelf -l "$SUBJECT" 2>/dev/null | sed -n "s/.*interpreter: \(.*\)\]/\1/p")"

    cat > "$W/fake.c" <<'EOC'
#include <stddef.h>
void *mi_malloc(size_t n);
void  mi_free(void *p);
void *mi_malloc(size_t n) { (void)n; return 0; }
void  mi_free(void *p)    { (void)p; }
EOC
    cc -shared -fPIC -o "$W/liballocbench.so" "$W/fake.c" 2>"$W/cc.log" \
        || { echo "could not build the stand-in library:"; cat "$W/cc.log"; exit 2; }
    echo "stand-in library: $W/liballocbench.so ($(wc -c < "$W/liballocbench.so") bytes)"
    echo "  exports:        $(nm -D --defined-only "$W/liballocbench.so" 2>/dev/null | awk '{print $3}' | tr '\n' ' ')"
    echo

    run_case() {   # $1 = label, $2 = --so path, $3 = expected exit, $4 = allocator
        echo "--- $1"
        echo "    --so $2"
        "$RUNNER" preload-check --bin "$SUBJECT" --so "$2" --corpus "$W/corpus" \
            --expect-allocator "$4" --runs 3 > "$W/out.json" 2>"$W/err.txt"
        got=$?
        python3 - "$W/out.json" <<'EOP' 2>/dev/null || cat "$W/out.json"
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception as e: print("    (no JSON: %s)"%e); raise SystemExit
w=d.get("with_preload",{}); o=d.get("without_preload",{})
print("    with LD_PRELOAD:    resident %s of %s sampled" % (w.get("library_resident"), w.get("subject_sampled")))
print("    without (control):  resident %s of %s sampled" % (o.get("library_resident"), o.get("subject_sampled")))
if d.get("map_line"): print("    map line: %s" % d["map_line"])
for r in d.get("reasons",[]): print("    reason: %s" % r)
EOP
        echo "    exit $got, wanted $3"
        [ "$got" = "$3" ] || fail "$1: exit $got, wanted $3"
        echo
    }

    echo "=== case 1: a library the loader takes -- must PASS ==="
    run_case "preloaded stand-in" "$W/liballocbench.so" 0 mimalloc

    echo "=== case 2: a library that is not there at all ==="
    echo "(preload-check sets LD_PRELOAD itself, so 'nobody preloaded it' is not"
    echo " reachable from outside; the reachable neighbour is a library the tool"
    echo " cannot read.  That is exit 2 -- could not run -- and never 0.)"
    run_case "a path that does not exist" "$W/absent.so" 2 mimalloc

    echo "=== case 3: a library the subject maps ANYWAY -- the control must fire ==="
    libc=$(ldd "$SUBJECT" 2>/dev/null | awk '/libc\.so/ {print $3; exit}')
    if [ -z "$libc" ] || [ ! -f "$libc" ]; then
        echo " SKIPPED: could not locate the libc the subject loads (ldd said nothing)."
        echo "  A skip is not a pass: the control is UNVERIFIED on this host."
        rc=2
    else
        echo "    the subject loads: $libc"
        run_case "libc, which is resident either way" "$libc" 1 mimalloc
        if grep -q 'does not distinguish' "$W/err.txt" 2>/dev/null; then
            echo "     and it failed for the RIGHT reason: the control fired."
        else
            fail "case 3 failed, but not on the control -- read err.txt"
            sed 's/^/      | /' "$W/err.txt"
        fi
        echo
    fi

    echo "=== what this establishes ==="
    echo " preload-check distinguishes a library the loader took from one it"
    echo "   did not, and its negative control CAN fail -- case 3 makes it fail."
    echo " Without case 3 the pair would be indistinguishable from a check that"
    echo "   always answers yes to the positive and no to the control, which is"
    echo "   what the first draft of preload.rs did."
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether the mapped library actually SERVED the allocations. The"
    echo "  stand-in here deliberately does not define malloc. finish_so asserts"
    echo "  the dynamic export of malloc on the real recipes; the two checks"
    echo "  together are the argument and neither alone is."
    echo "- anything about musl. This host is glibc; the alpine cells exercise"
    echo "  the musl loader and are the real test."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
