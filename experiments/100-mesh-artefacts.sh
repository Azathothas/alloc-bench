#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/experiments/out/100-mesh-artefacts.txt"
LOCK="$ROOT/allocators/allocators.lock.json"

mkdir -p "$ROOT/experiments/out"

for t in git cmake make nm python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "no $t on PATH" >&2; exit 2; }
done
CXX_BIN=$(command -v c++ || command -v g++ || true)
[ -n "$CXX_BIN" ] || { echo "no C++ compiler on PATH" >&2; exit 2; }

COMMIT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["entries"]["mesh"]["commit"])' "$LOCK" 2>/dev/null)
REPO=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["entries"]["mesh"]["repo"])' "$LOCK" 2>/dev/null)
[ -n "$COMMIT" ] || { echo "could not read mesh's pinned commit from $LOCK" >&2; exit 2; }

W="${TMPDIR:-/tmp}/alloc-bench-100-mesh.$$"
trap 'rm -rf "$W"' EXIT INT TERM

rc=0
fail() { rc=1; echo " $1"; }

{
    echo "=== conditions ==="
    echo "date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:    $(uname -srm)"
    echo "cmake:   $(cmake --version | head -1)"
    echo "c++:     $($CXX_BIN --version | head -1)"
    echo "mesh:    $REPO @ $COMMIT"
    echo "scratch: $W"
    echo

    mkdir -p "$W" || exit 2
    SRC="$W/src"
    B="$W/build"

    echo "=== fetch the pinned commit ==="
    if ! git init -q "$SRC" \
        || ! git -C "$SRC" remote add origin "$REPO" \
        || ! git -C "$SRC" fetch -q --depth 1 origin "$COMMIT" \
        || ! git -C "$SRC" checkout -q FETCH_HEAD; then
        echo "could not fetch $REPO @ $COMMIT -- no network, or the commit is gone" >&2
        exit 2
    fi
    echo "HEAD: $(git -C "$SRC" rev-parse HEAD)"
    echo

    echo "=== what the CMakeLists actually says ==="
    grep -n 'CMAKE_OUTPUT_DIRECTORY\|CMAKE_LIBRARY_OUTPUT_DIRECTORY' "$SRC/CMakeLists.txt" | head -4
    grep -n 'add_library' "$SRC/src/CMakeLists.txt" | head -2
    echo

    echo "=== configure and build, exactly as allocators/mesh/build.sh does ==="
    echo "cmake -S \$SRC -B \$B -DCMAKE_BUILD_TYPE=Release"
    if ! cmake -S "$SRC" -B "$B" -DCMAKE_BUILD_TYPE=Release >"$W/cmake.log" 2>&1; then
        echo "configure FAILED; last 10 lines:"
        tail -10 "$W/cmake.log"
        exit 2
    fi
    echo "configure: ok"

    if cmake --build "$B" --target mesh >"$W/build.log" 2>&1; then
        echo "build:     ok (--target mesh)"
    elif cmake --build "$B" >>"$W/build.log" 2>&1; then
        echo "build:     ok (all; --target mesh alone did not build)"
    else
        echo "build FAILED; last 15 lines:"
        tail -15 "$W/build.log"
        exit 2
    fi
    echo

    echo "=== 1. the recipe's search: shared objects under -B ==="
    echo "    find \$B -type f -name '*.so*'"
    in_b=$(find "$B" -type f -name '*.so*' 2>/dev/null | wc -l)
    find "$B" -type f -name '*.so*' 2>/dev/null | sed "s|$B|<BUILD>|" | head -10
    echo "    count: $in_b"
    [ "$in_b" -eq 0 ] || fail "1: expected ZERO shared objects under -B, found $in_b (mesh may have changed)"
    echo

    echo "=== 1b. and the objects of the mesh target ARE there ==="
    objs=$(find "$B" -type f -name '*.cc.o' -path '*mesh.dir*' 2>/dev/null | wc -l)
    echo "    \$B/**/mesh.dir/*.cc.o: $objs"
    [ "$objs" -gt 0 ] || fail "1b: no mesh.dir objects under -B; the build did not do what the refusal described"
    echo

    echo "=== 2. where CMake was told to put it: \$SRC/build ==="
    echo "    find \$SRC/build -type f -name '*.so*'"
    found=$(find "$SRC/build" -type f -name '*.so*' 2>/dev/null | head -1)
    find "$SRC/build" -type f -name '*.so*' 2>/dev/null | sed "s|$SRC|<SRC>|" | head -10
    if [ -z "$found" ]; then
        fail "2: no shared object under \$SRC/build either -- the diagnosis is WRONG"
        echo "    what is under \$SRC/build, if anything:"
        find "$SRC/build" -type f 2>/dev/null | sed "s|$SRC|<SRC>|" | head -20
    else
        echo "    size: $(wc -c < "$found") bytes"
        echo "    file: $(command -v file >/dev/null 2>&1 && file -b "$found" || echo '(file(1) absent)')"
    fi
    echo

    echo "=== 3. does it EXPORT malloc? (allocators/lib.sh finish_so's rule) ==="
    if [ -z "$found" ]; then
        echo "    skipped: nothing to read"
    else
        if nm -D --defined-only "$found" 2>/dev/null | grep -qE '[[:space:]][TWi][[:space:]]+malloc$'; then
            echo "    nm -D: malloc EXPORTED "
        else
            fail "3: $found does not export malloc; LD_PRELOAD would interpose nothing"
            echo "    --- dynamic symbols it does export (first 20) ---"
            nm -D --defined-only "$found" 2>/dev/null | head -20
        fi
        echo "    other allocator entry points it exports:"
        for s in free realloc calloc posix_memalign aligned_alloc; do
            if nm -D --defined-only "$found" 2>/dev/null | grep -qE "[[:space:]][TWi][[:space:]]+$s\$"; then
                printf '      %-16s yes\n' "$s"
            else
                printf '      %-16s NO\n' "$s"
            fi
        done
    fi
    echo

    echo "=== what this establishes ==="
    echo " mesh builds a shared library and always did. The refusal was the"
    echo "   recipe searching the CMake BINARY directory for an artefact mesh's"
    echo "   own CMakeLists redirects into the SOURCE directory."
    echo " It is the third refusal in this project that turned out to be the"
    echo "   instrument rather than the allocator -- after tcmalloc's \`find\`"
    echo "   not following the bazel-bin symlink, and its TLS failure being"
    echo "   reported as \"bazel build failed\". A refusal is a measurement and"
    echo "   has to be able to fail for the right reason."
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether a mesh cell now measures. The ripgrep build, the identity"
    echo "  gate, preload-check's residency read and the correctness gate all"
    echo "  sit downstream. Only a run of the \`preload\` suite answers that."
    echo "- whether writing into the source tree is safe for a CACHED source"
    echo "  directory. allocators/mesh/build.sh now cleans \$SRC/build before"
    echo "  configuring for exactly that reason; this probe uses a fresh clone."
} > "$OUT" 2>&1

cat "$OUT"
exit "$rc"
