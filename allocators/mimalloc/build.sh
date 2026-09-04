#!/bin/sh
. "$(dirname "$0")/../lib.sh"

prepare_out
B="$OUT/.build"

override=OFF
if [ "$MODE" = override ] || [ "$MODE" = preload ]; then override=ON; fi

shared=OFF
static=ON
if [ "$MODE" = preload ]; then shared=ON; static=OFF; fi

musl=OFF
[ "$LIBC" = musl ] && musl=ON

pic=ON
[ "$PIC" = 1 ] || pic=OFF

cmake -S "$SRC" -B "$B" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$(fortify_cflags)" \
    -DCMAKE_CXX_FLAGS="$(fortify_cflags)" \
    -DCMAKE_C_COMPILER="$CC" \
    -DMI_BUILD_SHARED="$shared" \
    -DMI_BUILD_STATIC="$static" \
    -DMI_BUILD_OBJECT=OFF \
    -DMI_BUILD_TESTS=OFF \
    -DMI_OVERRIDE="$override" \
    -DMI_LIBC_MUSL="$musl" \
    -DCMAKE_POSITION_INDEPENDENT_CODE="$pic" \
    >/dev/null

cmake --build "$B" --parallel "$NPROC" >/dev/null

cp -r "$SRC/include/." "$OUT/include/" 2>/dev/null || true

if [ "$MODE" = preload ]; then
    lib=$(find "$B" -type f -name 'libmimalloc*.so*' | sort | pick_elf_so) || lib=''
    [ -n "$lib" ] || { echo "no libmimalloc*.so under $B" >&2; exit 1; }
    cp "$lib" "$SHARED"
    write_meta "" "cmake Release MI_BUILD_SHARED=ON MI_OVERRIDE=$override MI_LIBC_MUSL=$musl PIC=$pic"
    finish_so malloc free realloc calloc
    exit 0
fi

lib=$(find "$B" -name 'libmimalloc*.a' | sort | pick_ar) || lib=''
[ -n "$lib" ] || { echo "no libmimalloc*.a under $B" >&2; exit 1; }
cp "$lib" "$ARCHIVE"

write_meta "" "cmake Release MI_OVERRIDE=$override MI_LIBC_MUSL=$musl PIC=$pic"

if [ "$MODE" = override ]; then
    finish malloc free realloc calloc
else
    finish mi_malloc mi_free mi_realloc mi_malloc_aligned mi_zalloc_aligned mi_realloc_aligned
fi
