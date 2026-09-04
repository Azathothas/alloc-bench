#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$HERE/.." && pwd)
OUT="$HERE/out/40-allocator-build-matrix.txt"
mkdir -p "$HERE/out" || exit 2

LOCK="$ROOT/allocators/allocators.lock.json"
[ -f "$LOCK" ] || { echo "40: no lock file at $LOCK; run alloc-bench update --write" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "40: no python3 on PATH" >&2; exit 2; }

RUNTIME=""
for r in docker podman; do
    if command -v "$r" >/dev/null 2>&1 && "$r" info >/dev/null 2>&1; then RUNTIME=$r; break; fi
done
[ -n "$RUNTIME" ] || { echo "40: no working container runtime (docker or podman)" >&2; exit 2; }

IMAGE=alloc-bench/alpine-x86_64:local
if ! "$RUNTIME" image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "40: image $IMAGE is not built." >&2
    echo "40: build it with any run, e.g. alloc-bench run --suite smoke --arch x86_64" >&2
    exit 2
fi

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# The allocators to sweep, and the commit each is pinned at. `system` is not a
# recipe -- it is the absence of one.
python3 - "$LOCK" "$ROOT/allocators/allocators.toml" > "$TMP/allocs.tsv" 2>"$TMP/allocs.err" <<'PY'
import json, re, sys
lock = json.load(open(sys.argv[1]))
toml = open(sys.argv[2], encoding="utf-8").read()
# Which integrations each allocator declares, so a refusal can be read against
# what it claims to support rather than against a guess.
ints = {}
for block in toml.split("[[allocator]]")[1:]:
    m = re.search(r'^\s*id\s*=\s*"([^"]+)"', block, re.M)
    if not m:
        continue
    i = re.search(r'^\s*integrations\s*=\s*\[([^\]]*)\]', block, re.M)
    ints[m.group(1)] = ",".join(re.findall(r'"([^"]+)"', i.group(1))) if i else ""
for aid, e in sorted(lock.get("entries", {}).items()):
    if aid in ("system", "ripgrep"):
        continue
    print("\t".join((aid, e["commit"], e.get("repo", "-"), ints.get(aid, ""))))
PY
if [ ! -s "$TMP/allocs.tsv" ]; then
    echo "40: could not read the allocator list" >&2
    sed 's/^/    /' "$TMP/allocs.err" >&2
    exit 2
fi

CACHE="$ROOT/.cache/alpine-x86_64"
mkdir -p "$CACHE/src" "$TMP/out" || exit 2
PIC=1
rc=0
built=0; refused=0; failed=0

