#!/bin/sh
set -u

: "${OUTDIR:?OUTDIR is required}"
: "${CELL_ID:?CELL_ID is required}"
: "${ALLOCATOR:=system}"
: "${INTEGRATION:=baseline}"
: "${PROFILE:=static-pie}"
: "${TOOLCHAIN:=distro}"
: "${LIBC:=musl}"
: "${TARGET_ARCH:=$(uname -m)}"
: "${CORPUS_PROFILE:=standard}"
: "${CORPUS_SEED:=20260901}"
: "${REPEAT:=10}"
: "${WARMUP:=2}"
: "${RG_REPO:=https://github.com/BurntSushi/ripgrep}"
: "${RG_COMMIT:?RG_COMMIT is required}"
: "${ALLOC_REPO:=}"
: "${ALLOC_COMMIT:=}"
: "${CACHE:=/cache}"
: "${HM_VARIANT:=default}"

ROOT=/opt/alloc-bench
RUNNER=/usr/local/bin/alloc-runner
LOG="$OUTDIR/steps.log"

mkdir -p "$OUTDIR" "$CACHE"
: > "$LOG"

say()  { printf '[cell %s] %s\n' "$CELL_ID" "$1" | tee -a "$LOG"; }
fail() { printf '%s\n' "$1" > "$OUTDIR/reason"; printf '%s\n' "$2" > "$OUTDIR/status"; say "$2: $1"; exit "${3:-1}"; }

# The toolchain is a recorded dimension, not an accident of PATH.
case "$TOOLCHAIN" in
    distro) CC=cc;     CXX=c++ ;;
    zig)
        if [ ! -x /usr/local/bin/zig-cc ]; then
            fail "the zig toolchain is not installed in this image (see /opt/zig-version.txt); it is a control, so the cell is not silently rebuilt with gcc" unsupported 3
        fi
        CC=/usr/local/bin/zig-cc; CXX=/usr/local/bin/zig-c++ ;;
    *) fail "unknown TOOLCHAIN: $TOOLCHAIN" unsupported 3 ;;
esac
export CC CXX
NPROC=$(nproc 2>/dev/null || echo 2)
export NPROC

say "cc=$($CC --version 2>/dev/null | head -1)"

# --- 1. Allocator ----------------------------------------------------------
ALLOC_PREFIX=""
if [ "$ALLOCATOR" != "system" ]; then
    [ -n "$ALLOC_COMMIT" ] || fail "ALLOC_COMMIT is required for allocator $ALLOCATOR" build_failed 1

    case "$INTEGRATION" in
        rust-global)                 MODE=prefixed ;;
        libc-surgery|link-override)  MODE=override ;;
        preload)                     MODE=preload ;;
        *) fail "unknown INTEGRATION: $INTEGRATION" unsupported 3 ;;
    esac
    export MODE

    case "$PROFILE" in *pie*|dynamic) PIC=1 ;; *) PIC=0 ;; esac
    export PIC

    src="$CACHE/src/$ALLOCATOR-$ALLOC_COMMIT"
    say "fetching $ALLOCATOR at $ALLOC_COMMIT"
    sh "$ROOT/scripts/build/fetch-source.sh" "$ALLOC_REPO" "$ALLOC_COMMIT" "$src" >>"$LOG" 2>&1 \
        || fail "could not fetch $ALLOC_REPO at $ALLOC_COMMIT" build_failed 1

    # Cache key covers everything that changes the archive. Getting this wrong
    # would serve one cell's archive to another and silently mislabel a result.
    key="$ALLOCATOR-$ALLOC_COMMIT-$MODE-pic$PIC-$LIBC-$TARGET_ARCH-$TOOLCHAIN-$HM_VARIANT"
    ALLOC_PREFIX="$CACHE/alloc/$key"

    if [ -f "$ALLOC_PREFIX/.built" ]; then
        say "allocator cache hit: $key"
    else
        say "building $ALLOCATOR (mode=$MODE pic=$PIC toolchain=$TOOLCHAIN)"
        recipe="$ROOT/allocators/$ALLOCATOR/build.sh"
        [ -x "$recipe" ] || fail "no build recipe at $recipe" build_failed 1
        out=$(SRC="$src" OUT="$ALLOC_PREFIX" MODE="$MODE" PIC="$PIC" LIBC="$LIBC" \
              TARGET_ARCH="$TARGET_ARCH" NPROC="$NPROC" CC="$CC" CXX="$CXX" \
              HM_VARIANT="$HM_VARIANT" \
              sh "$recipe" 2>&1)
        rc=$?
        printf '%s\n' "$out" >> "$LOG"
        if [ $rc -eq 3 ]; then
            fail "$(printf '%s' "$out" | grep '^UNSUPPORTED:' | head -1 | sed 's/^UNSUPPORTED: //')" unsupported 3
        elif [ $rc -ne 0 ]; then
            fail "allocator build failed (rc=$rc): $(printf '%s' "$out" | tail -5 | tr '\n' ' ')" build_failed 1
        fi
        touch "$ALLOC_PREFIX/.built"
    fi
