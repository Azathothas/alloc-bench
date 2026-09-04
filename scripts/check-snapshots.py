#!/usr/bin/env python3
"""Assert that every published snapshot carries the conditions its numbers need.

A published dataset is kept so a later session can answer questions about it.
One already could not: `mechanisms` run A was committed with its `rankings.json`
and **without its `run.json`**, so its CPU is unrecorded, and whether runs A and
B were the same host -- which decides whether a 20% disagreement is run-to-run
wander or a property of the machine -- cannot be established from the tree.
docs/AGENTS.md item 11 is that finding. Nothing prevented the next
snapshot doing the same; this does.

 A snapshot that keeps the numbers and drops the conditions cannot answer the
question it was kept for.

What it asserts, for every directory under `results/` that carries a
`rankings.json` -- a nested one included, because run A's splice is exactly
that, and the ROLLING WINDOW included, because `bench.yml` commits window runs
to `main` unattended and that is the tree deciding what transfers across
machines.  `results/local/` is gitignored and is skipped.

  1. `run.json` sits beside it and parses;
  2. every condition a reader needs is present and is not a placeholder:
     the host block (kernel, architecture, CPU model, core count, runtime),
     `tool_versions`, `corpus_seed` and `git_commit`;
  3. `git_commit` is a full sha, not a branch name or "unknown";
  4.  the tree that produced the numbers can still be OBTAINED. A sha is only
     half a condition: `mechanisms` run C records
     `e24709ba1f9bba9a40de5d38e55b186df17d83e7`, which is the head of the
     squash-merged branch of PR #1 and answers "could not get object info" in an
     ordinary clone. So a commit not reachable from HEAD has to carry a recovery
     route, in the snapshot's own README, naming both the commit and a
     `git fetch` that retrieves it.

  5.  the dataset REACHES A ROLLING WINDOW, or is accounted for by the window's
     own README. `results/rolling/` is the only thing in this repository that
     refuses an ordering, so a published dataset that never gets folded takes no
     part in what the project claims transfers across machines -- while looking,
     from the tree, exactly like one that does. On 2026-09-03 NINE of eighteen
     were in that state.  Absence is legitimate in two ways and both are
     derived rather than assumed: a FULL window may have evicted an older run
     (`keep` is read from the window's own `aggregate.json`), and a run whose
     candidate set differs from the window's belongs OUT of it -- rank means
     something different in a field of four than in a field of seven -- which
     the window's README argues, naming the run id.

  6.  a run whose containers were PINNED to a cpuset says so. `run.rs` gives
     every container the whole host on purpose -- "any cgroup limit here would
     become part of the result" -- and `ALLOC_BENCH_CPUSET` lifts that for one
     experiment (T-025). Its numbers look identical to an unconstrained run's,
     so the snapshot has to admit it in prose.

 Check 4 is the same wound as the vintage line `scripts/check-docs.py` guards
-- a document dating itself to `e24709b` -- found in a DATASET, which that
checker never looks at because it only reads markdown.  Check 5 is the same
shape as T-014, the path that PUBLISHES evidence failing quietly, one step
further out.

Exemptions are by name with the reason inline, because the alternative is
fabricating a number.  An exemption that stops being needed is itself a
failure, so the list cannot rot.

Exit 0 all good, 1 a snapshot cannot answer for itself, 2 could not run.  2 is
never a pass.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

SHA40 = re.compile(r"^[0-9a-f]{40}$")

# Values that are present but say nothing. A dash where the value is unknown is
# this project's convention; a word that LOOKS like data is worse than a gap,
# because a reader has no way to tell it apart from a recorded fact.
PLACEHOLDERS = {"", "-", "unknown", "none", "n/a", "null", "head", "0" * 40}

SKIP_UNDER = ("local",)  # gitignored working output, not a published claim

EXEMPT: dict[tuple[str, str], str] = {
    (
        "published/2026-09-01-mechanisms-x86_64/run-a-11member-splice",
        "run.json",
    ): (
        "run A was committed with rankings.json alone. Its conditions were never "
        "recorded, so reconstructing them would mean inventing a CPU model. "
        "docs/AGENTS.md item 11 is the finding this cost. "
        " Do not delete the directory to make this pass: section 11.2 cites its numbers."
    ),
    (
        "published/2026-09-01-core-x86_64",
        "git_commit",
    ): (
        "run.json records \"unknown\": `git rev-parse HEAD` failed at run time and "
        "the value was never captured. Every other condition is present, so the "
        "machine is answerable and only the tree is not."
    ),
    (
        "rolling/core-x86_64/runs/20260901-035224-local",
        "git_commit",
    ): (
        "the same run as published/2026-09-01-core-x86_64, folded into the rolling "
        "window, and it carries the same unrecorded commit.  Do not drop it from "
        "the window to make this pass: the window's whole claim is what held across "
        "ALL THREE machines, and removing one changes the answer."
    ),
}

REQUIRED_HOST = ("kernel", "arch", "cpu_model", "cpu_count", "container_runtime")

def is_placeholder(v: object) -> bool:
    if v is None:
        return True
    if isinstance(v, str):
        return v.strip().lower() in PLACEHOLDERS
    if isinstance(v, (dict, list)):
        return len(v) == 0
    return False

def snapshots(results: str) -> list[str]:
    """Every directory carrying a rankings.json, relative to results/.

     Recursive on purpose, and over the WHOLE of results/. Run A's splice is a
    SUBDIRECTORY of another snapshot, so a non-recursive walk misses the one
    defect this check was written for; and the rolling window's runs are
    snapshots by exactly this definition, committed to `main` by a workflow with
    nobody watching. Both were found by sweeping the callers rather than by
    writing the check.
    """
    out: list[str] = []
    for dirpath, dirnames, filenames in os.walk(results):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        rel = os.path.relpath(dirpath, results)
        if rel != "." and rel.split(os.sep)[0] in SKIP_UNDER:
            dirnames[:] = []
            continue
        if "rankings.json" in filenames:
            out.append(rel.replace(os.sep, "/"))
    return sorted(out)

def windows(results: str) -> dict[str, dict]:
    """Every rolling window, with the runs it holds and the size it keeps.

     `keep` is READ FROM THE WINDOW'S OWN `aggregate.json`, never typed here.
    It is the number that decides whether an absent snapshot was evicted or
    never folded, and a second copy of it in this file would be the standing-list
    defect T-019 was filed for: right until `--keep` changes, then silently
    wrong in the direction that hides work.
    """
    root = os.path.join(results, "rolling")
    out: dict[str, dict] = {}
    if not os.path.isdir(root):
        return out
    for name in sorted(os.listdir(root)):
        runsdir = os.path.join(root, name, "runs")
        if not os.path.isdir(runsdir):
            continue
        runs: dict[str, str] = {}
        for r in sorted(os.listdir(runsdir)):
            p = os.path.join(runsdir, r, "run.json")
            try:
                with open(p, encoding="utf-8") as fh:
                    m = json.load(fh)
            except (OSError, json.JSONDecodeError):
                continue
            rid = m.get("run_id")
            if isinstance(rid, str):
                runs[rid] = m.get("started_at") or ""
        keep = None
        try:
            with open(os.path.join(root, name, "aggregate.json"), encoding="utf-8") as fh:
                keep = ((json.load(fh).get("window") or {}).get("keep"))
        except (OSError, json.JSONDecodeError):
            pass
        readme = ""
        try:
            with open(os.path.join(root, name, "README.md"), encoding="utf-8") as fh:
                readme = fh.read()
        except OSError:
            pass
        out[name] = {
            "keep": keep,
            "runs": runs,
            "readme": readme,
            "oldest": min(runs.values()) if runs else None,
        }
    return out

def git_ok(root: str) -> bool:
    try:
        subprocess.run(
            ["git", "-C", root, "rev-parse", "--git-dir"],
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    return True

def reachable(root: str, sha: str) -> bool:
    """Is this commit obtainable by an ordinary `git checkout` here?

     One command answers both halves. An object that is absent from the clone
    is certainly not an ancestor of HEAD, so "we do not have it" and "we have it
    on a dead branch" collapse into the same verdict -- which is the verdict a
    READER cares about, and it needs no network.
    """
    r = subprocess.run(
        ["git", "-C", root, "merge-base", "--is-ancestor", sha, "HEAD"],
        capture_output=True,
    )
    return r.returncode == 0

def recovery_documented(snapdir: str, sha: str) -> bool:
    """Does the snapshot say how to get a commit that HEAD cannot reach?

    Both halves must be there: the commit named (7 hex is enough -- documents
    abbreviate), and a `git fetch` that retrieves it. Either alone leaves a
    reader stuck.
    """
    for name in ("README.md", "conditions.txt", "PROVENANCE.md"):
        p = os.path.join(snapdir, name)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        if sha[:7] in text and "git fetch" in text:
            return True
    return False

DIRTY_WORDS = ("uncommitted", "git_dirty", "dirty tree", "dirty checkout", "modified tree")

CPUSET_WORDS = ("cpuset", "pinned", "cpuset-cpus", "core count", "taskset")

def dirtiness_documented(snapdir: str) -> bool:
    """Does the snapshot admit, in prose, that its tree was not the commit?"""
    for name in ("README.md", "conditions.txt", "PROVENANCE.md"):
        p = os.path.join(snapdir, name)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                text = fh.read().lower()
        except OSError:
            continue
        if any(w in text for w in DIRTY_WORDS):
            return True
    return False

def constraint_documented(snapdir: str) -> bool:
    """Does the snapshot admit, in prose, that its containers were pinned?"""
    for name in ("README.md", "conditions.txt", "PROVENANCE.md"):
        p = os.path.join(snapdir, name)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="utf-8") as fh:
                text = fh.read().lower()
        except OSError:
            continue
        if any(w in text for w in CPUSET_WORDS):
            return True
    return False

def check(root: str, strict: bool = False, exempt: dict[tuple[str, str], str] | None = None) -> int:
    exempt = EXEMPT if exempt is None else exempt
    root = os.path.abspath(root)
    published = os.path.join(root, "results")
    if not os.path.isdir(published):
        print(f"check-snapshots: no results/ under {root!r}", file=sys.stderr)
        return 2

    dirs = snapshots(published)
    if not dirs:
        print("check-snapshots: no snapshot carries a rankings.json", file=sys.stderr)
        return 2

    problems: list[str] = []
    skips: list[str] = []
    used: set[tuple[str, str]] = set()
    imported: set[str] = set()
    import_file = os.path.join(published, "imported-commits.txt")
    if os.path.isfile(import_file):
        with open(import_file, encoding="utf-8") as fh:
            for line_no, line in enumerate(fh, 1):
                value = line.strip()
                if not value or value.startswith("#"):
                    continue
                if not SHA40.fullmatch(value):
                    problems.append(
                        f"results/imported-commits.txt:{line_no}: {value!r} is not a full SHA"
                    )
                else:
                    imported.add(value)
    notes: list[tuple[str, str]] = []
    wins = windows(published)

    all_ids: set[str] = set()
    for rel in dirs:
        try:
            with open(os.path.join(published, rel, "run.json"), encoding="utf-8") as fh:
                rid_ = json.load(fh).get("run_id")
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(rid_, str) and rid_:
            all_ids.add(rid_)
    ambiguous = {a for a in all_ids for b in all_ids if a != b and b.startswith(a)}
    for a in sorted(ambiguous):
        notes.append(
            ("AMBIGUOUS",
             f"run id {a!r} is a prefix of another run's id, so a window README naming "
            "the longer one would read as naming this one too -- this run cannot be "
             "accounted for by prose and must be folded or exempted")
        )

    have_git = git_ok(root)
    if not have_git:
        skips.append(
            f"the recovery check: {root!r} is not a git repository, so no commit can "
            "be shown reachable from HEAD"
        )
    elif os.path.exists(os.path.join(root, ".git", "shallow")):
        have_git = False
        skips.append(
            "the recovery check: this is a shallow clone, so a commit absent from it "
            "cannot be told apart from one on a dead branch "
            "(fetch-depth: 0, or `git fetch --unshallow`)"
        )

    for rel in dirs:
        snapdir = os.path.join(published, rel)
        runjson = os.path.join(snapdir, "run.json")

        if not os.path.isfile(runjson):
            key = (rel, "run.json")
            if key in exempt:
                used.add(key)
                notes.append(("EXEMPT", f"{rel}: no run.json -- exempt: {exempt[key]}"))
            else:
                problems.append(
                    f"{rel}: carries rankings.json but no run.json, so its numbers have "
                    "lost their conditions -- the machine, the toolchain and the tree "
                    "that produced them are unrecorded"
                )
            continue

        try:
            with open(runjson, encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, json.JSONDecodeError) as e:
            problems.append(f"{rel}: run.json does not parse: {e}")
            continue

        host = meta.get("host") or {}
        for field in REQUIRED_HOST:
            if is_placeholder(host.get(field)):
                problems.append(
                    f"{rel}: run.json host.{field} is {host.get(field)!r} -- a number "
                    "whose machine is unrecorded cannot be compared with another run's"
                )
        for field in ("tool_versions", "corpus_seed"):
            if is_placeholder(meta.get(field)):
                problems.append(f"{rel}: run.json {field} is {meta.get(field)!r}")

        sha = meta.get("git_commit")
        key = (rel, "git_commit")
        if not isinstance(sha, str) or not SHA40.match(sha.strip()):
            if key in exempt:
                used.add(key)
                notes.append(("EXEMPT", f"{rel}: git_commit {sha!r} -- exempt: {exempt[key]}"))
            else:
                problems.append(
                    f"{rel}: run.json git_commit is {sha!r}, not a full 40-hex sha -- "
                    "so the tree that produced these numbers cannot be checked out"
                )
        elif have_git:
            sha = sha.strip()
            if (
                not reachable(root, sha)
                and sha not in imported
                and not recovery_documented(snapdir, sha)
            ):
                problems.append(
                    f"{rel}: run.json names commit {sha[:8]}, which is not reachable "
                    "from HEAD, and the snapshot documents no way to obtain it -- add a "
                    "README naming the commit and the `git fetch` that recovers it"
                )

        if meta.get("git_dirty") is True and not dirtiness_documented(snapdir):
            problems.append(
                f"{rel}: run.json records git_dirty true, so commit {str(sha)[:8]} is "
                "NOT the tree that produced these numbers, and no README says so -- "
                "either re-run from a committed tree, or say in the README which "
                "uncommitted changes were in it and where they landed"
            )

        if host.get("cpuset") and not constraint_documented(snapdir):
            problems.append(
                f"{rel}: run.json records host.cpuset {host.get('cpuset')!r}, so every "
                "container was pinned and these timings are not comparable with a run "
                "that had the whole host -- and no README says so. Say it in the "
                "snapshot's README, or re-run unconstrained"
            )

        if wins is not None and not rel.startswith("rolling" + os.sep):
            key = (rel, "rolling")
            suite = (meta.get("suites") or [None])[0]
            arch = host.get("arch")
            wname = f"{suite}-{arch}"
            rid = meta.get("run_id")
            w = wins.get(wname)
            if key in exempt:
                used.add(key)
                notes.append(("EXEMPT", f"{rel}: not folded -- exempt: {exempt[key]}"))
            elif not isinstance(suite, str) or not isinstance(arch, str):
                problems.append(
                    f"{rel}: run.json records suites={meta.get('suites')!r} and "
                    f"host.arch={arch!r}, so the window it belongs in cannot be named"
                )
            elif w is None:
                problems.append(
                    f"{rel}: there is no results/rolling/{wname}/ at all, so this "
                    "dataset takes no part in what the project claims transfers "
                    "across machines -- fold it: python3 scripts/report/aggregate.py "
                    f"--window results/rolling/{wname} --add results/{rel}"
                )
            elif rid in w["runs"]:
                pass
            elif isinstance(rid, str) and rid and rid in w["readme"] and rid not in ambiguous:
                notes.append((
                    "ACCOUNTED",
                    f"{rel}: not in results/rolling/{wname}/, and that window's README "
                    f"names run {rid}",
                ))
            elif (
                w["keep"] is not None
                and len(w["runs"]) >= w["keep"]
                and w["oldest"] is not None
                and (meta.get("started_at") or "") < w["oldest"]
            ):
                notes.append((
                    "EVICTED?",
                    f"{rel}: absent from results/rolling/{wname}/, and older than every "
                    f"run in it -- a full window ({w['keep']}) may have evicted it",
                ))
            else:
                problems.append(
                    f"{rel}: run {rid} is not in results/rolling/{wname}/, which holds "
                    f"{len(w['runs'])} of {w['keep']}, and that window's README does not "
                    "name it -- so it was never folded, not evicted and not ruled out. "
                    "Either fold it (python3 scripts/report/aggregate.py --window "
                    f"results/rolling/{wname} --add results/{rel}), or -- if its "
                    "candidate set differs from the window's, which makes its ranks "
                    f"not comparable -- say so in results/rolling/{wname}/README.md, "
                    f"naming run {rid}"
                )

    for key, why in sorted(exempt.items()):
        if key not in used:
            problems.append(
                f"{key[0]}: exempt for {key[1]} but the exemption did not fire. Either "
                "the snapshot was repaired -- delete the row -- or it was renamed or "
                f"removed. Reason on file: {why}"
            )

    for label, n in notes:
        print(f"check-snapshots: {label} {n}")
    for s in skips:
        print(f"check-snapshots: SKIP {s}", file=sys.stderr)

    if problems:
        for p in problems:
            print(f"check-snapshots: {p}", file=sys.stderr)
        print(
            f"\ncheck-snapshots: {len(problems)} snapshot condition problem(s) across "
            f"{len(dirs)} snapshot(s).",
            file=sys.stderr,
        )
        return 1

    if skips and strict:
        print(
            f"check-snapshots: --strict, and {len(skips)} check(s) could not run",
            file=sys.stderr,
        )
        return 1

    print(
        f"check-snapshots: {len(dirs)} snapshot(s), every one carries its conditions. "
        f"{len(used)} exemption(s), "
        f"{sum(1 for lbl, _ in notes if lbl == 'ACCOUNTED')} accounted for elsewhere, "
        f"{len(skips)} skipped."
    )
    return 0

def _fold(results: str, run_id: str, started: str, window: str, keep: int = 6) -> None:
    """Put a fixture snapshot into a fixture rolling window.

     Only the two fields rule 5 reads -- `run_id` and `started_at` -- plus the
    window's own `keep`. A fixture that mirrored a real window would drift.
    """
    d = os.path.join(results, "rolling", window, "runs", run_id)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "run.json"), "w", encoding="utf-8") as fh:
        json.dump({"run_id": run_id, "started_at": started}, fh)
    agg = os.path.join(results, "rolling", window, "aggregate.json")
    n = len(os.listdir(os.path.join(results, "rolling", window, "runs")))
    with open(agg, "w", encoding="utf-8") as fh:
        json.dump({"window": {"keep": keep, "n_runs": n}}, fh)

def _snap(published: str, name: str, *, run=True, files=None, fold=True, **over) -> str:
    d = os.path.join(published, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "rankings.json"), "w", encoding="utf-8") as fh:
        json.dump({"primary_workload": "literal", "groups": []}, fh)
    if run:
        meta = {
            "run_id": name,
            "started_at": "2026-01-01T00:00:00Z",
            "suites": ["core"],
            "host": {
                "kernel": "Linux test",
                "arch": "x86_64",
                "cpu_model": "Test CPU",
                "cpu_count": 4,
                "container_runtime": "docker",
                "emulated": False,
            },
            "tool_versions": {"git": "git version 2.43.0"},
            "corpus_seed": 20260901,
            "git_commit": over.pop("git_commit", None),
        }
        for k, v in over.items():
            if k.startswith("host_"):
                meta["host"][k[5:]] = v
            else:
                meta[k] = v
        with open(os.path.join(d, "run.json"), "w", encoding="utf-8") as fh:
            json.dump(meta, fh)
        if fold:
            _fold(
                os.path.dirname(published),
                meta["run_id"],
                meta["started_at"],
                f"{meta['suites'][0]}-{meta['host']['arch']}",
            )
    for fn, body in (files or {}).items():
        with open(os.path.join(d, fn), "w", encoding="utf-8") as fh:
            fh.write(body)
    return d

def selftest() -> int:
    import contextlib
    import io
    import tempfile

    checks: list[tuple[str, bool, str]] = []

    def ok(name, cond, detail=""):
        checks.append((name, bool(cond), detail))

    sink = io.StringIO()
    with contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink), \
            tempfile.TemporaryDirectory() as td:
        env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t", **os.environ}
        run = lambda *a: subprocess.run(  # noqa: E731
            ["git", "-C", td, *a], capture_output=True, env=env, check=True
        )
        run("init", "-q", "-b", "main")
        pub = os.path.join(td, "results", "published")  # keys below are results-relative
        os.makedirs(pub)
        with open(os.path.join(td, "seed"), "w", encoding="utf-8") as fh:
            fh.write("seed\n")
        run("add", "-A")
        run("commit", "-qm", "seed")
        head = subprocess.run(
            ["git", "-C", td, "rev-parse", "HEAD"], capture_output=True, text=True, check=True
        ).stdout.strip()
        # A real commit that HEAD cannot reach: an orphan branch, which is what a
        # squash-merged PR head becomes.
        run("checkout", "-q", "--orphan", "sidebranch")
        run("commit", "-qm", "elsewhere", "--allow-empty")
        orphan = subprocess.run(
            ["git", "-C", td, "rev-parse", "HEAD"], capture_output=True, text=True, check=True
        ).stdout.strip()
        run("checkout", "-q", "main")

        _snap(pub, "good", git_commit=head)
        ok("a-complete-snapshot-passes", check(td, exempt={}) == 0)

        _snap(pub, "no-run-json", run=False)
        ok("refuses-a-snapshot-with-no-run-json", check(td, exempt={}) == 1)
        os.remove(os.path.join(pub, "no-run-json", "rankings.json"))
        os.rmdir(os.path.join(pub, "no-run-json"))

        _snap(pub, "nested/splice", run=False)
        ok("finds-a-NESTED-snapshot", check(td, exempt={}) == 1)
        ok(
            "an-exemption-lets-the-nested-one-through",
            check(td, exempt={("published/nested/splice", "run.json"): "known, unrepairable"}) == 0,
        )
        ok(
            "an-exemption-that-did-not-fire-is-itself-a-failure",
            check(td, exempt={
                ("published/nested/splice", "run.json"): "known",
                ("gone", "run.json"): "this snapshot no longer exists",
            }) == 1,
        )
        exempt_nested = {("published/nested/splice", "run.json"): "known, unrepairable"}

        for name, over, label in (
            ("no-cpu", {"host_cpu_model": ""}, "an-empty-cpu-model"),
            ("dash-cpu", {"host_cpu_model": "unknown"}, "a-placeholder-cpu-model"),
            ("no-kernel", {"host_kernel": None}, "a-missing-kernel"),
            ("no-runtime", {"host_container_runtime": ""}, "a-missing-container-runtime"),
            ("no-tools", {"tool_versions": {}}, "an-empty-tool_versions"),
            ("no-seed", {"corpus_seed": None}, "a-missing-corpus_seed"),
            ("unknown-commit", {"git_commit": "unknown"}, "git_commit-unknown"),
            ("branch-commit", {"git_commit": "main"}, "a-branch-name-for-a-commit"),
            ("short-commit", {"git_commit": head[:8]}, "an-abbreviated-commit"),
        ):
            d = _snap(pub, name, **{"git_commit": head, **over})
            ok(f"refuses-{label}", check(td, exempt=exempt_nested) == 1)
            for fn in os.listdir(d):
                os.remove(os.path.join(d, fn))
            os.rmdir(d)

        d = _snap(pub, "unreachable", git_commit=orphan)
        ok("refuses-an-unobtainable-commit", check(td, exempt=exempt_nested) == 1)
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write(f"measured at `{orphan}`\n")
        ok("a-commit-named-without-a-route-is-still-refused", check(td, exempt=exempt_nested) == 1)
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write(f"measured at `{orphan}`; recover with `git fetch origin sidebranch`\n")
        ok("a-documented-route-is-accepted", check(td, exempt=exempt_nested) == 0)
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("recover with `git fetch origin sidebranch`\n")
        ok("a-route-that-names-no-commit-is-refused", check(td, exempt=exempt_nested) == 1)
        for fn in os.listdir(d):
            os.remove(os.path.join(d, fn))
        os.rmdir(d)

        d = _snap(pub, "dirty", git_commit=head, git_dirty=True)
        ok("refuses-a-dirty-tree-that-says-nothing", check(td, exempt=exempt_nested) == 1)
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("a fine run on a fine host\n")
        ok(
            "a-README-that-does-not-mention-it-is-still-refused",
            check(td, exempt=exempt_nested) == 1,
        )
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("Built with UNCOMMITTED changes to images/debian.Dockerfile.\n")
        ok("a-documented-dirty-tree-is-accepted", check(td, exempt=exempt_nested) == 0)
        os.remove(os.path.join(d, "README.md"))
        _snap(pub, "dirty", git_commit=head, git_dirty=False)
        ok("a-recorded-CLEAN-tree-needs-no-note", check(td, exempt=exempt_nested) == 0)
        _snap(pub, "dirty", git_commit=head)
        ok("a-snapshot-predating-the-field-still-passes", check(td, exempt=exempt_nested) == 0)
        for fn in os.listdir(d):
            os.remove(os.path.join(d, fn))
        os.rmdir(d)

        d = _snap(pub, "pinned", git_commit=head, host_cpuset="0-1")
        ok("refuses-a-pinned-run-that-says-nothing", check(td, exempt=exempt_nested) == 1)
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("a fine run on a fine host\n")
        ok("a-README-that-does-not-mention-the-pinning-is-still-refused",
           check(td, exempt=exempt_nested) == 1)
        with open(os.path.join(d, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("Every container was pinned to a cpuset of two cores.\n")
        ok("a-documented-pinned-run-is-accepted", check(td, exempt=exempt_nested) == 0)
        os.remove(os.path.join(d, "README.md"))
        _snap(pub, "pinned", git_commit=head)
        ok("a-run-with-no-cpuset-recorded-needs-no-note",
           check(td, exempt=exempt_nested) == 0)
        for fn in os.listdir(d):
            os.remove(os.path.join(d, fn))
        os.rmdir(d)

        with open(os.path.join(pub, "good", "run.json"), "w", encoding="utf-8") as fh:
            fh.write("{not json")
        ok("refuses-a-run.json-that-does-not-parse", check(td, exempt=exempt_nested) == 1)
        _snap(pub, "good", git_commit=head)
        ok("and-the-tree-is-clean-again-before-the-next-case",
           check(td, exempt=exempt_nested) == 0)

        ok("cannot-run-without-a-results-tree", check(os.path.join(td, "nope")) == 2)
        empty = tempfile.mkdtemp()
        os.makedirs(os.path.join(empty, "results", "published"))
        ok("cannot-run-with-no-snapshots", check(empty) == 2)

        roll = os.path.join(td, "results", "rolling", "core-x86_64", "runs")
        os.makedirs(roll, exist_ok=True)
        _snap(roll, "20260101-000000-local", run=False, fold=False)
        ok("sweeps-the-rolling-window-too", check(td, exempt=exempt_nested) == 1)
        ok("and-results-local-is-skipped",
           "local" in SKIP_UNDER and not any(
               d.startswith("local") for d in snapshots(os.path.join(td, "results"))))
        for fn in os.listdir(os.path.join(roll, "20260101-000000-local")):
            os.remove(os.path.join(roll, "20260101-000000-local", fn))
        os.rmdir(os.path.join(roll, "20260101-000000-local"))

        _snap(pub, "unfolded", git_commit=head, fold=False)
        ok("refuses-a-published-snapshot-that-was-never-folded",
           check(td, exempt=exempt_nested) == 1)
        ok("an-exemption-lets-an-unfolded-one-through",
           check(td, exempt={**exempt_nested,
                             ("published/unfolded", "rolling"): "known"}) == 0)

        wdir = os.path.join(td, "results", "rolling", "core-x86_64")
        with open(os.path.join(wdir, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("this window restarted; the run is published in full instead\n")
        ok("a-README-that-does-not-name-the-run-is-not-enough",
           check(td, exempt=exempt_nested) == 1)
        with open(os.path.join(wdir, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("this window restarted; run `unfolded` is published in full instead\n")
        ok("a-window-README-naming-the-run-accounts-for-it",
           check(td, exempt=exempt_nested) == 0)
        _snap(pub, "unfolded-ci-runner", git_commit=head, fold=False)
        with open(os.path.join(wdir, "README.md"), "w", encoding="utf-8") as fh:
            fh.write("run `unfolded-ci-runner` is published in full instead\n")
        ok("a-run-id-that-prefixes-another-cannot-be-accounted-for-by-prose",
           check(td, exempt=exempt_nested) == 1)
        for fn in os.listdir(os.path.join(pub, "unfolded-ci-runner")):
            os.remove(os.path.join(pub, "unfolded-ci-runner", fn))
        os.rmdir(os.path.join(pub, "unfolded-ci-runner"))
        os.remove(os.path.join(wdir, "README.md"))

        res = os.path.join(td, "results")
        base = {**exempt_nested, ("published/unfolded", "rolling"): "known"}

        # (a) a window that is NOT full cannot have evicted anything, so an
        #     absence is "never folded" even for the oldest snapshot in the tree.
        _fold(res, "thin-1", "2026-06-01T00:00:00Z", "profiles-x86_64", keep=6)
        _snap(pub, "older-than-a-thin-window", git_commit=head, fold=False,
              suites=["profiles"], started_at="2020-01-01T00:00:00Z")
        ok("a-not-full-window-cannot-excuse-an-absence", check(td, exempt=base) == 1)
        base[("published/older-than-a-thin-window", "rolling")] = "known"

        # (b) once the window IS full, a snapshot older than everything in it
        #     cannot be told from one that was evicted, so it passes.
        for i in range(6):
            _fold(res, f"fat-{i}", f"2026-0{i + 1}-01T00:00:00Z", "distros-x86_64", keep=6)
        _snap(pub, "older-than-a-full-window", git_commit=head, fold=False,
              suites=["distros"], started_at="2020-01-01T00:00:00Z")
        ok("a-full-window-may-have-evicted-an-older-snapshot", check(td, exempt=base) == 0)

        # (c) …but only an OLDER one. A snapshot newer than the window's oldest
        #     run was skipped, not evicted, and a full window must not excuse it.
        _snap(pub, "newer-than-a-full-window", git_commit=head, fold=False,
              suites=["distros"], started_at="2026-12-01T00:00:00Z")
        ok("a-full-window-does-not-excuse-a-NEWER-absence", check(td, exempt=base) == 1)

    bad = [c for c in checks if not c[1]]
    for name, good, detail in checks:
        print(f"  {'ok   ' if good else 'FAIL '} {name}{(' ' + detail) if detail else ''}")
    print(f"check-snapshots --selftest: {len(checks)} check(s), {len(bad)} failure(s).")
    return 1 if bad else 0

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".", help="repository root")
    ap.add_argument(
        "--strict",
        action="store_true",
        help="a check that could not run is a failure, not a skip (what CI passes)",
    )
    ap.add_argument(
        "--selftest", action="store_true", help="plant each defect and assert refusal"
    )
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    return check(args.root, strict=args.strict)

if __name__ == "__main__":
    sys.exit(main())
