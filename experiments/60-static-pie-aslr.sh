#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$HERE/.." && pwd)
OUT="$HERE/out/60-static-pie-aslr.txt"
DOC="$ROOT/docs/static-linking.md"
mkdir -p "$HERE/out" || exit 2

command -v rustc >/dev/null 2>&1 || { echo "60: no rustc on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "60: no python3 on PATH" >&2; exit 2; }
[ -f "$DOC" ] || { echo "60: $DOC not found" >&2; exit 2; }

RUNNER="$ROOT/target/release/alloc-runner"
[ -x "$RUNNER" ] || { echo "60: $RUNNER not built (cargo build --release)" >&2; exit 2; }

TARGET=x86_64-unknown-linux-musl
libdir=$(rustc --print target-libdir --target "$TARGET" 2>/dev/null || true)
if [ -z "$libdir" ] || [ ! -d "$libdir" ]; then
    echo "60: $TARGET std is not installed; rustup target add $TARGET" >&2
    exit 2
fi

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# Ignores its arguments -- aslr-probe passes ripgrep's -- and stays mapped long
# enough for the parent to read /proc/<pid>/maps.
cat > "$TMP/m.rs" <<'RS'
fn main() {
    let t = std::time::Instant::now();
    let mut x: u64 = 0;
    while t.elapsed().as_millis() < 400 { x = x.wrapping_add(1); }
    if x == u64::MAX { println!("{}", x); }
}
RS

python3 - "$DOC" > "$TMP/expect.tsv" 2>"$TMP/parse.err" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8").read()
rows = {}
order = []
for line in text.splitlines():
    m = re.match(r"^\|\s*`([a-z-]+)`\s*\|(.*)\|\s*$", line)
    if not m:
        continue
    name, rest = m.group(1), m.group(2)
    cells = [c.strip() for c in rest.split("|")]
    if len(cells) != 3:          # RUSTFLAGS, ELF result, ASLR
        continue
    rows[name] = cells
    order.append(name)

def resolve(name, idx, seen=()):
    if name in seen:
        raise SystemExit(f"cycle resolving {name}")
    cell = rows[name][idx]
    m = re.match(r"^as\s+`([a-z-]+)`", cell)
    if m:
        return resolve(m.group(1), idx, seen + (name,))
    return cell

if not order:
    sys.exit("no profile table found in the document")

for name in order:
    elf = resolve(name, 1)
    aslr = resolve(name, 2)
    exec_dyn = "EXEC" if "ET_EXEC" in elf else ("DYN" if "ET_DYN" in elf else "?")
    interp = "no" if re.search(r"no\s+`?PT_INTERP", elf) else (
        "yes" if "PT_INTERP" in elf else "?")
    want = "yes" if re.match(r"^\**yes", aslr) else (
        "no" if re.match(r"^\**no", aslr) else "?")
    if "?" in (exec_dyn, interp, want):
        sys.exit(f"row {name}: could not read {elf!r} / {aslr!r}")
    print("\t".join((name, exec_dyn, interp, want)))
PY
if [ ! -s "$TMP/expect.tsv" ]; then
    echo "60: could not parse the profile table out of $DOC" >&2
    sed 's/^/    /' "$TMP/parse.err" >&2
    exit 2
fi

if ! "$RUNNER" gen-corpus --out "$TMP/corpus" --seed 20260901 --profile smoke \
        > "$TMP/corpus.log" 2>&1; then
    echo "60: gen-corpus failed" >&2
    tail -5 "$TMP/corpus.log" >&2
    exit 2
fi

flags_for() {
    case "$1" in
        static)         echo "-C target-feature=+crt-static -C relocation-model=static" ;;
        static-lto)     echo "-C target-feature=+crt-static -C relocation-model=static -C lto=fat" ;;
        static-pie)     echo "-C target-feature=+crt-static -C relocation-model=pic" ;;
        static-pie-lto) echo "-C target-feature=+crt-static -C relocation-model=pic -C lto=fat" ;;
        dynamic)        echo "-C target-feature=-crt-static" ;;
        *)              echo "" ;;
    esac
}