fi

# --- 2. libc surgery, when that is the mechanism ---------------------------
if [ "$INTEGRATION" = libc-surgery ]; then
    say "splicing $ALLOCATOR into every libc.a in the image"
    sh "$ROOT/scripts/build/libc-surgery.sh" "$ALLOC_PREFIX/lib/liballocbench.a" "$RUNNER" >>"$LOG" 2>&1 \
        || fail "libc surgery failed or could not be verified; see steps.log" build_failed 1
fi

rg_src="/work/ripgrep-$CELL_ID"
rm -rf "$rg_src"
say "fetching ripgrep at $RG_COMMIT"
sh "$ROOT/scripts/build/fetch-source.sh" "$RG_REPO" "$RG_COMMIT" "$rg_src" >>"$LOG" 2>&1 \
    || fail "could not fetch ripgrep at $RG_COMMIT" build_failed 1

case "$TARGET_ARCH" in
    x86_64)  rust_arch=x86_64 ;;
    aarch64) rust_arch=aarch64 ;;
    *) fail "unsupported architecture: $TARGET_ARCH" unsupported 3 ;;
esac
case "$LIBC" in musl) rust_libc=musl ;; *) rust_libc=gnu ;; esac
TARGET="$rust_arch-unknown-linux-$rust_libc"

say "building ripgrep ($TARGET, profile=$PROFILE, integration=$INTEGRATION)"
build_t0=$(date +%s)
RG_SRC="$rg_src" OUT="$OUTDIR" RUNNER="$RUNNER" ALLOCATOR="$ALLOCATOR" \
INTEGRATION="$INTEGRATION" PROFILE="$PROFILE" TARGET="$TARGET" \
ALLOC_PREFIX="$ALLOC_PREFIX" NPROC="$NPROC" \
    sh "$ROOT/scripts/build/build-ripgrep.sh" >>"$LOG" 2>&1
rc=$?
build_t1=$(date +%s)
echo "$((build_t1 - build_t0))" > "$OUTDIR/build_seconds"
if [ $rc -ne 0 ]; then
    fail "ripgrep build failed (rc=$rc); tail: $(tail -12 "$OUTDIR/build.log" 2>/dev/null | tr '\n' ' ')" build_failed 1
fi

# --- 4. Identity. Before anything is timed. --------------------------------
expect_alloc="$ALLOCATOR"
replacement=""
[ "$INTEGRATION" = libc-surgery ] || [ "$INTEGRATION" = link-override ] && replacement="--replacement"
# Under preload the BINARY is a plain system build; the allocator arrives at run
# time, so the binary must identify as the baseline and the .so is checked
# separately below.
if [ "$INTEGRATION" = preload ]; then
    expect_alloc=system
    replacement=""
fi
case "$PROFILE" in
    dynamic)   expect_kind=dynamic ;;
    *pie*)     expect_kind=static-pie ;;
    *)         expect_kind=static ;;
esac

say "identifying the binary (expect $expect_alloc, $expect_kind)"
"$RUNNER" identify --bin "$OUTDIR/rg" --expect-allocator "$expect_alloc" \
    --expect-kind "$expect_kind" $replacement > "$OUTDIR/identity.json" 2>>"$LOG"
if [ $? -ne 0 ]; then
    fail "the binary is not the configuration it claims: $(grep -o '\"reasons\":\[[^]]*\]' "$OUTDIR/identity.json" | head -c 500)" identity_failed 1