{
    echo "=== conditions ==="
    echo "date          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host          $(uname -srm)"
    echo "runtime       $RUNTIME $("$RUNTIME" version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"
    echo "image         $IMAGE"
    echo "image digest  $("$RUNTIME" image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || echo '?')"
    echo "lock resolved $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("resolved_at","?"))' "$LOCK")"
    echo "PIC           $PIC (the PIC=0 axis is deliberately not swept -- see the header)"
    echo "libc / arch   musl / x86_64"
    echo

    echo "=== the recipes, by mode ==="
    echo
    printf '%-18s %-10s %-14s %-12s %s\n' allocator mode outcome seconds detail
    while IFS="$(printf '\t')" read -r aid commit repo integrations; do
        for mode in prefixed override; do
            prefix="$TMP/out/$aid-$mode"
            start=$(date +%s)
            set +e
            "$RUNTIME" run --rm \
                -v "$ROOT:/opt/alloc-bench:ro" \
                -v "$CACHE:/cache" \
                -v "$TMP:/tmp/probe" \
                -e "ALLOC_REPO=$repo" -e "ALLOC_COMMIT=$commit" -e "ALLOCATOR=$aid" \
                -e "MODE=$mode" -e "PIC=$PIC" -e "LIBC=musl" -e "TARGET_ARCH=x86_64" \
                "$IMAGE" sh -c '
                    set -u
                    src=/cache/src/$ALLOCATOR-$ALLOC_COMMIT
                    if [ ! -d "$src" ]; then
                        sh /opt/alloc-bench/scripts/build/fetch-source.sh \
                            "$ALLOC_REPO" "$ALLOC_COMMIT" "$src" >/dev/null 2>&1 \
                            || { echo "FETCH-FAILED"; exit 90; }
                    fi
                    recipe=/opt/alloc-bench/allocators/$ALLOCATOR/build.sh
                    [ -f "$recipe" ] || { echo "NO-RECIPE"; exit 91; }
                    out=/tmp/probe/out/$ALLOCATOR-$MODE
                    mkdir -p "$out"
                    SRC="$src" OUT="$out" MODE="$MODE" PIC="$PIC" LIBC="$LIBC" \
                    TARGET_ARCH="$TARGET_ARCH" NPROC="$(nproc 2>/dev/null || echo 2)" \
                    CC=cc CXX=c++ sh "$recipe" 2>&1
                ' > "$prefix.log" 2>&1
            r=$?
            set -e
            secs=$(( $(date +%s) - start ))

            archive="$prefix/lib/liballocbench.a"
            reason=$(grep '^UNSUPPORTED:' "$prefix.log" 2>/dev/null | head -1 | sed 's/^UNSUPPORTED: //')

            if [ "$r" -eq 0 ] && [ -f "$archive" ]; then
                outcome="built"; built=$((built + 1))
                detail="$(wc -c < "$archive" | tr -d ' ') bytes"
            elif [ "$r" -eq 0 ]; then
                outcome=" NO ARCHIVE"; failed=$((failed + 1)); rc=1
                detail="recipe exited 0 but produced no lib/liballocbench.a"
            elif [ "$r" -eq 3 ] && [ -n "$reason" ]; then
                outcome="unsupported"; refused=$((refused + 1))
                detail="$reason"
            elif [ "$r" -eq 3 ]; then
                outcome=" NO REASON"; failed=$((failed + 1)); rc=1
                detail="exit 3 with no UNSUPPORTED: line -- a refusal must carry its reason"
            else
                outcome=" failed"; failed=$((failed + 1)); rc=1
                detail="rc=$r: $(tail -2 "$prefix.log" | tr '\n' ' ' | cut -c1-110)"
            fi
            printf '%-18s %-10s %-14s %-12s %s\n' \
                "$aid" "$mode" "$outcome" "${secs}s" "$detail"
        done
    done < "$TMP/allocs.tsv"
    echo
    echo "declared integrations, for reading the refusals against what each claims:"
    while IFS="$(printf '\t')" read -r aid _ _ integrations; do
        printf '  %-18s %s\n' "$aid" "${integrations:-<none declared>}"
    done < "$TMP/allocs.tsv"
    echo

    echo "=== what this establishes ==="
    echo
    echo "built $built, unsupported-with-reason $refused, failed $failed"
    echo
    if [ "$rc" -eq 0 ]; then
        echo " Every allocator × mode either produced lib/liballocbench.a or refused"
        echo "   with a stated reason. The recipe layer is intact."
        echo
        echo " What it does NOT establish: that any of these archives LINKS into"
        echo "   ripgrep, that the resulting binary contains the allocator it says,"
        echo "   or anything about speed. Only \`alloc-bench run\` answers those, and"
        echo "   only the identity oracle answers the second."
    else
        echo " At least one combination failed, or refused without saying why."
        echo "   The per-recipe logs are gone with the temporary directory; re-run"
        echo "   the single case through run-cell.sh to keep them:"
        echo
        echo "     docs/static-linking.md, 'Doing it by hand'"
        echo
        echo " A recipe that exits 0 without producing lib/liballocbench.a is"
        echo "   reported as a failure here on purpose: the contract is the path,"
        echo "   not the exit code, and a silent empty success is the case a"
        echo "   downstream link failure would otherwise be blamed for."
    fi

    echo
    echo "exit $rc"
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
