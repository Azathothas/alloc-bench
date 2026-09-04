#!/usr/bin/env python3
"""Validate links, anchors, dataset routes, and document vintage commits.

Current Markdown is checked. Archived records under ``docs/history`` are not
instruction sources and may describe paths that existed before migration.
Exit 0 means valid, 1 means invalid, and 2 means the check could not run.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

SKIP_DIRS = {
    ".git",
    "docs/history",
    "target",
    "__pycache__",
    "node_modules",
    ".cache",
    "results/local",
}

MD_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
VINTAGE = re.compile(
    r"(?:Last reviewed|Last updated)[^\n]*?commit\s+`([0-9a-f]{7,40})`", re.I
)
# Anchored so a path *inside* an example command -- `/tmp/snap/results/published/fake`
# in a guard-mutation step -- is not read as a citation of a real dataset.
PUBLISHED = re.compile(r"(?<![\w/])results/published/([0-9A-Za-z._-]+)")

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,}).*?^ {0,3}\1[ \t]*$", re.S | re.M)
CODE_SPAN = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)", re.S)

def strip_code(text: str) -> str:
    """Blank out code so an EXAMPLE is not read as a reference.

    Two false positives paid for this, both raised by this checker against the
    document that describes its own guard-mutation test:

      * `operator delete[](void*)` in backticks -- which markdown genuinely
        parses as a link to `void*`, so a renderer makes the same mistake;
      * a deliberately imaginary `results/published/2099-01-01-imaginary` used
        to show the dataset check refusing.

    Fenced blocks go entirely. An inline span keeps its delimiters and length so
    that a link written as [`path`](path) still parses -- only the span's
    CONTENTS are neutralised.
    """
    text = FENCE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    return CODE_SPAN.sub(
        lambda m: m.group(1) + re.sub(r"[^\n]", "x", m.group(2)) + m.group(1), text
    )

def slug(heading: str) -> str:
    h = re.sub(r"`", "", heading.lstrip("#")).lower()
    h = re.sub(r"[^\w\s-]", "", h, flags=re.UNICODE)
    return re.sub(r"\s+", "-", h.strip())

def anchors_of(path: str) -> set[str]:
    out: set[str] = set()
    try:
        with open(path, encoding="utf-8") as fh:
            fenced = False
            for line in fh:
                if line.startswith("```"):
                    fenced = not fenced
                    continue
                if not fenced and line.startswith("#"):
                    out.add(slug(line))
    except OSError:
        pass
    return out

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".", help="repository root")
    ap.add_argument(
        "--strict",
        action="store_true",
        help="a check that could not run is a failure, not a skip (what CI passes)",
    )
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    if not os.path.isdir(os.path.join(root, "docs")):
        print(f"check-docs: no docs/ under {root!r}", file=sys.stderr)
        return 2

    docs: list[str] = []
    tracked: list[str] | None = None
    try:
        r = subprocess.run(
            ["git", "-C", root, "ls-files", "-z", "--cached", "--others",
             "--exclude-standard", "*.md"],
            capture_output=True,
            check=True,
        )
        tracked = [p for p in r.stdout.decode("utf-8", "replace").split("\0") if p]
    except FileNotFoundError:
        print("check-docs: git not on PATH", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError:
        tracked = None  # not a repository; fall back to the walk

    if tracked is not None:
        for rel in tracked:
            normalized = rel.replace("\\", "/")
            if any(
                normalized == d or normalized.startswith(d + "/")
                for d in SKIP_DIRS
            ):
                continue
            full = os.path.join(root, rel)
            if os.path.isfile(full):
                docs.append(full)
    else:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn.endswith(".md"):
                    docs.append(os.path.join(dirpath, fn))
    docs.sort()
    if not docs:
        print("check-docs: no markdown found", file=sys.stderr)
        return 2

    problems: list[str] = []
    skips: list[str] = []
    checked_links = 0

    shallow = os.path.exists(os.path.join(root, ".git", "shallow"))
    if shallow:
        skips.append(
            "the vintage check: this is a shallow clone, so no commit can be "
            "shown reachable from HEAD (fetch-depth: 0, or `git fetch --unshallow`)"
        )

    for doc in docs:
        rel = os.path.relpath(doc, root)
        here = os.path.dirname(doc)
        with open(doc, encoding="utf-8") as fh:
            raw = fh.read()
        text = strip_code(raw)

        for target in MD_LINK.findall(text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                if target.startswith("#"):
                    frag = target[1:]
                    if frag not in anchors_of(doc):
                        problems.append(f"{rel}: same-file anchor #{frag} matches no heading")
                continue
            path, _, frag = target.partition("#")
            if not path:
                continue
            checked_links += 1
            full = os.path.normpath(os.path.join(here, path))
            if not os.path.exists(full):
                problems.append(f"{rel}: link to {path} does not resolve")
                continue
            if frag and full.endswith(".md"):
                if frag not in anchors_of(full):
                    problems.append(f"{rel}: {path}#{frag} matches no heading in that file")

        for sha in [] if shallow else VINTAGE.findall(raw):
            try:
                subprocess.run(
                    ["git", "-C", root, "merge-base", "--is-ancestor", sha, "HEAD"],
                    check=True,
                    capture_output=True,
                )
            except FileNotFoundError:
                print("check-docs: git not on PATH", file=sys.stderr)
                return 2
            except subprocess.CalledProcessError:
                problems.append(
                    f"{rel}: names commit {sha} as its vintage, but that commit is not "
                    "reachable from HEAD -- a reader cannot establish which tree this "
                    "document describes"
                )

        for run in set(PUBLISHED.findall(text)):
            d = os.path.join(root, "results", "published", run)
            if not os.path.isdir(d):
                problems.append(f"{rel}: cites results/published/{run}, which does not exist")

    for s in skips:
        print(f"check-docs: SKIP {s}", file=sys.stderr)

    if problems:
        for p in problems:
            print(f"check-docs: {p}", file=sys.stderr)
        print(
            f"\ncheck-docs: {len(problems)} unresolved reference(s) across "
            f"{len(docs)} documents.",
            file=sys.stderr,
        )
        return 1

    if skips and args.strict:
        print(
            f"check-docs: --strict, and {len(skips)} check(s) could not run",
            file=sys.stderr,
        )
        return 1

    print(
        f"check-docs: {len(docs)} documents, {checked_links} relative links, "
        f"every reference resolves. {len(skips)} skipped."
    )
    return 0

if __name__ == "__main__":
    sys.exit(main())
