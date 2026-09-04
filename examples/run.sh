#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$HERE/.." && pwd)
OUTDIR="$HERE/out"
mkdir -p "$OUTDIR" || exit 2

RUNTIME=""
for r in docker podman; do
    if command -v "$r" >/dev/null 2>&1 && "$r" info >/dev/null 2>&1; then RUNTIME=$r; break; fi
done
if [ -z "$RUNTIME" ]; then
    echo "run.sh: no working container runtime (docker or podman)." >&2
    echo "run.sh: docs/containers.md has the fix; on a host where the client is" >&2
    echo "run.sh: installed but the daemon is not started, it is one command." >&2
    exit 2
fi

CA=""
for c in "$ROOT"/images/extra-ca/*.crt; do
    [ -f "$c" ] && { CA=$c; break; }
done

want=$*
selected=0
failed=0
ran=0

for script in "$HERE"/[0-9][0-9]-*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script" .sh)
    num=$(printf '%s' "$name" | cut -c1-2)

    if [ -n "$want" ]; then
        match=0
        for w in $want; do
            case "$name" in *"$w"*) match=1 ;; esac
            [ "$w" = "$num" ] && match=1
        done
        [ "$match" -eq 1 ] || continue
    fi
    selected=$((selected + 1))

    # One source of truth for the image: the example declares it, the driver
    # reads it. A mapping table here would be a second copy to go stale.
    image=$(sed -n 's/^# IMAGE: *//p' "$script" | head -1)
    if [ -z "$image" ]; then
        echo "run.sh: $name declares no '# IMAGE:' line" >&2
        failed=$((failed + 1))
        continue
    fi

    out="$OUTDIR/$name.txt"
    echo "=== $name  ($image) ==="

    set -- \
        --rm \
        -v "$HERE:/examples:ro" \
        -e "EXAMPLE=$name"
    if [ -n "$CA" ]; then
        set -- "$@" -v "$CA:/tmp/extra-ca.crt:ro"
    fi

    "$RUNTIME" run "$@" "$image" sh "/examples/$(basename "$script")" > "$out" 2>&1
    rc=$?
    ran=$((ran + 1))

    tail -n 14 "$out" | sed 's/^/    /'
    if [ "$rc" -eq 0 ]; then
        echo "    -> PASS (transcript: examples/out/$name.txt)"
    else
        echo "    -> FAIL rc=$rc (transcript: examples/out/$name.txt)"
        failed=$((failed + 1))
    fi
    echo
done

if [ "$selected" -eq 0 ]; then
    echo "run.sh: nothing matched '$want'. Available:" >&2
    for s in "$HERE"/[0-9][0-9]-*.sh; do [ -f "$s" ] && basename "$s" .sh; done >&2
    exit 2
fi

echo "run.sh: $ran example(s) ran, $failed failed."
[ "$failed" -eq 0 ] || exit 1
exit 0
