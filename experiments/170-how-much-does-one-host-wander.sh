#!/bin/sh
set -u

OUT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/out" 2>/dev/null && pwd) || {
    echo "experiments/out is missing" >&2
    exit 2
}
OUT="$OUT_DIR/170-how-much-does-one-host-wander.txt"
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BENCH="$ROOT/target/release/alloc-bench"
WINDOW="$ROOT/results/rolling/core-x86_64/aggregate.json"

[ -x "$BENCH" ] || { echo "alloc-bench is not built" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3" >&2; exit 2; }

N="${ALLOC_BENCH_170_REPEATS:-10}"
case "$N" in
    ''|*[!0-9]*) echo "ALLOC_BENCH_170_REPEATS must be a number, got '$N'" >&2; exit 2 ;;
esac
[ "$N" -ge 3 ] || { echo "N must be at least 3; got $N" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-170"
mkdir -p "$W" || exit 2

rc=0
fail() { rc=1; echo " $1"; }

{
    echo "=== conditions, AT THE MOMENT THIS TRANSCRIPT WAS WRITTEN ==="
    echo " NOT necessarily the conditions the numbers were taken under. This"
    echo "   analysis is resumable, so a re-run re-prints this block while reusing"
    echo "   datasets measured earlier. The machine each RUN recorded is read back"
    echo "   from its own run.json further down, and that table is the one that"
    echo "   establishes the runs are comparable."
    echo "date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:     $(uname -srm)"
    echo "cpu:      $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
    echo "cpus:     $(nproc 2>/dev/null || echo '?')  (threads per core: $(lscpu 2>/dev/null | awk -F: '/Thread\(s\) per core/{gsub(/ /,"",$2);print $2}'))"
    echo "tree:     $ROOT at $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "repeats:  $N, nothing varied --- and CHECKED below, not assumed"
    echo "scratch:  $W  (kept, so the analysis can be re-run without re-measuring)"
    echo
    echo " These datasets are NOT published: they are measured from whatever tree"
    echo "   is checked out, and this project discards such a dataset rather than"
    echo "   annotating it. This transcript is the artefact."
    echo

    i=1
    while [ "$i" -le "$N" ]; do
        d="$W/r$i"
        echo "=== run $i of $N ==="
        if [ -f "$d/rankings.json" ]; then
            echo "  already measured, reusing $d"
        else
            rm -rf "$d"
            started=$(date +%s)
            "$BENCH" run --suite core --arch x86_64 --distro alpine \
                --out "$d" >"$W/r$i.log" 2>&1
            code=$?
            echo "  exit $code, $(( $(date +%s) - started ))s"
            [ "$code" -eq 0 ] || fail "run $i exited $code; see $W/r$i.log"
        fi
        python3 - "$d" <<'PY'
import json, sys
try:
    h = (json.load(open(sys.argv[1] + "/run.json")).get("host") or {})
except Exception as e:
    print(f"   no run.json: {e}")
    raise SystemExit(0)
env = h.get("env") or {}
print(f"  cpuset={h.get('cpuset') or '(none)'}  cpus_allowed={env.get('cpus_allowed') or '?'}"
      f"  thp={env.get('transparent_hugepage') or '?'}"
      f"  page={env.get('page_size_bytes') or '?'}"
      f"  smt={env.get('threads_per_core') or '?'}")
print(f"  cpu={h.get('cpu_model')!r} kernel={h.get('kernel')!r}")
print(f"  caches={env.get('cpu_caches')!r}")
PY
        i=$((i + 1))
    done
    echo

    python3 - "$W" "$N" "$WINDOW" <<'PY'
import json, os, statistics, sys

scratch, n, window_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]

def group_of(d):
    """The first ranking group of one dataset: {allocator: rel_time}, plus MADs."""
    try:
        doc = json.load(open(os.path.join(d, "rankings.json")))
    except Exception:
        return None, None, None
    for g in doc.get("groups", []):
        rel, mad = {}, {}
        for r in g["rows"]:
            if r.get("rel_time") is None or r.get("is_baseline"):
                continue
            rel[r["allocator"]] = r["rel_time"]
            # `rel_mad` is that cell's own median absolute deviation as a
            # FRACTION of its own median - the within-run spread §9 refuses a
            # lead smaller than. It is the quantity this probe measures against.
            if r.get("rel_mad") is not None:
                mad[r["allocator"]] = r["rel_mad"]
        return g.get("group"), rel, mad
    return None, None, None

runs, gname, conds = [], None, []
for i in range(1, n + 1):
    d = os.path.join(scratch, f"r{i}")
    name, rel, mad = group_of(d)
    if not rel:
        print(f" run {i} produced no readable ranking group; the analysis below "
              f"would be over fewer runs than it claims.")
        raise SystemExit(1)
    gname = gname or name
    runs.append((rel, mad))
    try:
        meta = json.load(open(os.path.join(d, "run.json")))
        h = meta.get("host") or {}
        conds.append((i, meta.get("started_at"), h.get("cpu_model"), h.get("kernel"),
                      (h.get("env") or {}).get("cpu_caches"), h.get("cpuset")))
    except Exception as e:
        print(f" run {i} has no readable run.json ({e}), so this probe cannot")
        print( "   establish that it ran on the same machine as the others. That is")
        print( "   the whole premise, so the analysis stops here.")
        raise SystemExit(1)

print("=== the machine each run recorded, read back from its own run.json ===")
print(f"  {'run':>3s}  {'started':20s} {'cpu_model':38s} {'caches':34s} cpuset")
for i, started, cpu, kern, caches, cpuset in conds:
    print(f"  {i:3d}  {started or '?':20s} {cpu or '?':38s} {caches or '?':34s} {cpuset or '(none)'}")
print()
distinct_machines = {(c[2], c[3], c[4]) for c in conds}
distinct_cpusets = {c[5] for c in conds}
if len(distinct_machines) != 1 or len(distinct_cpusets) != 1:
    print(" THE CONDITIONS WERE NOT CONSTANT ACROSS THESE RUNS, so nothing below")
    print("   can be attributed to run-to-run wander: a machine that changed under")
    print("   the experiment produces the same signature. This probe reports that")
    print("   and stops rather than publishing a wander it cannot attribute.")
    for m in sorted(distinct_machines, key=str):
        print(f"   machine: {m}")
    if len(distinct_cpusets) != 1:
        print(f"   cpusets seen: {sorted(distinct_cpusets, key=str)}")
    raise SystemExit(1)
print(f"   all {n} runs record ONE machine, one kernel, one cache geometry and no")
print( "     cpuset. The comparisons below are within a single machine.")
print()

sets = [frozenset(r) for r, _ in runs]
if len(set(sets)) != 1:
    print(" the runs do not share a candidate set, so they cannot be compared:")
    for i, s in enumerate(sets, 1):
        print(f"   run {i}: {sorted(s)}")
    raise SystemExit(1)
allocs = sorted(sets[0])

print(f"=== group: {gname} ===")
print(f"    {n} runs, identical conditions, {len(allocs)} candidates against the control")
print()

CONTROL_NOTE = True

# --------------------------------------------------------------- the orderings
print("=== the ordering, run by run ===")
orders = []
for i, (rel, _) in enumerate(runs, 1):
    o = tuple(sorted(allocs, key=lambda a: rel[a]))
    orders.append(o)
    print(f"  run {i:2d}: " + " < ".join(f"{a}({rel[a]:.3f})" for a in o))
print()
distinct = {}
for o in orders:
    distinct[o] = distinct.get(o, 0) + 1
print(f"  distinct orderings in {n} runs: {len(distinct)}")
for o, c in sorted(distinct.items(), key=lambda kv: -kv[1]):
    print(f"    {c:2d}x  " + " < ".join(o))
top = max(distinct.values())
print()
if len(distinct) == 1:
    print(f"   ONE ordering in {n} runs: this host reproduces its own ordering.")
else:
    print(f"   {len(distinct)} DIFFERENT ORDERINGS IN {n} RUNS ON ONE MACHINE, nothing")
    print(f"     varied. The most frequent occurs {top} of {n} times.")
    print( "      So 'the ordering is a property of the machine' is too strong as")
    print( "       stated: this machine does not have one ordering to be a property of.")
print()

# ------------------------------------------- between-run against within-run
print("=== each candidate: between-run spread against its own within-run MAD ===")
print("   RULES.md §4 says 'a within-run MAD is a floor on the uncertainty, not a")
print("     bound', on the strength of ONE pair of runs whose same-host status")
print("     docs/AGENTS.md item 11 admits it cannot confirm. This is the first")
print("     time this project has measured it over ten runs with the machine")
print("     checked. The answer is printed below whichever way it comes out.")
print()
print(f"  {'allocator':18s} {'median':>7s} {'min':>7s} {'max':>7s} {'range':>7s} "
      f"{'between':>8s} {'within':>7s} {'ratio':>6s}")
stats = {}
for a in allocs:
    vals = [rel[a] for rel, _ in runs]
    med = statistics.median(vals)
    rng = (max(vals) - min(vals)) / med * 100
    between = statistics.median([abs(v - med) for v in vals]) / med * 100
    mads = [mad[a] * 100 for _, mad in runs if a in mad]
    within = statistics.median(mads) if mads else float("nan")
    stats[a] = dict(vals=vals, med=med, lo=min(vals), hi=max(vals),
                    rng=rng, between=between, within=within)
    ratio = between / within if within and within == within and within > 0 else float("nan")
    print(f"  {a:18s} {med:7.3f} {min(vals):7.3f} {max(vals):7.3f} {rng:6.1f}% "
          f"{between:7.1f}% {within:6.1f}% {ratio:5.2f}x")
print()
print("  range   = (max-min)/median over the runs -- grows with N, shown for context")
print("  between = MAD of the per-run medians    -- the like-for-like quantity")
print("  within  = median of each run's own MAD  -- what §9 refuses a lead smaller than")
print()
ratios = [s["between"] / s["within"] for s in stats.values()
          if s["within"] and s["within"] == s["within"] and s["within"] > 0]
if ratios:
    print(f"  between-run MAD is {min(ratios):.2f}x to {max(ratios):.2f}x each cell's own")
    print( "  within-run MAD, MAD against MAD.")
    if min(ratios) >= 1.0:
        print( "   So the within-run figure UNDERSTATES the run-to-run spread for every")
        print( "     candidate, which is RULES.md §4's claim measured over ten runs.")
    else:
        print( "   So on this host the two are comparable, and the within-run MAD is NOT")
        print( "    a gross underestimate of run-to-run spread -- which is a weaker")
        print( "    statement than this project has made elsewhere, and it is what these")
        print( "    ten runs support.")
print()

# ------------------------------------------------ the candidate vs the control
print("=== the OTHER comparison: each candidate against the control ===")
print("   This is the one the project actually publishes. `rel_time` is already")
print("     the ratio to the control in the same run, so the question is whether a")
print("     candidate's whole RANGE over the repeats stays on one side of 1.000.")
print()
print(f"  {'allocator':18s} {'beats':>7s} {'min':>7s} {'max':>7s}  verdict")
control_verdict = {}
for a in allocs:
    s = stats[a]
    beats = sum(1 for rel, _ in runs if rel[a] < 1.0)
    if s["hi"] < 1.0:
        v = "BEATS the control, whole range below it"
    elif s["lo"] > 1.0:
        v = "LOSES to the control, whole range above it"
    else:
        v = " crosses the control"
    control_verdict[a] = v
    print(f"  {a:18s} {beats:3d}/{n:<3d} {s['lo']:7.3f} {s['hi']:7.3f}  {v}")
decided = [a for a in allocs if not control_verdict[a].startswith("")]
print()
print(f"   {len(decided)} of {len(allocs)} candidates are DECIDED against the control by")
print(f"     {n} repeats here. The ordering AMONG them is not (see below).")
print( "      So the two questions have different answers on the SAME data, and a")
print( "        window that refuses an ordering while publishing a control claim is")
print( "        drawing exactly the right line.")
print()

# ------------------------------------------------------ pairwise decidability
print("=== which comparisons this host can decide ===")
print("  separated : the two ranges do not overlap in any of the runs -> decided")
print("  consistent: same direction every run, but the ranges touch  -> weak")
print("  unsettled : the direction itself changed between runs       -> not a result")
print()
print(f"  {'pair':40s} {'agrees':>8s} {'gap(med)':>9s}  verdict")
verdict = {}
for x in range(len(allocs)):
    for y in range(x + 1, len(allocs)):
        a, b = allocs[x], allocs[y]
        wins = sum(1 for rel, _ in runs if rel[a] < rel[b])
        faster, slower = (a, b) if stats[a]["med"] < stats[b]["med"] else (b, a)
        gap = (stats[slower]["med"] - stats[faster]["med"]) / stats[faster]["med"] * 100
        if stats[faster]["hi"] < stats[slower]["lo"]:
            v = "separated"
        elif wins in (0, n):
            v = "consistent"
        else:
            v = "unsettled"
        verdict[frozenset((a, b))] = v
        print(f"  {faster + ' < ' + slower:40s} {max(wins, n - wins):3d}/{n:<4d} {gap:8.1f}%  {v}")
print()
counts = {}
for v in verdict.values():
    counts[v] = counts.get(v, 0) + 1
tot = len(verdict)
print(f"  of {tot} pairs: {counts.get('separated', 0)} separated, "
      f"{counts.get('consistent', 0)} consistent, {counts.get('unsettled', 0)} unsettled")
print()

# --------------------------------------------- cross-reference with the window
print("=== cross-reference: the rolling window's rank changes ===")
try:
    win = json.load(open(window_path))
except Exception as e:
    print(f"   {window_path} unreadable ({e}); the cross-reference is skipped, and")
    print( "    that is a gap in this transcript rather than a negative result.")
    raise SystemExit(0)

wg = None
for g in win.get("groups", []):
    if g.get("group") == gname:
        wg = g
        break
if wg is None:
    print(f"   the window holds no group named {gname!r}; nothing to cross-reference.")
    raise SystemExit(0)

wvals = {r["allocator"]: r["rel_time"]["values"] for r in wg["rows"]
         if not r.get("is_baseline") and r.get("rel_time", {}).get("values")}
nmach = win.get("distinct_cpu_models")
print(f"  window: {wg['group']}, {len(next(iter(wvals.values())))} run(s), "
      f"{nmach} CPU model(s)")
print(f"  machines: {', '.join(win.get('cpu_models') or [])}")
print()
print("   For every pair that CHANGED DIRECTION between machines, does this host")
print("     decide that pair at all? If it does not, the change is not evidence")
print("     about the machine -- the comparison was never resolved.")
print()
print(f"  {'pair':40s} {'across machines':>16s}  {'on one host':>12s}  reading")
real, illusory, skipped, agreed, ragged = 0, 0, 0, 0, 0
for pair, v in sorted(verdict.items(), key=lambda kv: sorted(kv[0])):
    a, b = sorted(pair)
    if a not in wvals or b not in wvals:
        skipped += 1
        continue
    if len(wvals[a]) != len(wvals[b]):
        print(f"   {a} has {len(wvals[a])} window value(s) and {b} has "
              f"{len(wvals[b])}; not comparable, skipped.")
        ragged += 1
        continue
    dirs = {ai < bi for ai, bi in zip(wvals[a], wvals[b])}
    if len(dirs) == 1:
        agreed += 1
        continue  # the machines agree; not a rank change
    if v == "unsettled":
        reading = " NOT evidence about the machine"
        illusory += 1
    elif v == "consistent":
        reading = " weak: ranges touch here"
        illusory += 1
    else:
        reading = " REAL: this host decides it"
        real += 1
    print(f"  {a + ' vs ' + b:40s} {'CHANGED':>16s}  {v:>12s}  {reading}")
print()
print(f"  pairs that changed direction across machines and that this host")
print(f"   DOES decide: {real}     does NOT decide: {illusory}")
print(f"  pairs the machines AGREED on: {agreed}")
if skipped:
    print(f"  ({skipped} pair(s) not in the window and not counted)")
if ragged:
    print(f"  ({ragged} pair(s) with mismatched window lengths, not counted)")
print()
if real == 0 and illusory == 0:
    print("   No pair changed direction across the window's machines, so there is")
    print("    nothing here to classify. That is a statement about THIS window's")
    print("    contents, not a finding about transfer.")
elif real == 0 and illusory > 0:
    print("   EVERY CROSS-MACHINE RANK CHANGE IN THIS GROUP IS A PAIR THIS SINGLE")
    print("     HOST ALSO FAILS TO DECIDE. On this evidence the rank changes are not")
    print("     a measurement of the machine at all: they are what unresolved")
    print("     comparisons look like when each is sampled once per machine.")
elif real > 0:
    print("   At least one cross-machine rank change is a pair this host resolves")
    print("     cleanly over its own repeats. THAT pair is where 'the machine")
    print("     changed the answer' is supported, and it is where a property-hunting")
    print("     experiment should be aimed.")
print()
print("=== cross-reference: the control comparison across machines ===")
print(f"   READ THE ASYMMETRY. {n} repeats here against ONE sample per machine there.")
print( "     A window value outside this host's range is CONSISTENT WITH a machine")
print( "     effect and does not establish one: the other machine's own spread is")
print( "     unmeasured, and this experiment is the reason to doubt a single sample.")
print()
print(f"  {'allocator':18s} {'this host (' + str(n) + ' runs)':>21s}  {'clearly outside':>15s}  widest margin")
outside_any = 0
for a in allocs:
    if a not in wvals:
        continue
    st = stats[a]
    thresh = st["within"] / 100.0 if st["within"] == st["within"] else 0.0
    margins = []
    for v in wvals[a]:
        if v > st["hi"]:
            margins.append((v - st["hi"]) / st["hi"])
        elif v < st["lo"]:
            margins.append((st["lo"] - v) / st["lo"])
        else:
            margins.append(0.0)
    out = [m for m in margins if m > thresh]
    outside_any += 1 if out else 0
    print(f"  {a:18s} {st['lo']:8.3f}-{st['hi']:<11.3f}  {len(out):5d} of {len(wvals[a]):<6d}  "
          f"{max(margins) * 100:6.2f}%  (needs > {thresh * 100:.1f}%)")
print()
print(f"   {outside_any} candidate(s) have a window value this host never produced in")
print(f"     {n} repeats, by more than that cell's own spread. Those are where a")
print(f"     machine effect would live,")
print( "     and settling it needs REPEATS ON THE SECOND MACHINE -- T-025 option (3),")
print( "     which needs runners this project does not have.")
print()
PY
    analysis=$?
    [ "$analysis" -eq 0 ] || fail "the analysis exited $analysis"

    echo
    echo "=== what this probe cannot tell you ==="
    echo "- WHICH property of the machine anything depends on. It measures how"
    echo "  much of the ordering is decidable at all, which is the question that"
    echo "  has to be answered before 'which property' is a well-posed one."
    echo "- anything about a second host. Every number above is this machine."
    echo "- whether a pair this host leaves unsettled is unsettled everywhere. A"
    echo "  quieter machine may separate it; that needs the machine."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
