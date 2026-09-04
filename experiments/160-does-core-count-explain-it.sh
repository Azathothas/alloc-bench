#!/bin/sh
set -u

OUT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/out" 2>/dev/null && pwd) || {
    echo "experiments/out is missing" >&2
    exit 2
}
OUT="$OUT_DIR/160-does-core-count-explain-it.txt"
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BENCH="$ROOT/target/release/alloc-bench"

[ -x "$BENCH" ] || { echo "alloc-bench is not built" >&2; exit 2; }
command -v nproc >/dev/null 2>&1 || { echo "no nproc" >&2; exit 2; }

NCPU=$(nproc)
if [ "$NCPU" -lt 4 ]; then
    echo "this host has $NCPU CPU(s); the experiment needs at least 4 to halve them" >&2
    exit 2
fi
HALF=$(( NCPU / 2 ))
FULL_SET="0-$(( NCPU - 1 ))"
HALF_SET="0-$(( HALF - 1 ))"

W="${TMPDIR:-/tmp}/alloc-bench-160.$$"
trap 'rm -rf "$W"' EXIT INT TERM

rc=0
fail() { rc=1; echo " $1"; }

# The ordering of one run's `alpine` group, fastest first, as one line.
ordering() {   # $1 = dataset dir
    python3 - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1] + "/rankings.json"))
except Exception as e:
    print(f"UNREADABLE: {e}")
    raise SystemExit(0)
for g in d.get("groups", []):
    rows = [r for r in g["rows"] if r.get("rel_time") is not None]
    rows.sort(key=lambda r: r["rel_time"])
    print(" < ".join(f"{r['allocator']}({r['rel_time']:.3f})" for r in rows))
    break
PY
}

{
    echo "=== conditions ==="
    echo "date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:     $(uname -srm)"
    echo "cpu:      $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
    echo "cpus:     $NCPU  (threads per core: $(lscpu 2>/dev/null | awk -F: '/Thread\(s\) per core/{gsub(/ /,"",$2);print $2}'))"
    echo "tree:     $ROOT at $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "cpusets:  A=$FULL_SET (whole host)   B=$HALF_SET (half)   C=$FULL_SET (control)"
    echo "scratch:  $W"
    echo
    echo " These datasets are NOT published: every container in run B is pinned,"
    echo "   so its run.json records host.cpuset and check-snapshots.py rule 6"
    echo "   would refuse it without a note. They exist to be compared here."
    echo

    mkdir -p "$W" || exit 2

    for run in A B C; do
        case "$run" in
            A|C) set_cpus=''        ; label="whole host ($FULL_SET)" ;;
            B)   set_cpus="$HALF_SET"; label="pinned ($HALF_SET)" ;;
        esac
        echo "=== run $run: $label ==="
        started=$(date +%s)
        if [ -n "$set_cpus" ]; then
            ALLOC_BENCH_CPUSET="$set_cpus" "$BENCH" run \
                --suite core --arch x86_64 --distro alpine \
                --out "$W/$run" >"$W/$run.log" 2>&1
        else
            "$BENCH" run \
                --suite core --arch x86_64 --distro alpine \
                --out "$W/$run" >"$W/$run.log" 2>&1
        fi
        code=$?
        echo "  exit $code, $(( $(date +%s) - started ))s"
        grep -E '^\[ *[0-9]+/' "$W/$run.log" | sed 's/^/    /' | head -10
        if [ "$code" -ne 0 ]; then
            fail "run $run exited $code; see $W/$run.log"
        fi
        recorded=$(python3 -c "
import json,sys
try: print((json.load(open('$W/$run/run.json')).get('host') or {}).get('cpuset') or '(none)')
except Exception: print('(no run.json)')")
        echo "  run.json host.cpuset: $recorded"
        case "$run" in
            A|C) [ "$recorded" = "(none)" ] || fail "run $run recorded a cpuset ($recorded) and should not have" ;;
            B)   [ "$recorded" = "$HALF_SET" ] || fail "run B recorded cpuset '$recorded', expected '$HALF_SET'" ;;
        esac
        echo
    done

    echo "=== the magnitudes: wander against effect ==="
    python3 - "$W/A" "$W/B" "$W/C" <<'MAG'
import json, sys

