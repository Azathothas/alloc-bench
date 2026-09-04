#!/bin/sh
. "$(dirname "$0")/../lib.sh"

prepare_out
B="$OUT/.build"

prefix="sn_"
[ "$MODE" = override ] && prefix=""

pic=ON
[ "$PIC" = 1 ] || pic=OFF

set -- \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$(fortify_cflags)" \
    -DCMAKE_CXX_FLAGS="$(fortify_cflags)" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DSNMALLOC_BUILD_TESTING=OFF \
    -DSNMALLOC_STATIC_LIBRARY=ON \
    -DSNMALLOC_STATIC_LIBRARY_PREFIX="$prefix" \
    -DCMAKE_POSITION_INDEPENDENT_CODE="$pic" \
    -DSNMALLOC_IPO=OFF

if [ "$MODE" = preload ]; then
    set -- \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$(fortify_cflags)" \
        -DCMAKE_CXX_FLAGS="$(fortify_cflags)" \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DSNMALLOC_BUILD_TESTING=OFF \
        -DSNMALLOC_STATIC_LIBRARY=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DSNMALLOC_IPO=OFF
fi

if [ "$LIBC" = musl ]; then
    set -- "$@" -DSNMALLOC_CLEANUP=CXX11_DESTRUCTORS
fi

cmake -S "$SRC" -B "$B" "$@" >/dev/null 2>"$OUT/cmake.log" || {
    # snmalloc requires a C++20 compiler by default. Where the image's compiler
    # is older, that is a real limitation of that image and is reported as one
    # rather than papered over.
    if grep -qiE 'c\+\+2|CMAKE_CXX_STANDARD|std=c\+\+' "$OUT/cmake.log" 2>/dev/null; then
        unsupported "snmalloc's CMake refused this toolchain (C++20 required). $(tail -3 "$OUT/cmake.log" | tr '\n' ' ')"
    fi
    cat "$OUT/cmake.log" >&2
    exit 1
}

if [ "$MODE" = preload ]; then
    cmake --build "$B" --parallel "$NPROC" --target snmallocshim >/dev/null
    so=$(find "$B" -type f -name 'libsnmallocshim*.so*' | sort | pick_elf_so) || so=''
    [ -n "$so" ] || { echo "no libsnmallocshim*.so under $B" >&2; exit 1; }
    cp "$so" "$SHARED"
    write_meta "" "cmake Release SNMALLOC_STATIC_LIBRARY=OFF target=snmallocshim (upstream's own LD_PRELOAD shim) CLEANUP=$([ "$LIBC" = musl ] && echo CXX11_DESTRUCTORS || echo default)"
    finish_so malloc free realloc calloc
    exit 0
fi

cmake --build "$B" --parallel "$NPROC" --target snmallocshim-static >/dev/null

lib=$(find "$B" \( -name 'libsnmallocshim-static.a' -o -name 'libsnmallocshim*.a' \) | sort | pick_ar) || lib=''
[ -n "$lib" ] || { echo "no libsnmallocshim*.a under $B" >&2; exit 1; }
cp "$lib" "$ARCHIVE"

if "$AR" t "$ARCHIVE" 2>/dev/null | grep -q '^new\.cc\.o$'; then
    "$AR" d "$ARCHIVE" new.cc.o
    echo "snmalloc: removed new.cc.o (C++ operator new/delete) to avoid colliding with the C++ runtime"
fi

# Which C++ runtime depends on the compiler driver, so it is detected rather
# than guessed: a wrong guess shows up as an undefined _ZdlPv at the very end
# of the ripgrep link, which is an unhelpful place to learn it.
cxxlib="static=stdc++"
if "$CXX" --version 2>/dev/null | grep -qi clang && ! command -v g++ >/dev/null 2>&1; then
    cxxlib="static=c++,static=c++abi"
fi
cxxpath=$("$CXX" -print-file-name=libstdc++.a 2>/dev/null || true)
if [ -n "$cxxpath" ] && [ -f "$cxxpath" ]; then
    ALLOC_LINK_SEARCH=$(dirname "$cxxpath")
else
    ALLOC_LINK_SEARCH=""
    echo "snmalloc: warning: could not locate libstdc++.a; the link may fail" >&2
fi
export ALLOC_LINK_SEARCH

write_meta "$cxxlib" "cmake Release PREFIX='$prefix' PIC=$pic CLEANUP=$([ "$LIBC" = musl ] && echo CXX11_DESTRUCTORS || echo default)"

if [ "$MODE" = override ]; then
    finish malloc free realloc calloc
else
    finish sn_malloc sn_free sn_realloc sn_calloc sn_aligned_alloc
fi
