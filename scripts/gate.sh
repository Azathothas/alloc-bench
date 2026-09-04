#!/bin/sh
# Run host-side validation. Container smoke testing is a separate required gate
# for changes to building, execution, measurement, images, or the matrix.

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

STRICT=0
if [ "${1:-}" = "--strict" ]; then
    STRICT=1
fi

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=''
SKIP_MARKER='(^|[[:space:]:])SKIP([[:space:]]|$)'

check() {
    name=$1
    shift
    printf '  %-48s ' "$name"
    if out=$("$@" 2>&1); then
        inner=$(printf '%s\n' "$out" | grep -E "$SKIP_MARKER" || true)
        if [ -n "$inner" ]; then
            n=$(printf '%s\n' "$inner" | wc -l | tr -d ' ')
            printf 'pass, %s skipped inside\n' "$n"
            printf '%s\n' "$inner" | sed 's/^ *//; s/^/      | /'
            PASS=$((PASS + 1))
            SKIP=$((SKIP + n))
        else
            printf 'pass\n'
            PASS=$((PASS + 1))
        fi
    else
        printf 'FAIL\n'
        FAIL=$((FAIL + 1))
        FAILED_NAMES="$FAILED_NAMES $name"
        printf '%s\n' "$out" | sed 's/^/      | /' | tail -25
    fi
}

skip() {
    printf '  %-48s SKIP (%s)\n' "$1" "$2"
    SKIP=$((SKIP + 1))
}

need() {
    command -v "$1" >/dev/null 2>&1
}

printf 'gate: host-side checks in %s\n\n' "$ROOT"

if need cargo; then
    check "cargo fmt --all --check" cargo fmt --all --check
    check "cargo clippy -D warnings" cargo clippy --workspace --all-targets -- -D warnings
    check "cargo test --workspace" cargo test --release --workspace
    check "cargo build --release" cargo build --release -p alloc-bench -p alloc-runner
else
    skip "Rust workspace" "cargo is not on PATH"
fi

if [ -x ./target/release/alloc-bench ]; then
    check "alloc-bench plan --suite all" ./target/release/alloc-bench plan --suite all
    check "alloc-bench doctor" ./target/release/alloc-bench doctor
else
    skip "alloc-bench plan and doctor" "release binary is not built"
fi

if [ -x ./target/release/alloc-runner ]; then
    check "alloc-runner selftest" ./target/release/alloc-runner selftest
else
    skip "alloc-runner selftest" "release binary is not built"
fi

shell_syntax() {
    find scripts allocators experiments examples -name '*.sh' -exec sh -n {} +
}
check "shell syntax" shell_syntax

if need shellcheck; then
    shellcheck_all() {
        find scripts allocators experiments examples -name '*.sh' -print0 \
            | xargs -0 shellcheck -S warning -e SC1091
    }
    check "shellcheck -S warning" shellcheck_all
else
    skip "shellcheck" "shellcheck is not installed"
fi

if need python3; then
    STRICT_ARG=''
    if [ "$STRICT" -eq 1 ]; then
        STRICT_ARG='--strict'
    fi

    # shellcheck disable=SC2086
    check "documentation references" python3 scripts/check-docs.py $STRICT_ARG
    # shellcheck disable=SC2086
    check "published snapshot structure" python3 scripts/check-snapshots.py $STRICT_ARG
    check "snapshot checker selftest" python3 scripts/check-snapshots.py --selftest
    check "evidence extractor selftest" python3 scripts/report/extract-evidence.py --selftest
    check "rolling aggregator selftest" python3 scripts/report/aggregate.py --selftest

    evidence_ok() {
        python3 scripts/report/extract-evidence.py \
            --check results/published/2026-09-01-mechanisms-x86_64/evidence \
            --expect 'multiple definition of .__libc_malloc' \
            --expect 'multiple definition of .strdup'
    }
    check "published failure evidence" evidence_ok

    rolling_ok() {
        rc=0
        for window in results/rolling/*/; do
            [ -d "$window/runs" ] || continue
            python3 scripts/report/aggregate.py --window "$window" --check >/dev/null || rc=1
            python3 scripts/report/aggregate.py --window "$window" >/dev/null || rc=1
        done
        if ! git diff --quiet -- results/rolling; then
            echo "results/rolling is stale; regenerate its aggregates"
            git diff --stat -- results/rolling
            rc=1
        fi
        return "$rc"
    }
    check "rolling windows coherent and current" rolling_ok
else
    skip "Python validation" "python3 is not on PATH"
fi

printf '\ngate: %s passed, %s failed, %s skipped.\n' "$PASS" "$FAIL" "$SKIP"

if [ "$FAIL" -gt 0 ]; then
    printf 'gate: failed:%s\n' "$FAILED_NAMES" >&2
    exit 1
fi
if [ "$SKIP" -gt 0 ] && [ "$STRICT" -eq 1 ]; then
    printf 'gate: --strict, and %s check(s) could not run\n' "$SKIP" >&2
    exit 1
fi
if [ "$PASS" -eq 0 ]; then
    printf 'gate: nothing ran\n' >&2
    exit 2
fi
