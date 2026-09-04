#!/bin/sh
set -u

OUT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/out" 2>/dev/null && pwd) || {
    echo "experiments/out is missing" >&2
    exit 2
}
OUT="$OUT_DIR/140-gate-sees-a-skip-below.txt"
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

command -v git     >/dev/null 2>&1 || { echo "no git on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3 on PATH" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-140-gate-skip.$$"
trap 'rm -rf "$W"' EXIT INT TERM

rc=0
fail() { rc=1; echo " $1"; }

{
    echo "=== conditions ==="
    echo "date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:    $(uname -srm)"
    echo "git:     $(git --version)"
    echo "python3: $(python3 --version 2>&1)"
    echo "tree:    $ROOT at $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "scratch: $W"
    echo

    rm -rf "$W"
    mkdir -p "$W" || exit 2

    echo "=== the two clones ==="
    git clone --depth 1 -q "file://$ROOT" "$W/shallow" 2>/dev/null || exit 2
    git clone -q         "file://$ROOT" "$W/full"    2>/dev/null || exit 2
    for c in shallow full; do
        cp "$ROOT/scripts/gate.sh"            "$W/$c/scripts/gate.sh"
        cp "$ROOT/scripts/check-docs.py"      "$W/$c/scripts/check-docs.py"
        cp "$ROOT/scripts/check-snapshots.py" "$W/$c/scripts/check-snapshots.py"
        printf '  %-8s is-shallow=%s  commits=%s\n' "$c" \
            "$(git -C "$W/$c" rev-parse --is-shallow-repository)" \
            "$(git -C "$W/$c" rev-list --count HEAD)"
    done
    echo

    # --- B: the two states, isolated ---------------------------------------
    echo "=== B. each checker, plain and --strict, in both clones ==="
    echo "(exit 0 = passed; exit 1 = refused. 'skips' is the checker's own count.)"
    echo
    printf '  %-22s %-8s %-14s %-14s\n' checker clone 'plain' '--strict'
    for chk in check-docs check-snapshots; do
        for c in shallow full; do
            p_out=$(cd "$W/$c" && python3 "scripts/$chk.py" 2>&1); p_rc=$?
            s_out=$(cd "$W/$c" && python3 "scripts/$chk.py" --strict 2>&1); s_rc=$?
            # The checker prints its own skip count in its last line.
            n=$(printf '%s\n' "$p_out" | sed -n 's/.*\([0-9][0-9]*\) skipped\..*/\1/p' | tail -1)
            printf '  %-22s %-8s rc=%s n=%-8s rc=%s\n' \
                "$chk.py" "$c" "$p_rc" "${n:-?}" "$s_rc"

            if [ "$c" = shallow ]; then
                [ "$p_rc" -eq 0 ] || fail "$chk.py plain in a shallow clone: expected 0, got $p_rc"
                [ "${n:-0}" -ge 1 ] || fail "$chk.py in a shallow clone reported no skip; the premise is gone"
                [ "$s_rc" -eq 1 ] || fail "$chk.py --strict in a shallow clone: expected 1, got $s_rc: $(printf '%s' "$s_out" | tail -1)"
            else
                [ "$p_rc" -eq 0 ] || fail "$chk.py plain in a full clone: expected 0, got $p_rc"
                [ "${n:-1}" -eq 0 ] || fail "$chk.py in a FULL clone skipped ($n); the control is not a control"
                [ "$s_rc" -eq 0 ] || fail "$chk.py --strict in a full clone: expected 0, got $s_rc: $(printf '%s' "$s_out" | tail -1)"
            fi
        done
    done
    echo

    # --- A: the production script -------------------------------------------
    echo "=== A. scripts/gate.sh --strict, unmodified, in the shallow clone ==="
    echo "(this builds the workspace in the clone; it is the real gate, not a"
    echo " reimplementation of it -- a probe that re-implements its subject is"
    echo " the defect T-019 was filed for, one level up)"
    echo
    g_out=$(cd "$W/shallow" && sh scripts/gate.sh --strict 2>&1); g_rc=$?
    printf '%s\n' "$g_out" | sed 's/^/  | /'
    echo
    echo "  gate exit code: $g_rc"

    if [ "$g_rc" -eq 0 ]; then
        fail "gate.sh --strict PASSED in a shallow clone -- the defect is back"
    fi
    for chk in check-docs check-snapshots; do
        if printf '%s\n' "$g_out" | grep -q "$chk"; then
            printf '   the refusal names %s\n' "$chk.py"
        else
            fail "gate.sh refused, but not because of $chk.py"
        fi
    done

    echo
    echo "=== what this establishes ==="
    echo " A gate that counts only the skips IT decided cannot see a skip one"
    echo "   level down. Two checkers retired a check each and the summary line"
    echo "   read '0 skipped' -- under --strict, whose entire job is to refuse a"
    echo "   skip. The check a session ran before pushing was weaker than the"
    echo "   one CI would run over the same tree."
    echo
    echo " Two independent guards now, on purpose. --strict is passed DOWN to"
    echo "   every checker that has it, so the gate runs CI's own invocation;"
    echo "   and a passing check's output is scanned for a skip marker, which is"
    echo "   what covers a checker with no such flag."
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether every checker the gate runs has been audited for internal"
    echo "  skips. alloc-runner selftest also skips and exits 0; it has nothing"
    echo "  to skip today, and the marker scan is what would catch it if it did."
    echo "- whether CI is right. CI already passed --strict; this probe is about"
    echo "  the gate having drifted below it."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
