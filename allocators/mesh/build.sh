#!/bin/sh
. "$(dirname "$0")/../lib.sh"

prepare_out
B="$OUT/.build"

case "$MODE" in
    prefixed)
        unsupported "Mesh exports no prefixed C allocation API at this revision, so a #[global_allocator] shim has no symbol to bind to. Checked: no mesh_malloc / mz_malloc in include/."
        ;;
esac

MESH_OUT="$SRC/build"
rm -rf "$MESH_OUT"

# A static archive is what this recipe would need for link-override or
# libc-surgery, so its absence is checked here rather than inferred from the
# documentation.
cmake -S "$SRC" -B "$B" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$(fortify_cflags)" -DCMAKE_CXX_FLAGS="$(fortify_cflags)" \
    >"$OUT/cmake.log" 2>&1 || {
    unsupported "Mesh's CMake configure failed in this image: $(tail -3 "$OUT/cmake.log" | tr '\n' ' ')"
}

cmake --build "$B" >"$OUT/build.log" 2>&1 || {
    unsupported "Mesh failed to build in this image: $(tail -5 "$OUT/build.log" | tr '\n' ' ')"
}

so=$(
    find "$MESH_OUT" "$B" -type f \( -name '*.so' -o -name '*.so.*' \) 2>/dev/null \
        | sort | pick_elf_so
) || so=''
a=$(find "$MESH_OUT" "$B" -type f -name 'libmesh*.a' 2>/dev/null | sort | pick_ar) || a=''

if [ -n "$a" ]; then
    cp "$a" "$ARCHIVE"
    write_meta "static=stdc++" "cmake Release (static archive found at this revision)"
    finish malloc free realloc calloc
    exit 0
fi

if [ -n "$so" ]; then
    cp "$so" "$SHARED"
    write_meta "" "cmake Release, shared object only (upstream builds no static target); took $so"
    finish_so malloc free realloc calloc
    exit 0
fi

for d in "$MESH_OUT" "$B"; do
    echo "--- what the build left under $d (top 20 by size) ---" >&2
    if [ -d "$d" ]; then
        find "$d" -type f \( -name '*.so*' -o -name '*.a' -o -name '*.o' -o -perm -u+x \) \
            -printf '%10s %p\n' 2>/dev/null | sort -rn | head -20 >&2
    else
        echo "(does not exist)" >&2
    fi
done
unsupported "Mesh's build produced neither a static archive nor a shared object under $MESH_OUT or $B; the artefacts it did leave in both are listed on stderr"
