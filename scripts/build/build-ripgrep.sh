#!/bin/sh
set -eu

: "${RG_SRC:?RG_SRC is required}"
: "${OUT:?OUT is required}"
: "${RUNNER:?RUNNER is required}"
: "${ALLOCATOR:=system}"
: "${INTEGRATION:=baseline}"
: "${PROFILE:=static-pie}"
: "${TARGET:?TARGET is required (a rust target triple)}"
: "${SHIM_PATH:=/opt/alloc-bench/crates/rgalloc-shim}"
: "${ALLOC_PREFIX:=}"
: "${NPROC:=$(nproc 2>/dev/null || echo 2)}"

[ -f "$RG_SRC/crates/core/main.rs" ] || { echo "build-rg: $RG_SRC is not a ripgrep checkout" >&2; exit 2; }
[ -x "$RUNNER" ] || { echo "build-rg: runner not executable: $RUNNER" >&2; exit 2; }

mkdir -p "$OUT"

# --- 1. Source preparation -------------------------------------------------
case "$INTEGRATION" in
    rust-global)
        [ -n "$ALLOC_PREFIX" ] || { echo "build-rg: rust-global needs ALLOC_PREFIX" >&2; exit 2; }
        "$RUNNER" patch-rg --src "$RG_SRC" --shim-path "$SHIM_PATH" --shim-feature "$ALLOCATOR" \
            > "$OUT/patch.json" || { echo "build-rg: patch-rg failed" >&2; exit 1; }
        ;;
    baseline|libc-surgery|link-override|preload)
        # No shim: these mechanisms act below the application, or not at all.
        "$RUNNER" patch-rg --src "$RG_SRC" > "$OUT/patch.json" \
            || { echo "build-rg: patch-rg failed" >&2; exit 1; }
        ;;
    *)
        echo "build-rg: unknown INTEGRATION: $INTEGRATION" >&2; exit 2 ;;
esac

# --- 2. Link configuration -------------------------------------------------
RUSTFLAGS=""
case "$PROFILE" in
    static)         RUSTFLAGS="-C target-feature=+crt-static -C relocation-model=static" ;;
    static-lto)     RUSTFLAGS="-C target-feature=+crt-static -C relocation-model=static" ;;
    static-pie)     RUSTFLAGS="-C target-feature=+crt-static -C relocation-model=pic" ;;
    static-pie-lto) RUSTFLAGS="-C target-feature=+crt-static -C relocation-model=pic" ;;
    dynamic)        RUSTFLAGS="-C target-feature=-crt-static" ;;
    *) echo "build-rg: unknown PROFILE: $PROFILE" >&2; exit 2 ;;
esac

case "$PROFILE" in
    static*) RUSTFLAGS="$RUSTFLAGS -C link-arg=-Wl,-z,stack-size=8388608" ;;
esac

case "$INTEGRATION" in
    rust-global)
        ALLOC_LIB_DIR="$ALLOC_PREFIX/lib"
        ALLOC_LIB_NAME="allocbench"
        export ALLOC_LIB_DIR ALLOC_LIB_NAME
        [ -f "$ALLOC_PREFIX/meta.env" ] && . "$ALLOC_PREFIX/meta.env"
        [ -n "${ALLOC_LINK_CXX:-}" ] && export ALLOC_LINK_CXX
        [ -n "${ALLOC_LINK_SEARCH:-}" ] && export ALLOC_LINK_SEARCH
        ;;
    link-override)
        [ -n "$ALLOC_PREFIX" ] || { echo "build-rg: link-override needs ALLOC_PREFIX" >&2; exit 2; }
        RUSTFLAGS="$RUSTFLAGS -L native=$ALLOC_PREFIX/lib -C link-arg=-Wl,--whole-archive -C link-arg=$ALLOC_PREFIX/lib/liballocbench.a -C link-arg=-Wl,--no-whole-archive"
        if [ -f "$ALLOC_PREFIX/meta.env" ]; then
            . "$ALLOC_PREFIX/meta.env"
            for d in $(echo "${ALLOC_LINK_SEARCH:-}" | tr ':' ' '); do
                [ -n "$d" ] && RUSTFLAGS="$RUSTFLAGS -L native=$d"
            done
            for l in $(echo "${ALLOC_LINK_CXX:-}" | tr ',' ' '); do
                case "$l" in
                    static=*) RUSTFLAGS="$RUSTFLAGS -C link-arg=-l${l#static=}" ;;
                    "") ;;
                    *) RUSTFLAGS="$RUSTFLAGS -C link-arg=-l$l" ;;
                esac
            done
        fi
        ;;
