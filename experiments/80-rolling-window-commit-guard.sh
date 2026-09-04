#!/bin/sh
set -u

OUT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/out" 2>/dev/null && pwd) || {
    echo "experiments/out is missing" >&2
    exit 2
}
OUT="$OUT_DIR/80-rolling-window-commit-guard.txt"

command -v git >/dev/null 2>&1 || { echo "no git on PATH" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-80-roll-guard.$$"
trap 'rm -rf "$W"' EXIT INT TERM

rc=0
fail() { rc=1; echo " $1"; }

{
    echo "=== conditions ==="
    echo "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:  $(uname -srm)"
    echo "git:   $(git --version)"
    echo "scratch repository: $W"
    echo
    echo "=== the guard, as bench.yml had it, and as it now has it ==="
    echo "old:  if git diff --quiet -- results/rolling; then ... exit 0; fi"
    echo 'new:  if [ -z "$(git status --porcelain -- results/rolling)" ]; then ... exit 0; fi'
    echo

    rm -rf "$W"
    mkdir -p "$W" || exit 2
    cd "$W" || exit 2
    git init -q . || exit 2
    git config user.email probe@example.invalid
    git config user.name  probe

    # The tracked starting point: one window that already exists, shaped like
    # results/rolling/core-x86_64.
    mkdir -p results/rolling/core-x86_64/runs/r1
    echo 'aggregate v1' > results/rolling/core-x86_64/aggregate.md
    echo '{"runs":1}'   > results/rolling/core-x86_64/aggregate.json
    echo 'r1'           > results/rolling/core-x86_64/runs/r1/rankings.json
    git add -A
    git commit -qm base

    verdict() {   # $1 = expected verdict, $2 = case name
        git diff --quiet -- results/rolling
        old=$?
        if [ -z "$(git status --porcelain -- results/rolling)" ]; then new=0; else new=1; fi

        [ "$old" -eq 0 ] && old_v='SKIP' || old_v='COMMIT'
        [ "$new" -eq 0 ] && new_v='SKIP' || new_v='COMMIT'

        printf '  old guard  git diff --quiet        -> %s\n' "$old_v"
        printf '  new guard  git status --porcelain  -> %s\n' "$new_v"
        printf '  wanted                             -> %s\n' "$1"
        [ "$new_v" = "$1" ] || fail "$2: the NEW guard says $new_v, wanted $1"
        echo
    }

    echo "=== case 1: a window that does not exist yet ==="
    echo "(what a dispatch of a suite with no window does: profiles, 2026-09-02)"
    mkdir -p results/rolling/profiles-x86_64/runs/r9
    echo 'aggregate v1' > results/rolling/profiles-x86_64/aggregate.md
    echo 'r9'           > results/rolling/profiles-x86_64/runs/r9/rankings.json
    if [ -z "$(git status --porcelain -- results/rolling)" ]; then
        fail "case 1: the mutation did not land -- nothing to test"
    else
        printf '  mutation landed: %s\n' \
            "$(git status --porcelain -- results/rolling | tr '\n' ' ')"
        verdict COMMIT 'case 1'
    fi
    git clean -qfd results/rolling

    echo "=== case 2: an existing window gains a run ==="
    echo "(the case that DID work, and must keep working)"
    echo 'aggregate v2' > results/rolling/core-x86_64/aggregate.md
    mkdir -p results/rolling/core-x86_64/runs/r2
    echo 'r2' > results/rolling/core-x86_64/runs/r2/rankings.json
    if git diff --quiet -- results/rolling/core-x86_64/aggregate.md; then
        fail "case 2: the mutation did not land -- aggregate.md reads unchanged"
    else
        printf '  mutation landed: %s\n' \
            "$(git status --porcelain -- results/rolling | tr '\n' ' ')"
        verdict COMMIT 'case 2'
    fi
    git checkout -q -- results/rolling
    git clean -qfd results/rolling

    echo "=== case 3: nothing changed ==="
    echo "(a guard that always commits would pass case 1 and be worse)"
    printf '  mutation landed: %s\n' \
        "$(git status --porcelain -- results/rolling | tr '\n' ' ')(nothing, deliberately)"
    verdict SKIP 'case 3'

    echo "=== what this establishes ==="
    echo " \`git diff\` compares TRACKED paths. A window the fold step has just"
    echo "   created is untracked in every one of its files, so the old guard"
    echo "   reads it as 'unchanged', the step exits 0 having printed nothing,"
    echo "   and the folded window is discarded under a green tick."
    echo
    echo " It is the MIRROR IMAGE of the git_dirty defect fixed the same day in"
    echo "   crates/alloc-bench/src/envinfo.rs, where \`git status --porcelain\`"
    echo "   counted untracked files it should have ignored. Here the untracked"
    echo "   files are the entire change. Both directions of one confusion."
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether the FIXED job actually pushes. That is a property of the"
    echo "  runner's token and of main not having moved, and only a dispatch"
    echo "  answers it. docs/history/todo/instrument.md T-014 names the run that did."
    echo "- whether the two windows already in the tree are correct. They were"
    echo "  committed by hand and scripts/gate.sh re-derives them on every run."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