RUNS=6
rc=0
{
    echo "=== conditions ==="
    echo "date          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host          $(uname -srm)"
    echo "rustc         $(rustc --version)"
    echo "target        $TARGET"
    echo "instrument    $RUNNER"
    echo "corpus        smoke, seed 20260901"
    echo "aslr samples  $RUNS per profile"
    echo "document      docs/static-linking.md (expectations parsed from it)"
    echo "subject       a 6-line Rust program, NOT ripgrep -- see the header"
    echo

    echo "=== what the document claims ==="
    echo
    printf '%-16s %-10s %-10s %s\n' profile "ELF type" PT_INTERP "ASLR"
    while IFS="$(printf '\t')" read -r name elf interp want; do
        printf '%-16s %-10s %-10s %s\n' "$name" "$elf" "$interp" "$want"
    done < "$TMP/expect.tsv"
    echo

    echo "=== what the artefacts do ==="
    echo
    printf '%-16s %-12s %-10s %-12s %-8s %s\n' \
        profile "link kind" PT_INTERP "bases seen" ASLR verdict
    while IFS="$(printf '\t')" read -r name elf interp want; do
        f=$(flags_for "$name")
        if [ -z "$f" ]; then
            printf '%-16s %s\n' "$name" "NO FLAGS KNOWN for this profile -- the document lists a profile this script does not build"
            rc=2
            continue
        fi
        # shellcheck disable=SC2086
        if ! rustc --target "$TARGET" $f -C opt-level=1 -C codegen-units=1 \
                "$TMP/m.rs" -o "$TMP/bin-$name" > "$TMP/build-$name.err" 2>&1; then
            printf '%-16s %s\n' "$name" "BUILD FAILED: $(head -1 "$TMP/build-$name.err")"
            rc=2
            continue
        fi

        ident=$("$RUNNER" identify --bin "$TMP/bin-$name" 2>/dev/null | head -1)
        kind=$(printf '%s' "$ident" | python3 -c 'import json,sys; print(json.load(sys.stdin)["link_kind"])' 2>/dev/null || echo "?")
        has_interp=$(printf '%s' "$ident" | python3 -c 'import json,sys; print("no" if json.load(sys.stdin)["interp"] is None else "yes")' 2>/dev/null || echo "?")

        probe=$("$RUNNER" aslr-probe --bin "$TMP/bin-$name" --corpus "$TMP/corpus" \
                    --runs "$RUNS" 2>/dev/null | head -1)
        seen=$(printf '%s' "$probe" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%d of %d" % (d["distinct_bases"], d["sampled"]))' 2>/dev/null || echo "?")
        got=$(printf '%s' "$probe" | python3 -c 'import json,sys; print("yes" if json.load(sys.stdin)["randomised"] else "no")' 2>/dev/null || echo "?")

        # The document says ET_EXEC/ET_DYN; the instrument says static /
        # static-pie / dynamic. They are the same statement in two vocabularies.
        want_kind=""
        case "$elf-$interp" in
            EXEC-no)  want_kind=static ;;
            DYN-no)   want_kind=static-pie ;;
            DYN-yes)  want_kind=dynamic ;;
        esac

        verdict="ok"
        if [ "$kind" = "?" ] || [ "$got" = "?" ]; then
            verdict="COULD NOT READ"; rc=2
        elif [ "$kind" != "$want_kind" ]; then
            verdict=" link kind: document says $want_kind"; rc=${rc:-0}; [ "$rc" -eq 2 ] || rc=1
        elif [ "$has_interp" != "$interp" ]; then
            verdict=" PT_INTERP: document says $interp"; [ "$rc" -eq 2 ] || rc=1
        elif [ "$got" != "$want" ]; then
            verdict=" ASLR: document says $want"; [ "$rc" -eq 2 ] || rc=1
        fi
        printf '%-16s %-12s %-10s %-12s %-8s %s\n' \
            "$name" "$kind" "$has_interp" "$seen" "$got" "$verdict"
    done < "$TMP/expect.tsv"
    echo

    echo "=== what this establishes ==="
    echo
    if [ "$rc" -eq 0 ]; then
        echo " Every profile in docs/static-linking.md's table behaves as the table"
        echo "   says: the ELF type, the presence of PT_INTERP, and the OBSERVED"
        echo "   load address all agree, on this host, with this rustc."
        echo
        echo " What it does NOT establish: anything about ripgrep's build, which"
        echo "   adds a stack-size link argument and an allocator archive; and"
        echo "   anything about another kernel's randomize_va_space."
    elif [ "$rc" -eq 1 ]; then
        echo " A profile disagrees with the document. Read the verdict column."
        echo
        echo "   Two things it can mean, and they need opposite fixes:"
        echo "     - the BUILD changed (a rustc upgrade, a target-spec change):"
        echo "       fix the build or update the table, having measured it;"
        echo "     - the TABLE was edited to claim something untrue: fix the row."
        echo
        echo " Do not 'fix' this by editing the table to match the output"
        echo "   without establishing which of the two happened."
    else
        echo "The measurement could not run, so NOTHING is established here."
        echo " 2 is not a pass. See the rows above for what could not be read."
    fi

    echo
    echo "exit $rc"
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