def rel(d):
    try:
        doc = json.load(open(d + "/rankings.json"))
    except Exception:
        return {}
    for g in doc.get("groups", []):
        return {r["allocator"]: r["rel_time"]
                for r in g["rows"]
                if r.get("rel_time") is not None and not r.get("is_baseline")}
    return {}

A, B, C = (rel(p) for p in sys.argv[1:4])
common = sorted(set(A) & set(B) & set(C))
if not common:
    print("  (no allocator was measured in all three runs)")
    raise SystemExit(0)
print(f"  {'allocator':18s} {'A':>7s} {'C':>7s} {'wander':>9s} {'B':>7s} {'effect':>9s}")
ws, es = [], []
for k in common:
    m = (A[k] + C[k]) / 2
    w = abs(A[k] - C[k]) / m * 100
    e = (B[k] - m) / m * 100
    ws.append(w); es.append(e)
    print(f"  {k:18s} {A[k]:7.3f} {C[k]:7.3f} {w:8.1f}% {B[k]:7.3f} {e:8.1f}%")
print()
print(f"  wander (A vs C, identical conditions) : {min(ws):.1f}% - {max(ws):.1f}%")
print(f"  effect (B vs the mean of A and C)     : {min(es):.1f}% - {max(es):.1f}%")
same = all(e > 0 for e in es) or all(e < 0 for e in es)
print(f"  every candidate moved the same way    : {'yes' if same else 'NO'}")
if same and min(abs(e) for e in es) > max(ws):
    print()
    print("   THE EFFECT IS OUTSIDE THE WANDER, FOR EVERY CANDIDATE, IN ONE")
    print("     DIRECTION. Core count has a measured effect on the SIZE of each")
    print("     allocator's advantage on this host -- a different and weaker")
    print("     claim than 'core count decides the ordering', and the one these")
    print("     numbers actually support.")
else:
    print()
    print("   The effect is NOT cleanly outside the wander, so this run separates")
    print("    neither, and no claim is made about magnitude either.")
MAG
    echo

    echo "=== the orderings ==="
    oa=$(ordering "$W/A"); ob=$(ordering "$W/B"); oc=$(ordering "$W/C")
    printf '  A  whole host : %s\n' "$oa"
    printf '  B  pinned     : %s\n' "$ob"
    printf '  C  whole host : %s\n' "$oc"
    echo

    # Names only, so the comparison is about ORDER and not about magnitudes,
    # which §9 says this project cannot pin down anyway.
    names() { printf '%s\n' "$1" | sed 's/([^)]*)//g'; }
    na=$(names "$oa"); nb=$(names "$ob"); nc=$(names "$oc")

    echo "=== what that means ==="
    if [ "$na" = "$nc" ]; then
        echo "   A and C agree: this host reproduced its own ordering."
        if [ "$na" = "$nb" ]; then
            echo "   AND B AGREES TOO: halving the core count did NOT move the"
            echo "     ordering on this host. The standing first hypothesis ---"
            echo "     that core count is what separates the sandbox from the"
            echo "     GitHub runner --- gets NO support here."
            echo "      That is a publishable negative result, and it is the"
            echo "     one this experiment was written to be able to report."
        else
            echo "   AND B DIFFERS: with A and C agreeing, the difference at B"
            echo "     is attributable to the core count rather than to wander."
            echo "     This is the first support the hypothesis has ever had."
        fi
    else
        echo "   A AND C DISAGREE, so this host does not reproduce its own"
        echo "     ordering and B tells us nothing about core count. That is"
        echo "     itself the finding: docs/AGENTS.md item 11 recorded the"
        echo "     same host wandering, and this is a second instance under a"
        echo "     design built to detect it."
        echo "      The experiment is not invalid --- its CONTROL fired, which"
        echo "       is what a control is for. And the MAGNITUDE table above may"
        echo "       still separate cleanly even when the ORDER does not: the"
        echo "       candidates sit within a few percent of each other, so the"
        echo "       wander swamps the gaps BETWEEN them while leaving each"
        echo "       one's distance from the control readable."
    fi

    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether core count explains it on any OTHER host. One machine."
    echo "- whether 2 of 4 pinned cores behaves like a 2-core machine. Cache,"
    echo "  memory bandwidth and the scheduler's view all differ, which is why"
    echo "  T-025's option (3) stays open."
    echo "- anything about SMT: this host reports 1 thread per core, so the"
    echo "  hypothesis's OTHER half cannot be varied here at all."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