esac

# --- 3. Cargo profile, identical in every cell but the one variable ---------
LTO=false
case "$PROFILE" in *-lto) LTO=fat ;; esac

export CARGO_PROFILE_RELEASE_LTO="$LTO"
export CARGO_PROFILE_RELEASE_OPT_LEVEL=3
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
export CARGO_PROFILE_RELEASE_PANIC=abort
export CARGO_PROFILE_RELEASE_INCREMENTAL=false
export CARGO_PROFILE_RELEASE_DEBUG=0
export CARGO_PROFILE_RELEASE_STRIP=none

export RUSTFLAGS
export CARGO_TERM_COLOR=never
export CARGO_NET_RETRY=5

cd "$RG_SRC"
build_log="$OUT/build.log"
set +e
cargo build --release --target "$TARGET" --jobs "$NPROC" > "$build_log" 2>&1
rc=$?
set -e
if [ $rc -ne 0 ]; then
    echo "build-rg: cargo build failed (rc=$rc); tail of $build_log:" >&2
    tail -30 "$build_log" >&2
    exit 1
fi

bin="$RG_SRC/target/$TARGET/release/rg"
[ -f "$bin" ] || { echo "build-rg: cargo reported success but $bin does not exist" >&2; exit 1; }
cp "$bin" "$OUT/rg"

if [ "$ALLOCATOR" = "system" ]; then
    alloc_cc="(none: this cell builds no allocator)"
else
    alloc_cc="$(${CC:-cc} --version 2>/dev/null | head -1 | tr -d '\n')"
fi
{
    echo "{"
    printf '  "allocator": "%s",\n' "$ALLOCATOR"
    printf '  "integration": "%s",\n' "$INTEGRATION"
    printf '  "profile": "%s",\n' "$PROFILE"
    printf '  "target": "%s",\n' "$TARGET"
    printf '  "rustflags": "%s",\n' "$(echo "$RUSTFLAGS" | sed 's/"/\\"/g')"
    printf '  "cargo_lto": "%s",\n' "$LTO"
    printf '  "rustc": "%s",\n' "$(rustc --version 2>/dev/null | tr -d '\n')"
    printf '  "cargo": "%s",\n' "$(cargo --version 2>/dev/null | tr -d '\n')"
    printf '  "cc": "%s",\n' "$(cc --version 2>/dev/null | head -1 | tr -d '\n')"
    printf '  "alloc_cc": "%s",\n' "$alloc_cc"
    printf '  "toolchain": "%s",\n' "${TOOLCHAIN:-unrecorded}"
    printf '  "linker": "%s",\n' "$( (ld --version 2>/dev/null || ld.lld --version 2>/dev/null) | head -1 | tr -d '\n')"
    printf '  "binary_bytes": %s,\n' "$(wc -c < "$OUT/rg")"
    printf '  "cargo_lock_sha256": "%s"\n' "$(sha256sum Cargo.lock 2>/dev/null | cut -d' ' -f1)"
    echo "}"
} > "$OUT/build.json"

if [ -n "$ALLOC_PREFIX" ]; then
    [ -f "$ALLOC_PREFIX/meta.env" ]        && cp "$ALLOC_PREFIX/meta.env"        "$OUT/alloc-meta.env"
    [ -f "$ALLOC_PREFIX/build-flags.txt" ] && cp "$ALLOC_PREFIX/build-flags.txt" "$OUT/alloc-build-flags.txt"
fi

# The build metadata must be readable by the orchestrator, so it is parsed here
# rather than discovered to be malformed after the run. A build that cannot
# describe itself is not a usable result.
if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; json.load(open('$OUT/build.json'))" 2>/dev/null \
        || { echo "build-rg: build.json is not valid JSON" >&2; cat "$OUT/build.json" >&2; exit 1; }
fi

echo "build-rg: $OUT/rg ($(wc -c < "$OUT/rg") bytes) allocator=$ALLOCATOR integration=$INTEGRATION profile=$PROFILE"