fi

if [ "$INTEGRATION" = preload ]; then
    so="$ALLOC_PREFIX/lib/liballocbench.so"
    [ -f "$so" ] || fail "preload needs $so and the allocator build produced none" unsupported 3
    echo "$so" > "$OUTDIR/preload_so"
    say "preload object: $so"
fi

# --- 5. Corpus -------------------------------------------------------------
# Shared across cells through the cache, so every cell searches BYTE-IDENTICAL
# input. Regenerating per cell would be equally deterministic but would put the
# files at different inode/extent layouts, which the filesystem can notice.
corpus="$CACHE/corpus-$CORPUS_PROFILE-$CORPUS_SEED"
if [ ! -f "$corpus/truth.kv" ]; then
    say "generating corpus ($CORPUS_PROFILE, seed $CORPUS_SEED)"
    "$RUNNER" gen-corpus --out "$corpus" --profile "$CORPUS_PROFILE" --seed "$CORPUS_SEED" \
        >> "$LOG" 2>&1 || fail "corpus generation failed" measurement_failed 1
fi
cp "$corpus/manifest.json" "$OUTDIR/corpus.json" 2>/dev/null || true

RUNENV=""
if [ "$INTEGRATION" = preload ]; then
    RUNENV="--env LD_PRELOAD=$(cat "$OUTDIR/preload_so")"

    say "checking the preloaded library is resident in the running process"
    "$RUNNER" preload-check --bin "$OUTDIR/rg" --so "$(cat "$OUTDIR/preload_so")" \
        --corpus "$corpus" --expect-allocator "$ALLOCATOR" --runs 4 \
        > "$OUTDIR/preload.json" 2>>"$LOG"
    rc=$?
    if [ $rc -ne 0 ]; then
        fail "the preloaded allocator was not observed in the process: $(grep -o '"reasons":\[[^]]*\]' "$OUTDIR/preload.json" | head -c 500)" identity_failed 1
    fi
fi

# --- 6. Correctness. Before anything is timed. -----------------------------
say "correctness gate"
# shellcheck disable=SC2086
if [ -n "$RUNENV" ]; then
    LD_PRELOAD="$(cat "$OUTDIR/preload_so")" "$RUNNER" verify --bin "$OUTDIR/rg" --corpus "$corpus" \
        > "$OUTDIR/correctness.json" 2>>"$LOG"
else
    "$RUNNER" verify --bin "$OUTDIR/rg" --corpus "$corpus" \
        > "$OUTDIR/correctness.json" 2>>"$LOG"
fi
if [ $? -ne 0 ]; then
    fail "correctness gate failed: $(grep -o '\"name\":\"[a-z]*\",\"ok\":false[^}]*' "$OUTDIR/correctness.json" | head -c 400)" correctness_failed 1
fi

say "observing load-address randomisation"
# shellcheck disable=SC2086
"$RUNNER" aslr-probe --bin "$OUTDIR/rg" --corpus "$corpus" --runs 6 \
    > "$OUTDIR/aslr.json" 2>>"$LOG" || true

# --- 8. Measure ------------------------------------------------------------
workloads=$("$RUNNER" workloads | tr ',' '\n' | grep -o '"name":"[a-z0-9-]*"' | cut -d'"' -f4)
[ -n "$workloads" ] || fail "the runner listed no workloads" measurement_failed 1

measured=0
for w in $workloads; do
    say "measuring $w (repeat=$REPEAT warmup=$WARMUP)"
    # shellcheck disable=SC2086
    "$RUNNER" measure --bin "$OUTDIR/rg" --corpus "$corpus" --workload "$w" \
        --repeat "$REPEAT" --warmup "$WARMUP" --timeout 600 $RUNENV \
        > "$OUTDIR/measure-$w.json" 2>>"$LOG"
    rc=$?
    if [ $rc -ne 0 ]; then
        say "workload $w FAILED (rc=$rc); its samples are kept and marked"
    else
        measured=$((measured + 1))
    fi
done

if [ "$measured" -eq 0 ]; then
    fail "no workload produced a usable measurement" measurement_failed 1
fi

echo ok > "$OUTDIR/status"
say "done: $measured/$(echo "$workloads" | wc -w) workloads measured"
exit 0
