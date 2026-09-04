#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$HERE/.." && pwd)
OUT="$HERE/out/50-libc-surgery-verify.txt"
mkdir -p "$HERE/out" || exit 2

RT=""
for c in docker podman; do
    if command -v "$c" >/dev/null 2>&1 && "$c" info >/dev/null 2>&1; then RT="$c"; break; fi
done
[ -n "$RT" ] || { echo "50: no working container runtime" >&2; exit 2; }

ARCH=$(uname -m)
IMAGE="alloc-bench/alpine-$ARCH:local"
"$RT" image inspect "$IMAGE" >/dev/null 2>&1 || {
    echo "50: image $IMAGE not present. Build it first:" >&2
    echo "    alloc-bench run --suite smoke --arch $ARCH" >&2
    exit 2
}

LOCK="$ROOT/allocators/allocators.lock.json"
COMMIT=$(python3 -c "
import json; print(json.load(open('$LOCK'))['entries']['mimalloc']['commit'], end='')
" 2>/dev/null) || { echo "50: could not read mimalloc's commit from the lock" >&2; exit 2; }

# The list the prior art deletes, verbatim, so drift against it is measurable.
PRIOR_ART_LIST="aligned_alloc.lo calloc.lo donate.lo free.lo libc_calloc.lo lite_malloc.lo malloc.lo malloc_usable_size.lo memalign.lo posix_memalign.lo realloc.lo reallocarray.lo valloc.lo"

rc=0
{
    echo "=== conditions ==="
    echo "date          $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host          $(uname -srm)"
    echo "runtime       $RT"
    echo "image         $IMAGE"
    echo "mimalloc      $COMMIT"
    echo
} > "$OUT" 2>&1

"$RT" run --rm \
    -e COMMIT="$COMMIT" -e PRIOR_ART_LIST="$PRIOR_ART_LIST" \
    ${ALLOC_BENCH_HTTPS_PROXY:+-e HTTPS_PROXY="$ALLOC_BENCH_HTTPS_PROXY"} \
    "$IMAGE" sh -c '
set -eu
R=/usr/local/bin/alloc-runner
LIBC=/usr/lib/libc.a

echo "=== BEFORE: who defines malloc in $LIBC? ==="
"$R" ar-members --archive "$LIBC" --symbols malloc,free,calloc,realloc || true
before=$("$R" ar-members --archive "$LIBC" --symbols malloc,free,calloc,realloc 2>/dev/null | wc -l)
echo "members defining an allocation symbol: $before"
echo

echo "=== how much of the prior art'"'"'s hard-coded delete list still exists? ==="
present=0; absent=0; missing_names=""
for m in $PRIOR_ART_LIST; do
    if ar t "$LIBC" 2>/dev/null | grep -qx "$m"; then
        present=$((present+1))
    else
        absent=$((absent+1)); missing_names="$missing_names $m"
    fi
done
echo "present in this musl: $present    absent:$absent"
[ -n "$missing_names" ] && echo "names that no longer exist:$missing_names"
echo

echo "=== build mimalloc in override mode ==="
sh /opt/alloc-bench/scripts/build/fetch-source.sh \
   https://github.com/microsoft/mimalloc "$COMMIT" /work/mimalloc >/dev/null
SRC=/work/mimalloc OUT=/opt/mi MODE=override PIC=1 LIBC=musl \
TARGET_ARCH=$(uname -m) CC=cc CXX=c++ NPROC=$(nproc) \
   sh /opt/alloc-bench/allocators/mimalloc/build.sh
echo

echo "=== the surgery ==="
sh /opt/alloc-bench/scripts/build/libc-surgery.sh /opt/mi/lib/liballocbench.a "$R"
echo

echo "=== AFTER: exactly one definition of each? ==="
fail=0
for sym in malloc free calloc realloc; do
    if "$R" archive-check --archive "$LIBC" --symbol "$sym" --expect-providers 1 >/dev/null 2>&1; then
        echo "  ok    $sym defined exactly once"
    else
        n=$("$R" ar-members --archive "$LIBC" --symbols "$sym" 2>/dev/null | wc -l)
        echo "  FAIL  $sym defined by $n member(s)"
        fail=1
    fi
done
echo

echo "=== and the definition comes from the allocator, not from musl ==="
"$R" ar-members --archive "$LIBC" --symbols malloc,free | sed "s/^/  provider: /"
if "$R" ar-members --archive "$LIBC" --symbols malloc | grep -qE "\.lo$"; then
    echo "  FAIL  a musl object (.lo) still provides malloc"
    fail=1
else
    echo "  ok    no musl .lo object provides malloc"
fi
exit $fail
' >> "$OUT" 2>&1 || rc=1

{
    echo
    echo "=== what this means ==="
    if [ "$rc" -eq 0 ]; then
        cat <<'TEXT'
The surgery displaced the libc allocator: after the splice exactly one archive
member defines each of malloc, free, calloc and realloc, and none of them is a
musl object.

 Note the drift line above. Where the prior art's hard-coded delete list names
objects that no longer exist in this musl, a build using that list would delete
fewer members than it intended -- and every name it fails to match leaves a
second definition behind. That is why scripts/build/libc-surgery.sh DERIVES the
list from the archive and then asserts the outcome.
TEXT
    else
        cat <<'TEXT'
 The archive is NOT in the expected state. Either the splice did not remove
every displaced member, or the allocator did not provide a replacement.

Do not benchmark this image: which allocator serves malloc is decided by link
order, so any number it produces is unattributable.
TEXT
    fi
    echo
    echo "=== what this probe cannot tell you ==="
    echo "- whether a BINARY built in the patched image really routes every"
    echo "  allocation through the new allocator. That is what"
    echo "  \`alloc-runner identify --replacement\` checks, on the linked ELF."
    echo "- anything about glibc. Statically replacing glibc's allocator is not"
    echo "  supported; see docs/allocator-integration.md."
} >> "$OUT" 2>&1

cat "$OUT"
exit "$rc"
