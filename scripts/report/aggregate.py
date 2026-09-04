#!/usr/bin/env python3
"""Maintain a rolling window of the last N runs of one suite, and aggregate them.

 **Why this is not a mean.** `docs/AGENTS.md` §11.1 established that this
project's ranking is a property of the MACHINE: `core` measured on three CPUs
gave three orderings, and the run that inverted the result reported the TIGHTEST
within-run noise of the three. Averaging those into one table would erase the
single most important thing the project has found, and would do it while looking
more authoritative than any individual run.

 **So this aggregate reports disagreement as a first-class result.** For every
allocator it publishes the spread across runs, whether it stayed on the same side
of the control, and whether its rank moved. A group whose ranks moved gets **no
ordering**, and says so.

 **What a repeated sample genuinely buys.** GitHub's hosted runner fleet is
heterogeneous, so successive runs land on different CPUs. That does not
average the machine away -- it SAMPLES it. After a few weeks you can say "this held
on every machine we landed on", which is a claim about transfer rather than about
one Xeon. That claim is the deliverable; the mean is not.

Usage:

    aggregate.py --window DIR                 # regenerate from what is there
    aggregate.py --window DIR --add DATASET   # add a run, prune, regenerate
    aggregate.py --window DIR --check         # assert the window is coherent

`--keep N` sets the window size (default 6).

It reads `rankings.json` and `run.json`, which `alloc-bench` derived from the raw
samples.  It re-derives nothing and never invents a value: a metric absent from
a dataset is an em dash, never a zero.

Exit: 0 it ran, 1 it ran and something is wrong, 2 it could not run.
 2 is never a pass.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import statistics
import sys

DEFAULT_KEEP = 6
KEEP_FILES = ("rankings.json", "run.json")

def die(msg: str) -> int:
    print(f"aggregate: {msg}", file=sys.stderr)
    return 2

def load(path: pathlib.Path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise ValueError(f"{path}: {e}") from e

def fmt(v, digits=3):
    if v is None or not isinstance(v, (int, float)):
        return "–"
    return f"{v:.{digits}f}"

def pct(v, digits=1):
    if v is None or not isinstance(v, (int, float)):
        return "–"
    return f"{v * 100:.{digits}f}%"

def run_key(run_doc) -> str:
    """A stable directory name for one run: when it started, and where."""
    started = (run_doc.get("started_at") or "unknown").replace(":", "").replace("-", "")
    started = started.replace("T", "-").rstrip("Z")
    ci = (run_doc.get("ci") or {}).get("GITHUB_RUN_ID")
    return f"{started}-{'ci' + ci if ci else 'local'}"

def conditions(run_doc) -> dict:
    host = run_doc.get("host") or {}
    ci = run_doc.get("ci") or {}
    return {
        "run_id": run_doc.get("run_id"),
        "started_at": run_doc.get("started_at"),
        "cpu_model": host.get("cpu_model"),
        "cpu_count": host.get("cpu_count"),
        "kernel": host.get("kernel"),
        "emulated": host.get("emulated"),
        "runtime": host.get("container_runtime"),
        "ci_run_id": ci.get("GITHUB_RUN_ID"),
        "git_commit": run_doc.get("git_commit"),
        "corpus_seed": run_doc.get("corpus_seed"),
        "suites": run_doc.get("suites"),
    }

# --------------------------------------------------------------------------
# Adding a run to the window

def add_run(window: pathlib.Path, dataset: pathlib.Path, keep: int) -> int:
    for f in KEEP_FILES:
        if not (dataset / f).is_file():
            return die(f"{dataset} has no {f}; refusing to add an unidentifiable run")
    try:
        run_doc = load(dataset / "run.json")
    except ValueError as e:
        return die(str(e))

    if (run_doc.get("host") or {}).get("emulated"):
        print("aggregate: refusing to add an EMULATED run to the window", file=sys.stderr)
        print("aggregate: an allocator comparison under emulation measures the emulator too",
              file=sys.stderr)
        return 1

    dest = window / "runs" / run_key(run_doc)
    if dest.exists():
        print(f"aggregate: {dest.name} is already in the window; replacing it")
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for f in KEEP_FILES:
        shutil.copy2(dataset / f, dest / f)
    print(f"aggregate: added {dest.name}")

    prune(window, keep)
    return 0

def prune(window: pathlib.Path, keep: int) -> None:
    runs = collect(window)
    if len(runs) <= keep:
        return
    # Newest first by start instant; drop the tail.
    for path, _, _ in runs[keep:]:
        print(f"aggregate: pruning {path.name} (window keeps {keep})")
        shutil.rmtree(path)

def collect(window: pathlib.Path):
    """Every run in the window, newest first. Returns (dir, run_doc, rank_doc)."""
    out = []
    runs_dir = window / "runs"
    if not runs_dir.is_dir():
        return out
    for d in sorted(runs_dir.iterdir()):
        if not d.is_dir():
            continue
        try:
            run_doc = load(d / "run.json")
            rank_doc = load(d / "rankings.json")
        except ValueError as e:
            print(f"aggregate: skipping {d.name}: {e}", file=sys.stderr)
            continue
        out.append((d, run_doc, rank_doc))
    out.sort(key=lambda t: t[1].get("started_at") or "", reverse=True)
    return out

# --------------------------------------------------------------------------
# The aggregate itself

def build(window: pathlib.Path, keep: int) -> dict | None:
    runs = collect(window)
    if not runs:
        return None

    per_group: dict[str, dict] = {}
    workloads = set()
    for idx, (_, _, rank_doc) in enumerate(runs):
        workloads.add(rank_doc.get("primary_workload"))
        for g in rank_doc.get("groups", []):
            name = g.get("group", "?")
            grp = per_group.setdefault(name, {})
            rows = [r for r in g.get("rows", []) if r.get("rel_time") is not None]
            # Rank within this run, fastest first. Position is what has to be
            # stable for an ordering to be publishable.
            order = sorted(rows, key=lambda r: r["rel_time"])
            for pos, r in enumerate(order, start=1):
                key = (
                    r.get("allocator"),
                    r.get("integration"),
                    r.get("variant") or "default",
                )
                cell = grp.setdefault(
                    key,
                    {
                        "allocator": key[0],
                        "integration": key[1],
                        "variant": key[2],
                        "label": key[0] if key[2] == "default" else f"{key[0]} ({key[2]})",
                        "is_baseline": bool(r.get("is_baseline")),
                        "rel_time": [],
                        "rel_rss": [],
                        "rel_mad": [],
                        "positions": [],
                        "run_index": [],
                    },
                )
                cell["rel_time"].append(r["rel_time"])
                if isinstance(r.get("rel_rss"), (int, float)):
                    cell["rel_rss"].append(r["rel_rss"])
                m = r.get("rel_mad")
                cell["rel_mad"].append(m if isinstance(m, (int, float)) else None)
                cell["positions"].append(pos)
                cell["run_index"].append(idx)

    groups_out = []
    for name in sorted(per_group):
        rows_out = []
        for cell in per_group[name].values():
            vals = cell["rel_time"]
            med = statistics.median(vals)
            lo, hi = min(vals), max(vals)
            spread = (hi - lo) / med if med else None
            mads = [m for m in cell["rel_mad"] if m is not None]
            mads_by_run = cell["rel_mad"]

            def _clears_its_own_noise(v, m):
                return m is not None and (1.0 - v) > m

            beats = (
                (not cell["is_baseline"])
                and hi < 1.0
                and all(_clears_its_own_noise(v, m) for v, m in zip(vals, mads_by_run))
            )
            row = {
                "allocator": cell["allocator"],
                "integration": cell["integration"],
                "variant": cell["variant"],
                "label": cell["label"],
                "is_baseline": cell["is_baseline"],
                "n_runs": len(vals),
                "rel_time": {
                    "median": med,
                    "min": lo,
                    "max": hi,
                    "values": vals,
                },
                "rel_rss": {
                    "median": statistics.median(cell["rel_rss"]) if cell["rel_rss"] else None,
                    "min": min(cell["rel_rss"]) if cell["rel_rss"] else None,
                    "max": max(cell["rel_rss"]) if cell["rel_rss"] else None,
                },
                "between_run_spread": spread,
                "within_run_mad": {
                    "min": min(mads) if mads else None,
                    "max": max(mads) if mads else None,
                },
                "positions": cell["positions"],
                "rank_stable": len(set(cell["positions"])) == 1,
                "beats_control_every_run": beats,
                "beats_control_but_inside_its_own_noise": (
                    (not cell["is_baseline"])
                    and hi < 1.0
                    and not beats
                ),
                "loses_to_control_every_run": (not cell["is_baseline"]) and lo > 1.0,
                "crosses_control": (not cell["is_baseline"]) and lo < 1.0 < hi,
            }
            rows_out.append(row)
        rows_out.sort(key=lambda r: r["rel_time"]["median"])

        candidates = [r for r in rows_out if not r["is_baseline"]]
        movers = [r["label"] for r in candidates if not r["rank_stable"]]
        crossers = [r["label"] for r in candidates if r["crosses_control"]]
        invariant = [r["label"] for r in candidates if r["beats_control_every_run"]]
        groups_out.append(
            {
                "group": name,
                "rows": rows_out,
                "ordering_transfers": len(rows_out) > 0 and not movers,
                "rank_movers": movers,
                "control_crossers": crossers,
                "beat_control_every_run": invariant,
            }
        )

    conds = [conditions(rd) for _, rd, _ in runs]
    cpus = sorted({c["cpu_model"] for c in conds if c["cpu_model"]})
    return {
        "schema_version": 1,
        "generated_from": "rankings.json of each run in the window; nothing re-derived",
        "window": {"keep": keep, "n_runs": len(runs), "runs": conds},
        "distinct_cpu_models": len(cpus),
        "cpu_models": cpus,
        "primary_workload": sorted(w for w in workloads if w)[0] if workloads else None,
        "groups": groups_out,
    }

# --------------------------------------------------------------------------
# Markdown

def render(agg: dict) -> str:
    L: list[str] = []
    w = agg["window"]
    n = w["n_runs"]
    ncpu = agg["distinct_cpu_models"]
    L.append("# Rolling aggregate")
    L.append("")
    L.append(
        f"The last **{n}** run(s) of this suite, on **{ncpu}** distinct CPU model(s). "
        f"Primary workload `{agg.get('primary_workload')}`."
    )
    L.append("")
    L.append(
        " **Generated. Do not edit.** `scripts/report/aggregate.py` rewrites this "
        "file from the runs under `runs/`, and CI regenerates it after every "
        "weekly benchmark."
    )
    L.append("")

    L.append("## How to read every table here")
    L.append("")
    L.append(
        "**Every measured column is one where lower is better**, marked `↓`: a "
        "ratio under `1.000` beat the control, and one over it lost.  The two "
        "exceptions are marked where they appear - `rank` (position, so `1` is "
        "best) and the run counts in the prose."
    )
    L.append("")
    L.append("| column | means | good direction |")
    L.append("| --- | --- | --- |")
    L.append(
        "| `rel median ↓` | the middle of this cell's per-run ratios to its own "
        "control | **lower**; `0.800` is 20% faster than the image's own allocator |"
    )
    L.append(
        "| `rel min ↓` / `rel max ↓` | the best and worst that ratio has ever been "
        "in this window | **lower**, and the GAP between them is the finding |"
    )
    L.append(
        "| `between-run spread ↓` | `(max − min) / median` across machines | "
        "**lower**; a large value means the result does not transfer |"
    )
    L.append(
        "| `within-run MAD ↓` | the spread of one run's own samples | **lower**; "
        " it is a floor on the uncertainty, never a bound |"
    )
    L.append(
        "| `rank` | position within each run, newest first | **lower**, `1` = "
        "fastest.  A `` marks a candidate whose rank MOVED |"
    )
    L.append(
        "| `RSS rel ↓` | peak resident set relative to the control | **lower**; "
        "`3.500` means three and a half times the control's peak memory |"
    )
    L.append("")

    L.append("## What this aggregate does not establish")
    L.append("")
    if n < 2:
        L.append(
            " **One run.** Nothing here is an aggregate yet: there is no second "
            "measurement to disagree with it. Every figure below is one machine "
            "on one day."
        )
        L.append("")
    if ncpu < 2 and n >= 2:
        L.append(
            f" **All {n} runs landed on the same CPU model.** Agreement between "
            "them is therefore evidence about repeatability on one machine, and "
            "says nothing about whether a result transfers to another."
        )
        L.append("")

    any_movers = False
    for g in agg["groups"]:
        if g["rank_movers"]:
            any_movers = True
            L.append(
                f" **The ordering does not transfer** in `{g['group']}`. "
                f"{len(g['rank_movers'])} allocator(s) changed rank between runs: "
                + ", ".join(f"**{m}**" for m in sorted(g["rank_movers"]))
                + ". **No ordering is published for this group.**"
            )
            L.append("")
        if g["control_crossers"]:
            L.append(
                " **Changed which side of the control they sit on:** "
                + ", ".join(f"**{m}**" for m in sorted(g["control_crossers"]))
                + ". A recommendation naming one of these is a statement about a "
                "machine, not about the allocator."
            )
            L.append("")
    if not any_movers and n >= 2:
        L.append(
            " Every allocator held its rank across every run in this window. "
            " That is a statement about the machines sampled so far, not a "
            "guarantee - see the CPU models listed below."
        )
        L.append("")

    L.append("## What survives every run in the window")
    L.append("")
    for g in agg["groups"]:
        inv = g["beat_control_every_run"]
        if inv:
            L.append(
                f"- `{g['group']}`: **"
                + ", ".join(sorted(inv))
                + f"** beat the control in all {n} run(s), by more than that "
                "run's own MAD each time."
            )
        else:
            L.append(f"- `{g['group']}`:  **no allocator beat the control in every run.**")
        noisy = sorted(
            r["label"]
            for r in g["rows"]
            if r.get("beats_control_but_inside_its_own_noise")
        )
        if noisy:
            L.append(
                "  -  **below the control every run but never by more than that "
                "run's own MAD:** "
                + ", ".join(f"**{m}**" for m in noisy)
                + ". Not counted above: a lead smaller than the run's own spread "
                "is no result."
            )
    L.append("")

    for g in agg["groups"]:
        L.append(f"## {g['group']}")
        L.append("")
        L.append(
            "| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | "
            "within-run MAD ↓ | rank | RSS rel ↓ |"
        )
        L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        rss_movers = []
        for r in g["rows"]:
            rt = r["rel_time"]
            mad = r["within_run_mad"]
            madtxt = (
                "–"
                if mad["min"] is None
                else (pct(mad["min"]) if mad["min"] == mad["max"] else f"{pct(mad['min'])}–{pct(mad['max'])}")
            )
            ranks = "/".join(str(p) for p in r["positions"])
            flag = "" if (r["rank_stable"] or r["is_baseline"]) else " "
            name = r["label"] + (" *(control)*" if r["is_baseline"] else "")
            rss = r["rel_rss"]
            rsstxt = fmt(rss["median"])
            if (
                rss["median"]
                and rss["max"] is not None
                and (rss["max"] - rss["min"]) / rss["median"] > 0.25
            ):
                # Peak RSS transfers no better than time does, and a median alone
                # would hide it.
                rsstxt = f"{fmt(rss['median'])}  ({fmt(rss['min'],2)}–{fmt(rss['max'],2)})"
                if not r["is_baseline"]:
                    rss_movers.append(r["label"])
            L.append(
                f"| {name} | `{r['integration']}` | **{fmt(rt['median'])}** | {fmt(rt['min'])} | "
                f"{fmt(rt['max'])} | {pct(r['between_run_spread'])} | {madtxt} | {ranks}{flag} | "
                f"{rsstxt} |"
            )
        L.append("")
        L.append(
            " **`rank` is this cell's position in each run, newest first**, "
            "fastest = 1. A candidate marked  moved, and a moved rank is why no "
            "ordering is claimed."
        )
        L.append("")
        base = next((r for r in g["rows"] if r["is_baseline"]), None)
        if base is not None and n >= 2:
            beat = [p - 1 for p in base["positions"]]
            L.append(
                " **The control's own position is how many allocators beat it "
                f"that run: {', '.join(str(b) for b in beat)}.** "
                + (
                    "That number moving is the same finding as the rank changes above, "
                    "stated as a count."
                    if len(set(beat)) > 1
                    else "It did not move across this window."
                )
            )
            L.append("")
        if rss_movers:
            L.append(
                " **Peak RSS does not transfer either**, for "
                + ", ".join(f"**{m}**" for m in sorted(set(rss_movers)))
                + ". A memory-capped deployment cannot be sized from the median "
                "column alone; the range is the honest figure."
            )
            L.append("")
        worst = max(
            (r for r in g["rows"] if r["between_run_spread"] is not None),
            key=lambda r: r["between_run_spread"],
            default=None,
        )
        if worst is not None and worst["within_run_mad"]["max"] is not None and n >= 2:
            bs, wm = worst["between_run_spread"], worst["within_run_mad"]["max"]
            L.append(
                f" **The within-run MAD is a floor on the uncertainty, not a bound.** "
                f"The widest cell here is **{worst['label']}**: it moved "
                f"**{pct(bs)}** between runs while its own samples never spread more "
                f"than **{pct(wm)}** within one."
            )
            L.append("")

    L.append("## The runs in this window")
    L.append("")
    L.append("| started | CPU | cores | kernel | commit | CI run |")
    L.append("| --- | --- | --- | --- | --- | --- |")
    for c in w["runs"]:
        ci = c["ci_run_id"]
        ci_txt = (
            f"[`{ci}`](https://github.com/Azathothas/alloc-bench/actions/runs/{ci})"
            if ci
            else "local"
        )
        commit = (c["git_commit"] or "")[:7] or "–"
        L.append(
            f"| {c['started_at'] or '–'} | {c['cpu_model'] or '–'} | {c['cpu_count'] or '–'} "
            f"| `{c['kernel'] or '–'}` | `{commit}` | {ci_txt} |"
        )
    L.append("")
    L.append(
        " **A measurement carries its conditions.** Never quote a figure above "
        "without naming which of these machines it came from - and where the "
        "window spans several, the figure is a range, not a number."
    )
    L.append("")
    return "\n".join(L)

# --------------------------------------------------------------------------

def check(window: pathlib.Path, agg: dict | None) -> list[str]:
    """Assert the window is coherent. Returns problems."""
    problems = []
    if agg is None:
        return [f"{window}: no runs in the window"]
    seen = set()
    for c in agg["window"]["runs"]:
        if not c["started_at"]:
            problems.append(f"{window}: a run carries no start instant")
        if not c["cpu_model"]:
            problems.append(
                f"{window}: run {c['run_id']} carries no cpu_model; "
                "a run whose conditions are unrecorded cannot join an aggregate"
            )
        suites = tuple(c["suites"] or ())
        seen.add(suites)
    if len(seen) > 1:
        problems.append(f"{window}: mixes different suites: {sorted(seen)}")
    for g in agg["groups"]:
        for r in g["rows"]:
            if r["n_runs"] != agg["window"]["n_runs"]:
                problems.append(
                    f"{window}: {g['group']} / {r['label']} appears in "
                    f"{r['n_runs']} of {agg['window']['n_runs']} runs. "
                    "Either the suite's candidate set changed -- in which case "
                    "the older runs are not rank-comparable and belong out of "
                    "this window, with a README saying so -- or a cell failed "
                    "and was dropped, which is what this check is for."
                )
    return problems

def _fixture(tmp: pathlib.Path, name, cpu, started, rows, suites=("core",), emulated=False, mad=0.01):
    d = tmp / name
    d.mkdir(parents=True)
    (d / "run.json").write_text(
        json.dumps(
            {
                "run_id": name,
                "started_at": started,
                "suites": list(suites),
                "git_commit": "0" * 40,
                "corpus_seed": 1,
                "host": {
                    "cpu_model": cpu,
                    "cpu_count": 4,
                    "kernel": "test",
                    "arch": "x86_64",
                    "container_runtime": "docker",
                    "emulated": emulated,
                },
            }
        )
    )
    (d / "rankings.json").write_text(
        json.dumps(
            {
                "primary_workload": "literal",
                "groups": [
                    {
                        "group": "g",
                        "rows": [
                            {
                                "allocator": r[0],
                                "integration": "rust-global" if r[0] != "system" else "baseline",
                                "arch": "x86_64",
                                "is_baseline": r[0] == "system",
                                "rel_time": r[1],
                                "rel_rss": 1.0,
                                "rel_mad": mad,
                                "variant": r[2] if len(r) > 2 else "default",
                            }
                            for r in rows
                        ],
                    }
                ],
            }
        )
    )
    return d

def selftest() -> int:
    import contextlib
    import io
    import tempfile

    checks: list[tuple[str, bool, str]] = []

    def ok(name, cond, detail=""):
        checks.append((name, bool(cond), detail))

    # The fixtures' own progress and refusal messages are the thing under test,
    # not output anybody needs to read. Only the check results are printed.
    sink = io.StringIO()
    with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink), \
            tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        w = tmp / "win"

        a = _fixture(tmp, "a", "CPU-1", "2026-01-01T00:00:00Z", [("system", 1.0), ("x", 0.5)])
        b = _fixture(tmp, "b", "CPU-2", "2026-01-02T00:00:00Z", [("system", 1.0), ("x", 1.5)])
        c = _fixture(tmp, "c", "CPU-3", "2026-01-03T00:00:00Z", [("system", 1.0), ("x", 0.6)])
        d = _fixture(tmp, "d", "CPU-4", "2026-01-04T00:00:00Z", [("system", 1.0), ("x", 0.7)])

        ok("add-first-run", main(["--window", str(w), "--add", str(a)]) == 0)
        ok("add-second-run", main(["--window", str(w), "--add", str(b)]) == 0)
        agg = json.loads((w / "aggregate.json").read_text())
        row = next(r for r in agg["groups"][0]["rows"] if r["allocator"] == "x")
        ok("crossing-the-control-is-detected", row["crosses_control"] is True)
        ok("crossing-is-not-called-a-win", row["beats_control_every_run"] is False)
        ok("moved-rank-is-detected", row["rank_stable"] is False)
        ok("no-ordering-published", agg["groups"][0]["ordering_transfers"] is False)

        ok("add-third-run", main(["--window", str(w), "--add", str(c)]) == 0)
        ok("add-fourth-prunes", main(["--window", str(w), "--add", str(d), "--keep", "3"]) == 0)
        kept = sorted(p.name for p in (w / "runs").iterdir())
        ok("window-holds-exactly-keep", len(kept) == 3, f"kept={kept}")
        ok("oldest-was-pruned", not any(k.startswith("20260101") for k in kept), f"kept={kept}")

        # A window whose runs all agree SHOULD publish an ordering.
        w2 = tmp / "win2"
        for i, (nm, cpu) in enumerate([("s1", "CPU-1"), ("s2", "CPU-2")]):
            f = _fixture(
                tmp, nm, cpu, f"2026-02-0{i + 1}T00:00:00Z", [("system", 1.0), ("x", 0.5)]
            )
            main(["--window", str(w2), "--add", str(f)])
        agg2 = json.loads((w2 / "aggregate.json").read_text())
        ok("stable-window-publishes-an-ordering", agg2["groups"][0]["ordering_transfers"] is True)

        w7 = tmp / "win7"
        noisy = _fixture(
            tmp, "noisy", "CPU-1", "2026-06-01T00:00:00Z",
            [("system", 1.0), ("x", 0.988)], mad=0.025,
        )
        main(["--window", str(w7), "--add", str(noisy)])
        agg7 = json.loads((w7 / "aggregate.json").read_text())
        rnoisy = next(r for r in agg7["groups"][0]["rows"] if r["allocator"] == "x")
        ok("a-lead-inside-the-runs-own-MAD-is-not-a-win",
           rnoisy["beats_control_every_run"] is False)
        ok("and-it-is-NAMED-rather-than-dropped",
           rnoisy["beats_control_but_inside_its_own_noise"] is True)
        ok("the-aggregate-says-so-in-prose",
           "never by more than that run's own MAD" in (w7 / "aggregate.md").read_text())
        ok("a-lead-outside-the-MAD-is-still-a-win",
           next(r for r in agg2["groups"][0]["rows"] if r["allocator"] == "x")[
               "beats_control_every_run"] is True)
        w8 = tmp / "win8"
        nomad = _fixture(
            tmp, "nomad", "CPU-1", "2026-07-01T00:00:00Z",
            [("system", 1.0), ("x", 0.5)], mad=None,
        )
        main(["--window", str(w8), "--add", str(nomad)])
        agg8 = json.loads((w8 / "aggregate.json").read_text())
        ok("a-run-with-no-MAD-cannot-establish-a-win",
           next(r for r in agg8["groups"][0]["rows"] if r["allocator"] == "x")[
               "beats_control_every_run"] is False)
        ok(
            "stable-window-names-the-invariant",
            agg2["groups"][0]["beat_control_every_run"] == ["x"],
        )

        em = _fixture(
            tmp, "em", "CPU-9", "2026-03-01T00:00:00Z",
            [("system", 1.0), ("x", 0.5)], emulated=True,
        )
        ok("refuses-an-emulated-run", main(["--window", str(tmp / "w3"), "--add", str(em)]) == 1)

        broken = tmp / "broken"
        broken.mkdir()
        (broken / "run.json").write_text("{}")
        ok(
            "refuses-a-dataset-with-no-rankings",
            main(["--window", str(tmp / "w4"), "--add", str(broken)]) == 2,
        )

        nocpu = _fixture(tmp, "nocpu", None, "2026-04-01T00:00:00Z", [("system", 1.0), ("x", 0.5)])
        w5 = tmp / "w5"
        main(["--window", str(w5), "--add", str(nocpu)])
        ok("check-refuses-a-run-with-no-cpu", main(["--window", str(w5), "--check"]) == 1)

        mixed = _fixture(
            tmp, "mixed", "CPU-1", "2026-05-01T00:00:00Z",
            [("system", 1.0), ("x", 0.5)], suites=("mechanisms",),
        )
        w6 = tmp / "w6"
        main(["--window", str(w6), "--add", str(a)])
        main(["--window", str(w6), "--add", str(mixed)])
        ok("check-refuses-a-window-mixing-suites", main(["--window", str(w6), "--check"]) == 1)

        v1 = _fixture(tmp, "v1", "CPU-1", "2026-06-01T00:00:00Z",
                      [("system", 1.0), ("h", 1.08, "default"), ("h", 0.73, "light")],
                      suites=("hardening-variants",))
        v2 = _fixture(tmp, "v2", "CPU-1", "2026-06-02T00:00:00Z",
                      [("system", 1.0), ("h", 1.08, "default"), ("h", 0.73, "light")],
                      suites=("hardening-variants",))
        wv = tmp / "wv"
        main(["--window", str(wv), "--add", str(v1)])
        main(["--window", str(wv), "--add", str(v2)])
        aggv = json.loads((wv / "aggregate.json").read_text())
        vrows = aggv["groups"][0]["rows"]
        ok("two-variants-of-one-allocator-are-two-rows", len(vrows) == 3,
           f"rows={[r['label'] for r in vrows]}")
        ok("the-default-variant-keeps-its-bare-name",
           any(r["label"] == "h" for r in vrows))
        ok("a-non-default-variant-is-named-in-the-label",
           any(r["label"] == "h (light)" for r in vrows))
        ok("each-variant-has-one-position-per-run",
           all(len(r["positions"]) == 2 for r in vrows),
           f"positions={[r['positions'] for r in vrows]}")
        ok("identical-runs-produce-no-rank-mover",
           aggv["groups"][0]["rank_movers"] == [],
           f"movers={aggv['groups'][0]['rank_movers']}")
        ok("identical-runs-produce-no-control-crosser",
           aggv["groups"][0]["control_crossers"] == [])
        ok("the-faster-variant-is-recorded-as-beating-the-control",
           aggv["groups"][0]["beat_control_every_run"] == ["h (light)"],
           f"beat={aggv['groups'][0]['beat_control_every_run']}")
        ok("a-variant-window-is-coherent", main(["--window", str(wv), "--check"]) == 0)

        ok("refuses-a-missing-window", main(["--window", str(tmp / "nope")]) == 2)
        ok("refuses-keep-zero", main(["--window", str(w), "--keep", "0"]) == 2)

    bad = [c for c in checks if not c[1]]
    for name, good, detail in checks:
        print(f"  {'ok   ' if good else 'FAIL '} {name}{(' ' + detail) if detail else ''}")
    print(f"aggregate --selftest: {len(checks)} check(s), {len(bad)} failure(s).")
    return 1 if bad else 0

def main(argv=None) -> int:
    if argv is None and len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        return selftest()
    if argv is not None and argv and argv[0] == "--selftest":
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true", help="plant each defect and assert refusal")
    ap.add_argument("--window", required=True, help="the rolling window directory")
    ap.add_argument("--add", metavar="DATASET", help="a run directory to add first")
    ap.add_argument("--keep", type=int, default=DEFAULT_KEEP, help="window size")
    ap.add_argument("--check", action="store_true", help="assert the window is coherent")
    args = ap.parse_args(argv)

    if args.keep < 1:
        return die("--keep must be at least 1")
    window = pathlib.Path(args.window)

    if args.add:
        dataset = pathlib.Path(args.add)
        if not dataset.is_dir():
            return die(f"{dataset} is not a directory")
        window.mkdir(parents=True, exist_ok=True)
        rc = add_run(window, dataset, args.keep)
        if rc:
            return rc
    elif not window.is_dir():
        return die(f"{window} is not a directory")

    prune(window, args.keep)
    agg = build(window, args.keep)
    if agg is None:
        return die(f"{window} has no runs to aggregate")

    problems = check(window, agg)
    if args.check:
        for p in problems:
            print(f"aggregate: {p}", file=sys.stderr)
        if problems:
            print(f"\naggregate: {len(problems)} problem(s).", file=sys.stderr)
            return 1
        print(f"aggregate: {window} is coherent: {agg['window']['n_runs']} run(s).")
        return 0

    for p in problems:
        print(f"aggregate:  {p}", file=sys.stderr)

    (window / "aggregate.json").write_text(
        json.dumps(agg, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (window / "aggregate.md").write_text(render(agg), encoding="utf-8")
    movers = sum(len(g["rank_movers"]) for g in agg["groups"])
    print(
        f"aggregate: {window}: {agg['window']['n_runs']} run(s), "
        f"{agg['distinct_cpu_models']} CPU model(s), {movers} rank change(s)."
    )
    return 0

if __name__ == "__main__":
    sys.exit(main())
