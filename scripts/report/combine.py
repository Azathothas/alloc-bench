#!/usr/bin/env python3
"""Combine the per-architecture datasets into one summary.

Reads the artefact directory a CI run downloaded and writes Markdown to stdout,
which `bench.yml` appends to the job summary.

 Why this exists: an ordering that holds on x86_64 and reverses on aarch64 is
the most interesting thing a two-architecture run can find, and nobody sees it
if the two results live in separate artefacts.

 It reads `rankings.json`, which `alloc-bench report` derived from the raw
samples. It does not re-derive anything and it never invents a value: a metric
absent from the dataset is printed as an em dash.

Exit: 0 it ran, 1 it ran and found no dataset, 2 it could not run.
"""

import json
import pathlib
import sys

def find_rankings(root: pathlib.Path):
    """Every rankings.json under root, keyed by the architecture it describes."""
    out = {}
    for p in sorted(root.rglob("rankings.json")):
        try:
            doc = json.loads(p.read_text())
        except (OSError, json.JSONDecodeError) as e:
            print(f"<!-- skipped {p}: {e} -->")
            continue
        # The architecture is a property of the cells, not of the path: an
        # artefact directory can be renamed, a cell id cannot.
        arches = {
            row.get("arch")
            for g in doc.get("groups", [])
            for row in g.get("rows", [])
            if row.get("arch")
        }
        key = "+".join(sorted(arches)) if arches else p.parent.name
        out.setdefault(key, []).append((p, doc))
    return out

def label(row) -> str:
    """The allocator's name, with its variant when that is not the default.

     The same rule the cell ids and the rolling aggregate follow, ruled
    2026-09-02: a name gains a variant segment only when the variant is not the
    default, so nothing that has ever been published reads differently.
    """
    a = row.get("allocator", "?")
    v = row.get("variant") or "default"
    return a if v == "default" else f"{a} ({v})"

def fmt(v, digits=3):
    if v is None or not isinstance(v, (int, float)):
        return "–"
    return f"{v:.{digits}f}"

def rel_cell(rel, mad, is_baseline, better, worse):
    """A ratio as a reader acts on it: exact, then what it means.

     Identical rule and wording to `report.rs::rel_cell`, deliberately. The
    job summary and the report are read by the same person minutes apart, and a
    ratio that is annotated in one and bare in the other invites the reader to
    conclude the two are different quantities.

     Where the distance from the control is inside the cell's own MAD this
    says `≈ control` rather than a percentage. `docs/AGENTS.md` §9: a lead
    smaller than the run's own spread is not a result.
    """
    if rel is None or not isinstance(rel, (int, float)):
        return "–"
    if is_baseline:
        return f"{rel:.3f}× *(control)*"
    if mad is not None and isinstance(mad, (int, float)) and mad > 0 and abs(rel - 1.0) < mad:
        return f"{rel:.3f}×  ≈ control"
    d = (rel - 1.0) * 100.0
    if abs(d) < 0.05:
        return f"{rel:.3f}× (same as control)"
    return f"{rel:.3f}× ({abs(d):.1f}% {better if d < 0 else worse})"

def main(argv):
    if len(argv) < 2:
        print("usage: combine.py <artifact-dir>", file=sys.stderr)
        return 2
    root = pathlib.Path(argv[1])
    if not root.is_dir():
        print(f"combine: {root} is not a directory", file=sys.stderr)
        return 2

    found = find_rankings(root)
    if not found:
        print("# Combined summary\n")
        print("No `rankings.json` was found in the downloaded artefacts.")
        print("The per-architecture jobs may have failed before producing a report;")
        print("their own artefacts still carry the logs.")
        return 1

    print("# Combined summary\n")
    print("Both architectures, from the datasets each job produced.  Rows are")
    print("only comparable **down** a column: an absolute time on one machine")
    print("says nothing about another. The `rel` column is the transferable part.\n")
    print("**How to read it.** Every measured column below is one where **lower is")
    print("better**, marked `↓`: `0.800×` beat the image's own allocator by 20%,")
    print("`1.200×` lost to it by 20%. A cell reading ` ≈ control` is one whose")
    print("distance from the control is smaller than that cell's own MAD - this run")
    print("does not establish that it is faster or slower, and saying it did is the")
    print("claim `docs/AGENTS.md` §9 forbids.\n")

    # Per architecture, the primary group's table.
    per_arch_rows = {}
    for arch, docs in sorted(found.items()):
        print(f"## {arch}\n")
        for path, doc in docs:
            wl = doc.get("primary_workload", "?")
            for g in doc.get("groups", []):
                rows = g.get("rows", [])
                if len(rows) < 2:
                    continue
                print(f"### {g.get('group', '?')}  (workload `{wl}`)\n")
                print(
                    "| allocator | mechanism | time (s) ↓ | vs control ↓ | MAD ↓ "
                    "| peak RSS vs control ↓ |"
                )
                print("| --- | --- | --- | --- | --- | --- |")
                for r in rows:
                    mad = r.get("rel_mad")
                    base = bool(r.get("is_baseline"))
                    print(
                        f"| {label(r)}"
                        f"{' *(control)*' if base else ''} "
                        f"| `{r.get('integration', '?')}` "
                        f"| {fmt(r.get('time_s'))} "
                        f"| {rel_cell(r.get('rel_time'), mad, base, 'faster', 'slower')} "
                        f"| {'–' if mad is None else f'{mad * 100:.1f}%'} "
                        f"| {rel_cell(r.get('rel_rss'), None, base, 'less', 'more')} |"
                    )
                print()
                for r in rows:
                    if r.get("rel_time") is not None:
                        per_arch_rows.setdefault(
                            (label(r), r.get("integration")), {}
                        )[arch] = r["rel_time"]

            for v in doc.get("verdicts", []):
                if v.get("within_noise"):
                    print(f">  **No winner claimed** for {v.get('group')}: {v.get('note')}\n")
                elif v.get("winner"):
                    print(f"> **Fastest** in {v.get('group')}: {v['winner']}. {v.get('note')}\n")

            errs = [f for f in doc.get("findings", []) if f.get("severity") == "ERROR"]
            if errs:
                print(f">  **{len(errs)} validation error(s)** in this dataset;")
                print("> the ranking above must not be trusted. See the artefact.\n")

    arches = sorted(found.keys())
    if len(arches) > 1 and per_arch_rows:
        print("## Does the ordering hold across architectures?\n")
        print("Ratios to each architecture's **own** control.  Lower is better in")
        print("every column, and a column is never comparable with another as an")
        print("absolute - only the ORDER within each is.\n")
        print("| allocator | mechanism | " + " | ".join(f"{a} ↓" for a in arches) + " |")
        print("| --- | --- |" + " --- |" * len(arches))
        for (alloc, mech), by_arch in sorted(per_arch_rows.items()):
            cells = " | ".join(fmt(by_arch.get(a)) for a in arches)
            print(f"| {alloc} | `{mech}` | {cells} |")
        print()
        print(" A row present on one architecture and `–` on another was not")
        print("measured there - it is a gap, never a zero.\n")

    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
