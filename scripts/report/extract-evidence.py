#!/usr/bin/env python3
"""Extract a failing cell's evidence by RELEVANCE, not by `tail -n`.

 This project publishes failed configurations as results. It published them as
positional tails, and a tail is chosen by where a line sits in the file rather
than by what the failure is. What that cost, measured:

  $ grep -c 'multiple definition' \\
      results/published/2026-09-01-mechanisms-x86_64-run-c/evidence/link-override-mimalloc.txt
  0

`link-override` fails on musl-static with a NINE-symbol `multiple definition`
collision -- that is the finding, and it is what the A/B extract shows. Run C's
80-line tail of the same failure kept `__stack_chk_fail` and `__popcountdi2`
noise and cut the collision block entirely, so the tree could not confirm its own
headline. docs/AGENTS.md carries the caveat; docs/history/todo/instrument.md
T-011 is the entry.

 The tails were a deliberate size trade-off and the trade is defensible: a full
dataset is tens of megabytes. What is not defensible is choosing WHICH lines to
keep by their offset in the file.

Two modes.

  --run DIR --out DIR      extract every failing cell's diagnostics
  --check DIR --expect P   assert a COMMITTED extract still contains the failure
                           it was kept for

 The second exists because an extract that has quietly lost its finding is a
regression, not something a reader should discover. docs/methodology/experiments.md.

Exit 0 all good, 1 the assertion failed or a log was unreadable, 2 could not run.
 2 is never a pass.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

# Ordered most-diagnostic first. The order is the whole point: when a budget
# forces an elision, the line that names the failure survives and the noise goes,
# which is exactly the inversion a positional tail produced.
CLASSES: list[tuple[str, re.Pattern[str]]] = [
    ("multiple definition", re.compile(r"multiple definition of")),
    ("undefined reference", re.compile(r"undefined reference to")),
    ("undefined symbol", re.compile(r"undefined symbol|aliased to undefined symbol")),
    ("unsupported", re.compile(r"\bUNSUPPORTED\b")),
    ("error", re.compile(r"(?:^|[^\w])(?:error|fatal error):", re.I)),
    ("cannot find", re.compile(r"cannot find|No such file or directory")),
    ("collect2/ld", re.compile(r"^\s*(?:collect2|.*\bld):\s")),
]

# The absolute toolchain prefix an `ld` message carries makes two reports of the
# SAME symbol look like two findings. Strip it for de-duplication only -- the
# line is printed as it was written.
NOISE = re.compile(r"^\s*(?:/\S+/)?(?:[\w.+-]*ld|collect2)(?:\.\w+)?:\s*")
PATHY = re.compile(r"/\S{20,}")
OFFSET = re.compile(r"\(\s*\.[\w.$-]+\s*\+\s*0x[0-9a-fA-F]+\s*\)")

FLOOR_PER_CLASS = 3

def normalise(line: str) -> str:
    s = line.strip()
    s = NOISE.sub("", s)
    s = PATHY.sub("<path>", s)
    s = OFFSET.sub("(<offset>)", s)
    return re.sub(r"\s+", " ", s)

def classify(line: str) -> str | None:
    for name, pat in CLASSES:
        if pat.search(line):
            return name
    return None

def extract_one(log: str, budget: int) -> tuple[list[str], dict]:
    """Return the lines to publish and the accounting that makes the elision honest."""
    with open(log, "rb") as fh:
        raw = fh.read()
    text = raw.decode("utf-8", "replace")
    lines = text.splitlines()

    # first-seen order per class, de-duplicated on the normalised form
    buckets: dict[str, list[tuple[str, int]]] = {name: [] for name, _ in CLASSES}
    index: dict[tuple[str, str], int] = {}
    matched = 0
    for line in lines:
        cls = classify(line)
        if cls is None:
            continue
        matched += 1
        key = (cls, normalise(line))
        if key in index:
            buckets[cls][index[key]] = (buckets[cls][index[key]][0], buckets[cls][index[key]][1] + 1)
            continue
        index[key] = len(buckets[cls])
        buckets[cls].append((line.rstrip(), 1))

    present = [name for name, _ in CLASSES if buckets[name]]
    floor = min(FLOOR_PER_CLASS, max(1, budget // max(1, len(present))))
    quota = {name: min(len(buckets[name]), floor) for name in present}
    spare = budget - sum(quota.values())
    for name in present:
        if spare <= 0:
            break
        take = min(spare, len(buckets[name]) - quota[name])
        quota[name] += take
        spare -= take

    out: list[str] = []
    kept = 0
    dropped_classes: list[str] = []
    for name in present:
        rows = buckets[name]
        n_take = quota[name]
        if n_take <= 0:
            dropped_classes.append(f"{name} ({len(rows)} distinct)")
            continue
        out.append(f"--- {name}: {len(rows)} distinct ---")
        for line, n in rows[:n_take]:
            out.append(line if n == 1 else f"{line}    [x{n}]")
            kept += 1
        if n_take < len(rows):
            dropped_classes.append(f"{name} ({len(rows) - n_take} of {len(rows)} not shown)")

    stats = {
        "log_bytes": len(raw),
        "log_lines": len(lines),
        "diagnostic_lines": matched,
        "distinct_kept": kept,
        "elided_lines": len(lines) - kept,
        "classes": {n: len(b) for n, b in buckets.items() if b},
        "over_budget": dropped_classes,
    }
    return out, stats

def cell_outcomes(run: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for p in sorted(glob.glob(os.path.join(run, "results", "*.json"))):
        try:
            with open(p, encoding="utf-8") as fh:
                d = json.load(fh)
        except (OSError, json.JSONDecodeError):
            continue
        cid = (d.get("cell") or {}).get("id") or os.path.splitext(os.path.basename(p))[0]
        out[cid] = d.get("outcome") or "unknown"
    return out

def do_extract(run: str, outdir: str, want_all: bool, budget: int) -> int:
    if not os.path.isdir(os.path.join(run, "cells")):
        print(
            f"extract-evidence: {run!r} has no cells/ -- point --run at a LOCAL run "
            "directory; no published snapshot carries one, which is the gap this "
            "script exists to close",
            file=sys.stderr,
        )
        return 2
    outcomes = cell_outcomes(run)
    os.makedirs(outdir, exist_ok=True)
    written = 0
    problems = 0
    for cell in sorted(os.listdir(os.path.join(run, "cells"))):
        log = os.path.join(run, "cells", cell, "build.log")
        outcome = outcomes.get(cell, "unknown")
        if not want_all and outcome not in ("build_failed", "error", "unsupported"):
            continue
        if not os.path.isfile(log):
            print(f"extract-evidence: {cell}: {outcome} but no build.log", file=sys.stderr)
            problems += 1
            continue
        body, stats = extract_one(log, budget)
        dest = os.path.join(outdir, f"{cell}.txt")
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(f"# {cell}\n")
            fh.write(f"# outcome: {outcome}\n")
            fh.write(
                f"# source: cells/{cell}/build.log -- {stats['log_bytes']} bytes, "
                f"{stats['log_lines']} lines\n"
            )
            fh.write(
                f"# kept {stats['distinct_kept']} distinct diagnostic line(s) of "
                f"{stats['diagnostic_lines']} matching; {stats['elided_lines']} line(s) elided\n"
            )
            fh.write(f"# classes: {stats['classes'] or 'none'}\n")
            if stats["over_budget"]:
                fh.write(f"#  OVER BUDGET, not published: {', '.join(stats['over_budget'])}\n")
            fh.write(
                "#  Chosen by relevance, not by `tail -n`. The full log is not published;\n"
                "#   the byte count above is what it was.\n\n"
            )
            fh.write("\n".join(body) + ("\n" if body else ""))
        print(
            f"extract-evidence: {cell} ({outcome}) -> {os.path.relpath(dest)}: "
            f"{stats['distinct_kept']} line(s) from {stats['log_bytes']} bytes, "
            f"classes {stats['classes'] or '{}'}"
        )
        written += 1
    if written == 0:
        print(
            f"extract-evidence: no failing cell in {run!r} "
            "(pass --all to extract every cell)",
            file=sys.stderr,
        )
        return 2 if problems == 0 else 1
    print(f"extract-evidence: {written} extract(s) written to {outdir}")
    return 1 if problems else 0

def do_check(evdir: str, expects: list[str], require_each_file: bool) -> int:
    if not os.path.isdir(evdir):
        print(f"extract-evidence: {evdir!r} is not a directory", file=sys.stderr)
        return 2
    files = sorted(glob.glob(os.path.join(evdir, "*.txt")))
    if not files:
        print(f"extract-evidence: no .txt under {evdir!r}", file=sys.stderr)
        return 2
    bodies = {}
    for p in files:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                bodies[p] = fh.read()
        except OSError as e:
            print(f"extract-evidence: {p}: {e}", file=sys.stderr)
            return 2

    problems = 0
    for pat in expects:
        rx = re.compile(pat)
        hits = [p for p, b in bodies.items() if rx.search(b)]
        if require_each_file:
            missing = [p for p in files if p not in hits]
            if missing:
                problems += 1
                for p in missing:
                    print(
                        f"extract-evidence: {os.path.relpath(p)} no longer contains "
                        f"{pat!r} -- the extract has lost the failure it was kept for",
                        file=sys.stderr,
                    )
        elif not hits:
            problems += 1
            print(
                f"extract-evidence: no extract under {evdir} contains {pat!r} -- the "
                "evidence has lost the failure it was kept for",
                file=sys.stderr,
            )
        else:
            print(
                f"extract-evidence: {pat!r} present in "
                f"{', '.join(os.path.basename(p) for p in hits)}"
            )
    if problems:
        print(f"\nextract-evidence: {problems} expectation(s) not met.", file=sys.stderr)
        return 1
    print(f"extract-evidence: {len(files)} extract(s), every expectation met.")
    return 0

def selftest() -> int:
    import contextlib
    import io
    import tempfile

    checks: list[tuple[str, bool, str]] = []

    def ok(name, cond, detail=""):
        checks.append((name, bool(cond), detail))

    collision = [
        f"/usr/lib/gcc/x86_64-alpine-linux-musl/15.2.0/../bin/ld: multiple definition of `{s}'"
        for s in (
            "__libc_free", "__libc_malloc", "__libc_realloc", "aligned_alloc",
            "calloc", "free", "posix_memalign", "realloc", "strdup",
        )
    ]
    noise = [
        "/usr/lib/gcc/x86_64-alpine-linux-musl/15.2.0/../bin/ld: bitmap.c:(.text+0x%x): "
        "undefined reference to `__popcountdi2'" % (0x100 + i)
        for i in range(200)
    ]

    sink = io.StringIO()
    with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink), \
            tempfile.TemporaryDirectory() as td:
        run = os.path.join(td, "run")
        cid = "alpine-x86_64-mimalloc-link-override-static-pie-distro"
        os.makedirs(os.path.join(run, "cells", cid))
        os.makedirs(os.path.join(run, "results"))
        with open(os.path.join(run, "cells", cid, "build.log"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(["configuring"] * 50 + collision + noise) + "\n")
        with open(os.path.join(run, "results", cid + ".json"), "w", encoding="utf-8") as fh:
            json.dump({"cell": {"id": cid}, "outcome": "build_failed"}, fh)

        okc = "alpine-x86_64-system-baseline-static-pie-distro"
        os.makedirs(os.path.join(run, "cells", okc))
        with open(os.path.join(run, "cells", okc, "build.log"), "w", encoding="utf-8") as fh:
            fh.write("all good\n")
        with open(os.path.join(run, "results", okc + ".json"), "w", encoding="utf-8") as fh:
            json.dump({"cell": {"id": okc}, "outcome": "ok"}, fh)

        out = os.path.join(td, "ev")
        ok("extracts-a-failing-cell", do_extract(run, out, False, 120) == 0)
        ok("skips-a-passing-cell", not os.path.exists(os.path.join(out, okc + ".txt")))
        body = open(os.path.join(out, cid + ".txt"), encoding="utf-8").read()

        ok("keeps-every-collision-symbol", all(f"`{s}'" in body for s in (
            "__libc_free", "__libc_malloc", "__libc_realloc", "aligned_alloc",
            "calloc", "free", "posix_memalign", "realloc", "strdup")))
        payload = body.split("\n\n", 1)[1]
        ok("collision-outranks-the-noise",
           payload.index("multiple definition") < payload.index("__popcountdi2"))
        ok("de-duplicates-repeated-noise", body.count("__popcountdi2") < 20,
           f"count={body.count('__popcountdi2')}")
        ok("records-the-full-log-size", re.search(r"# source:.* \d+ bytes", body) is not None)
        ok("records-what-was-elided", re.search(r"\d+ line\(s\) elided", body) is not None)

        tail80 = "\n".join((["configuring"] * 50 + collision + noise)[-80:])
        ok("a-positional-tail-would-have-LOST-it", "multiple definition" not in tail80)

        # A budget too small to hold everything must still keep the collision and
        # must SAY what it dropped.
        small = os.path.join(td, "ev-small")
        do_extract(run, small, False, 12)
        sb = open(os.path.join(small, cid + ".txt"), encoding="utf-8").read()
        ok("a-tight-budget-still-keeps-the-collision", sb.count("multiple definition of") == 9)
        ok("a-budget-that-fits-declares-no-elision", "OVER BUDGET" not in sb)

        tiny = os.path.join(td, "ev-tiny")
        do_extract(run, tiny, False, 6)
        header = open(os.path.join(tiny, cid + ".txt"), encoding="utf-8").read().split("\n\n", 1)[0]
        ok("an-impossible-budget-declares-the-elision", "OVER BUDGET" in header)
        ok("an-impossible-budget-names-the-class-it-cut",
           "multiple definition (4 of 9 not shown)" in header, header.splitlines()[-1][:90])

        mixed = os.path.join(td, "ev-mixed")
        do_extract(run, mixed, False, 12)
        mb = open(os.path.join(mixed, cid + ".txt"), encoding="utf-8").read()
        ok("every-matched-class-survives-a-tight-budget",
           "--- multiple definition:" in mb and "--- undefined reference:" in mb)

        ok("check-passes-when-the-finding-is-present",
           do_check(out, ["multiple definition"], False) == 0)
        ok("check-refuses-when-the-finding-is-gone",
           do_check(out, ["this string is not in any extract"], False) == 1)

        lost = os.path.join(td, "ev-lost")
        os.makedirs(lost)
        with open(os.path.join(lost, "x.txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(noise[-80:]) + "\n")
        ok("check-refuses-a-tail-that-cut-the-collision",
           do_check(lost, ["multiple definition"], False) == 1)

        ok("cannot-run-on-a-snapshot-with-no-cells",
           do_extract(os.path.join(td, "nope"), out, False, 120) == 2)
        ok("cannot-run-on-an-empty-evidence-dir",
           do_check(os.path.join(td, "nothing-here"), ["x"], False) == 2)

    bad = [c for c in checks if not c[1]]
    for name, good, detail in checks:
        print(f"  {'ok   ' if good else 'FAIL '} {name}{(' ' + detail) if detail else ''}")
    print(f"extract-evidence --selftest: {len(checks)} check(s), {len(bad)} failure(s).")
    return 1 if bad else 0

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run", help="a LOCAL run directory (the one with cells/)")
    ap.add_argument("--out", help="where the extracts go")
    ap.add_argument("--all", action="store_true", help="extract every cell, not only failures")
    ap.add_argument(
        "--budget",
        type=int,
        default=120,
        help="most distinct lines to publish per cell (default 120)",
    )
    ap.add_argument("--check", help="a committed evidence directory to assert against")
    ap.add_argument(
        "--expect",
        action="append",
        default=[],
        help="a regex the evidence must still contain; repeatable",
    )
    ap.add_argument(
        "--expect-in-every-file",
        action="store_true",
        help="every extract must match, not just one of them",
    )
    ap.add_argument("--selftest", action="store_true", help="plant each defect and assert refusal")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    if args.check:
        if not args.expect:
            print("extract-evidence: --check needs at least one --expect", file=sys.stderr)
            return 2
        return do_check(args.check, args.expect, args.expect_in_every_file)
    if args.run:
        if not args.out:
            print("extract-evidence: --run needs --out", file=sys.stderr)
            return 2
        if args.budget < 1:
            print("extract-evidence: --budget must be at least 1", file=sys.stderr)
            return 2
        return do_extract(args.run, args.out, args.all, args.budget)
    ap.print_help()
    return 2

if __name__ == "__main__":
    sys.exit(main())
