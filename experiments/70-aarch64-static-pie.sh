#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
OUT="$HERE/out/70-aarch64-static-pie.txt"
mkdir -p "$HERE/out" || exit 2

command -v rustc >/dev/null 2>&1 || { echo "70: no rustc on PATH" >&2; exit 2; }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT
printf 'fn main() { println!("hello"); }\n' > "$TMP/main.rs"

PROFILE_FLAGS="-C target-feature=+crt-static -C relocation-model=pic"
TARGETS="x86_64-unknown-linux-musl aarch64-unknown-linux-musl"

installed=$(rustc --print target-libdir --target aarch64-unknown-linux-musl 2>/dev/null || true)
if [ -z "$installed" ] || [ ! -d "$installed" ]; then
    echo "70: aarch64-unknown-linux-musl std is not installed" >&2
    echo "70: run \`rustup target add aarch64-unknown-linux-musl\` first" >&2
    exit 2
fi

rc=0
{
    echo "=== conditions ==="
    echo "date          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host          $(uname -srm)"
    echo "rustc         $(rustc --version)"
    echo "profile flags $PROFILE_FLAGS"
    echo

    echo "=== 1. what rustc puts on the link line ==="
    echo
    printf '%-30s %-10s %-24s %s\n' target rc driver "link mode"
    for t in $TARGETS; do
        rustc --target "$t" $PROFILE_FLAGS -C opt-level=0 \
            "$TMP/main.rs" -o "$TMP/out-$t" > "$TMP/err-$t" 2>&1
        r=$?
        driver=$(sed -n 's/.*linking with `\([^`]*\)`.*/\1/p' "$TMP/err-$t" | head -1)
        [ -n "$driver" ] || driver="(linked, no error)"
        mode=$(grep -o '"-static-pie"\|"-static"\|"-no-pie"\|"-pie"' "$TMP/err-$t" \
               | sort -u | tr -d '"' | tr '\n' ' ')
        if [ -z "$mode" ] && [ -f "$TMP/out-$t" ]; then
            case $(od -An -tx1 -j16 -N2 "$TMP/out-$t" | tr -d ' ') in
                0300) mode="(linked: ELF type DYN -- a static-PIE)" ;;
                0200) mode="(linked: ELF type EXEC -- plain static)" ;;
                *)    mode="(linked: ELF type unread)" ;;
            esac
        fi
        printf '%-30s %-10s %-24s %s\n' "$t" "$r" "$driver" "${mode:-(none seen)}"
    done
    echo
    echo " A non-zero rc for aarch64 here is EXPECTED on an x86_64 host with no"
    echo "  aarch64 cc: the link dies on 'Relocations in generic ELF (EM: 183)'."
    echo "  The link MODE above is what rustc asked for, and is emitted either way."
    echo

    echo "=== 2. rustc's own target definition ==="
    echo
    printf '%-30s %-46s %s\n' target static-position-independent-executables linker-flavor
    spie_aarch64=""
    for t in $TARGETS; do
        if ! RUSTC_BOOTSTRAP=1 rustc -Z unstable-options --print target-spec-json \
                --target "$t" > "$TMP/spec-$t.json" 2>"$TMP/spec-$t.err"; then
            printf '%-30s %s\n' "$t" "COULD NOT READ THE TARGET SPEC"
            sed 's/^/    /' "$TMP/spec-$t.err"
            rc=2
            continue
        fi
        vals=$(python3 - "$TMP/spec-$t.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("%s\t%s" % (d.get("static-position-independent-executables", "ABSENT"),
                  d.get("linker-flavor", "?")))
PY
) || { rc=2; continue; }
        spie=$(printf '%s' "$vals" | cut -f1)
        flavor=$(printf '%s' "$vals" | cut -f2)
        printf '%-30s %-46s %s\n' "$t" "$spie" "$flavor"
        case "$t" in aarch64-*) spie_aarch64="$spie" ;; esac
    done
    echo

    echo "=== what this establishes ==="
    echo
    if [ "$spie_aarch64" = "True" ] || [ "$spie_aarch64" = "true" ]; then
        echo " aarch64-unknown-linux-musl NOW asks for a static-PIE."
        echo "   The limitation has gone. Retire the unsupported rule in"
        echo "   crates/alloc-bench/src/plan.rs and the profiles_by_arch override"
        echo "   on the core suite in benchmarks/matrix.toml, and re-run"
        echo "   \`alloc-bench plan --suite core --arch aarch64\`."
    elif [ "$rc" -eq 2 ]; then
        echo "The target spec could not be read, so nothing is established."
    else
        rc=1
        echo " static-PIE is decided by ONE BOOLEAN IN RUSTC, not by the linker."
        echo
        echo "   x86_64-unknown-linux-musl  sets static-position-independent-executables"
        echo "   aarch64-unknown-linux-musl leaves it unset"
        echo
        echo "   so rustc emits -static -no-pie on the aarch64 link line and"
        echo "   -static-pie on the x86_64 one."
        echo
        echo " BOTH targets already use the gnu-cc linker flavour -- the gcc"
        echo "   driver. So 'use gcc instead of rust-lld' is not a lever: it is"
        echo "   already what happens. The previously recorded reason ('rust-lld"
        echo "   rejects the argument') does not describe this."
        echo
        echo "   -C link-arg=-static-pie only APPENDS the flag; rustc's own"
        echo "   -static -no-pie stay on the line beside it."
        echo
        echo "RESULT: exit 1 ON PURPOSE. The project publishes aarch64/musl"
        echo "static-pie* cells as unsupported with this reason, and runs \`core\`"
        echo "on the non-PIE static-lto profile there. docs/history/todo/platform.md T-002."
    fi
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether the aarch64 musl LINKER would accept -static-pie if asked."
    echo "  rustc never asks, and this host has no aarch64 cc to ask it with."
    echo "- whether a CUSTOM target JSON with the flag flipped, built with"
    echo "  -Z build-std, would produce a working static-PIE. Untested, and it"
    echo "  would mean shipping a custom rustc target."
    echo " So 'impossible' is not what this says. 'Not achievable from the"
    echo "  stable toolchain as it stands' is."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
