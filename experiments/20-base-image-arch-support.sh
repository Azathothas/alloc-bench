#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
OUT="$HERE/out/20-base-image-arch-support.txt"
mkdir -p "$HERE/out" || exit 2

RT=""
for c in docker podman; do
    if command -v "$c" >/dev/null 2>&1 && "$c" info >/dev/null 2>&1; then RT="$c"; break; fi
done
[ -n "$RT" ] || { echo "20: no working container runtime" >&2; exit 2; }

REQUIRED="amd64 arm64"
IMAGES="alpine:latest debian:latest archlinux:latest menci/archlinuxarm:base-devel"

rc=0
{
    echo "=== conditions ==="
    echo "date          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host          $(uname -srm)"
    echo "runtime       $RT $("$RT" --version 2>/dev/null | head -1)"
    echo "required      $REQUIRED"
    echo

    for img in $IMAGES; do
        raw=$("$RT" manifest inspect "$img" 2>/dev/null)
        if [ -z "$raw" ]; then
            printf '%-34s %s\n' "$img" "COULD NOT INSPECT (network, or the tag is gone)"
            rc=2
            continue
        fi
        arches=$(printf '%s' "$raw" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ms = d.get("manifests", [])
if ms:
    a = sorted({m["platform"]["architecture"] for m in ms
                if m["platform"]["architecture"] != "unknown"})
else:
    a = [d.get("architecture", "?")]
print(" ".join(a))
' 2>/dev/null)
        printf '%-34s %s\n' "$img" "$arches"
        for want in $REQUIRED; do
            case " $arches " in
                *" $want "*) ;;
                *)
                    case "$img" in
                        menci/*) ;;   # the substitute, checked below on its own terms
                        *)
                            echo "     $img does not publish $want"
                            rc=1 ;;
                    esac ;;
            esac
        done
    done

    echo
    echo "=== what this means for the matrix ==="
    echo "Arch publishes amd64 only. Upstream Arch does not support aarch64;"
    echo "Arch Linux ARM is a SEPARATE project with its own package set and its"
    echo "own build of glibc."
    echo
    echo "So this project does not label an aarch64 build \`archlinux\`. The"
    echo "planner renames the distribution to \`archlinuxarm\` on that"
    echo "architecture (crates/alloc-bench/src/plan.rs, effective_distro), and"
    echo "the two never share a table row."
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether the published image for an architecture actually WORKS;"
    echo "  a manifest entry is a claim of availability, not of function."
    echo "  images/*.Dockerfile building successfully is that evidence."
    echo
    if [ "$rc" -eq 1 ]; then
        echo "RESULT: exit 1 ON PURPOSE. A gap is present and is documented above."
        echo "If a future run exits 0, upstream has started publishing the missing"
        echo "architecture and images/arch.Dockerfile's substitution can be retired."
    fi
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
