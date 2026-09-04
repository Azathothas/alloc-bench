#!/bin/sh
. "$(dirname "$0")/../lib.sh"

prepare_out

B="$OUT/.build"
mkdir -p "$B"

[ -f "$SRC/rpmalloc/rpmalloc.c" ] || unsupported "rpmalloc/rpmalloc.c not found at this revision; the source layout changed"
# rpmalloc.c #includes it; it is a dependency even though it is never named on a
# compiler command line.
[ -f "$SRC/rpmalloc/malloc.c" ] || unsupported "rpmalloc/malloc.c (the override layer rpmalloc.c includes) not found at this revision"

pic_flag=$(pic_cflags)
CFLAGS="-O3 $pic_flag $(fortify_cflags) -std=c11 -D_GNU_SOURCE -I$SRC/rpmalloc -fno-builtin-malloc -fno-builtin-free"

if [ "$MODE" = preload ]; then
    [ "$PIC" = 1 ] || unsupported "a preload object must be position-independent and this cell asked for PIC=0"
    "$CC" $CFLAGS -DENABLE_OVERRIDE=1 -DENABLE_PRELOAD=1 -shared \
        -o "$SHARED" "$SRC/rpmalloc/rpmalloc.c" \
        || { echo "rpmalloc: shared link failed" >&2; exit 1; }
    cp "$SRC/rpmalloc/rpmalloc.h" "$OUT/include/" 2>/dev/null || true
    write_meta "" "direct $CC $CFLAGS -DENABLE_OVERRIDE=1 -DENABLE_PRELOAD=1 -shared"
    finish_so malloc free realloc calloc
    exit 0
fi

if [ "$MODE" = override ]; then
    ov=1
else
    ov=0
fi
"$CC" $CFLAGS -DENABLE_OVERRIDE=$ov -DENABLE_PRELOAD=0 -c "$SRC/rpmalloc/rpmalloc.c" -o "$B/rpmalloc.o"
set -- "$B/rpmalloc.o"

"$AR" rcs "$ARCHIVE" "$@"

if [ "$MODE" = prefixed ] && "$NM" --defined-only "$ARCHIVE" 2>/dev/null | grep -qE '[[:space:]]T[[:space:]]+malloc$'; then
    command -v objcopy >/dev/null 2>&1 || \
        unsupported "rpmalloc defines malloc unconditionally at this revision and objcopy is unavailable to localise it"
    tmp="$B/localise"; mkdir -p "$tmp"
    ( cd "$tmp" && "$AR" x "$ARCHIVE" )
    for o in "$tmp"/*.o; do
        objcopy \
            --localize-symbol=malloc --localize-symbol=free \
            --localize-symbol=calloc --localize-symbol=realloc \
            --localize-symbol=aligned_alloc --localize-symbol=posix_memalign \
            --localize-symbol=memalign --localize-symbol=valloc \
            --localize-symbol=pvalloc --localize-symbol=cfree \
            --localize-symbol=malloc_usable_size --localize-symbol=reallocarray \
            "$o" 2>/dev/null || true
    done
    rm -f "$ARCHIVE"
    "$AR" rcs "$ARCHIVE" "$tmp"/*.o
fi
cp "$SRC/rpmalloc/rpmalloc.h" "$OUT/include/" 2>/dev/null || true

write_meta "" "direct $CC $CFLAGS -DENABLE_OVERRIDE=$ov -DENABLE_PRELOAD=0"

if [ "$MODE" = override ]; then
    finish malloc free realloc calloc
else
    finish rpmalloc rpfree rpaligned_alloc rpaligned_realloc rpaligned_calloc rpmalloc_initialize rpmalloc_thread_initialize
fi
