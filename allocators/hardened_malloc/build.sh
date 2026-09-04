#!/bin/sh
. "$(dirname "$0")/../lib.sh"

prepare_out

B="$OUT/.build"
mkdir -p "$B"

VARIANT="${HM_VARIANT:-default}"
[ -f "$SRC/config/$VARIANT.mk" ] || unsupported "hardened_malloc has no config/$VARIANT.mk at this revision"
[ -f "$SRC/h_malloc.c" ] || unsupported "h_malloc.c not found; the source layout changed"

pic_flag=$(pic_cflags)

# Upstream's SHARED_FLAGS with -flto and -march=native left out, and visibility
# opened. -fcf-protection and -fstack-clash-protection are not accepted by every
# compiler/architecture pair, so each is probed rather than assumed: on aarch64
# GCC, -fcf-protection is rejected outright.
SF="-pipe -O3 $pic_flag $(fortify_cflags) -fvisibility=default -fno-plt -Wall -Wextra"
PREFIX_DEF=""
if [ "$MODE" = prefixed ]; then
    # An `[ ... ] && x=y` one-liner would return 1 in override mode and abort
    # the whole recipe, because lib.sh sets -e.
    PREFIX_DEF="-DH_MALLOC_PREFIX"
    SF="$SF $PREFIX_DEF"
fi
for f in -fstack-clash-protection -fcf-protection -fstack-protector-strong; do
    if echo 'int main(void){return 0;}' | "$CC" $f -x c - -o /dev/null 2>/dev/null; then
        SF="$SF $f"
    fi
done

objs=""
cd "$SRC" || { echo "hardened_malloc: cannot enter source dir $SRC" >&2; exit 1; }
for s in chacha.c h_malloc.c memory.c pages.c random.c util.c; do
    [ -f "$s" ] || continue
    o="$B/$(basename "$s" .c).o"
    make -s OUT="$B" \
        TARGET_ARCH= \
        VARIANT="$VARIANT" \
        CONFIG_NATIVE=false \
        CONFIG_CXX_ALLOCATOR=false \
        CONFIG_WERROR=false \
        SHARED_FLAGS="$SF" \
        CC="$CC" \
        "$o" || { echo "hardened_malloc: make failed for $s" >&2; exit 1; }
    objs="$objs $o"
done
[ -n "$objs" ] || { echo "hardened_malloc: no objects built" >&2; exit 1; }

cp -r "$SRC/include/." "$OUT/include/" 2>/dev/null || true

if [ "$MODE" = preload ]; then
    [ "$PIC" = 1 ] || unsupported "a preload object must be position-independent and this cell asked for PIC=0"
    if [ "$VARIANT" = default ]; then hm_suffix=""; else hm_suffix="-$VARIANT"; fi
    hm_so="$B/libhardened_malloc$hm_suffix.so"
    make -s OUT="$B" \
        TARGET_ARCH= \
        VARIANT="$VARIANT" \
        CONFIG_NATIVE=false \
        CONFIG_CXX_ALLOCATOR=false \
        CONFIG_WERROR=false \
        SHARED_FLAGS="$SF" \
        CC="$CC" \
        "$hm_so" || { echo "hardened_malloc: make failed for $hm_so" >&2; exit 1; }
    cp "$hm_so" "$SHARED"
    write_meta "" "make VARIANT=$VARIANT CONFIG_NATIVE=false CONFIG_CXX_ALLOCATOR=false SHARED_FLAGS='$SF' -shared (upstream's own link rule); took $hm_so"
    finish_so malloc free realloc calloc
    exit 0
fi

"$AR" rcs "$ARCHIVE" $objs

write_meta "" "make VARIANT=$VARIANT CONFIG_NATIVE=false CONFIG_CXX_ALLOCATOR=false CPPFLAGS='$PREFIX_DEF' SHARED_FLAGS='$SF'"

if [ "$MODE" = prefixed ]; then
    finish h_malloc h_free h_realloc h_calloc h_aligned_alloc
else
    finish malloc free realloc calloc
fi
