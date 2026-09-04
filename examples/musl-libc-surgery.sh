#!/bin/sh
set -eu

REPL=${1:?usage: musl-libc-surgery.sh <replacement.a> [libc.a]}
LIBC=${2:-/usr/lib/libc.a}

[ -f "$REPL" ] || { echo "surgery: no replacement archive at $REPL" >&2; exit 2; }
[ -f "$LIBC" ] || { echo "surgery: no libc.a at $LIBC" >&2; exit 2; }
command -v ar >/dev/null 2>&1 || { echo "surgery: no ar" >&2; exit 2; }
command -v nm >/dev/null 2>&1 || { echo "surgery: no nm" >&2; exit 2; }

# The entry points a replacement is expected to provide, and therefore the ones
# musl must stop providing.
ALLOC_SYMS='malloc free calloc realloc aligned_alloc posix_memalign malloc_usable_size'

UNRELATED='fork pthread_create printf open close memcpy read write execve mmap'

echo "=== the archive, before ==="
echo "libc.a:      $LIBC ($(wc -c < "$LIBC") bytes, $(ar t "$LIBC" | wc -l) members)"
echo "replacement: $REPL ($(wc -c < "$REPL") bytes, $(ar t "$REPL" | wc -l) members)"
echo

members=$(nm --defined-only "$LIBC" 2>/dev/null | awk -v syms="$ALLOC_SYMS" '
    /^[^ \t].*:$/ {
        m = substr($0, 1, length($0) - 1)
        if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2)
        next
    }
    NF >= 3 {
        n = split(syms, want, " ")
        for (i = 1; i <= n; i++)
            if ($3 == want[i] && $2 ~ /^[TtWwDdBb]$/) { print m; next }
    }
' | sort -u)

if [ -z "$members" ]; then
    echo "surgery: no member of $LIBC defines any of: $ALLOC_SYMS" >&2
    echo "surgery: this libc.a does not look like musl's, or the symbols moved" >&2
    exit 1
fi

echo "=== members that define an allocation entry point ==="
printf '%s\n' "$members" | sed 's/^/  /'
echo "  ($(printf '%s\n' "$members" | wc -l) members)"
echo

# --- 2. refuse any member that also defines something unrelated ------------
for m in $members; do
    hit=$(nm --defined-only "$LIBC" 2>/dev/null | awk -v m="$m" -v un="$UNRELATED" '
        /^[^ \t].*:$/ {
            cur = substr($0, 1, length($0) - 1)
            if (match(cur, /\(.*\)$/)) cur = substr(cur, RSTART + 1, RLENGTH - 2)
            next
        }
        cur == m && NF >= 3 {
            n = split(un, bad, " ")
            for (i = 1; i <= n; i++) if ($3 == bad[i]) print $3
        }
    ' | sort -u | tr '\n' ' ')
    if [ -n "$hit" ]; then
        echo "surgery: REFUSING to delete $m -- it also defines: $hit" >&2
        echo "surgery: deleting it would remove functionality unrelated to allocation." >&2
        exit 1
    fi
done
echo "guard: no candidate member defines any of: $UNRELATED  "
echo

W=${TMPDIR:-/tmp}/surgery-syms.$$
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

nm --defined-only "$REPL" 2>/dev/null | awk '
    NF >= 3 && $2 ~ /^[TtWwDdBbVvRr]$/ { print $3 }' | sort -u > "$W/repl-defines"

printf '%s\n' "$members" | while IFS= read -r m; do
    [ -n "$m" ] || continue
    nm --defined-only "$LIBC" 2>/dev/null | awk -v m="$m" '
        /^[^ \t].*:$/ { cur = substr($0, 1, length($0) - 1)
                        if (match(cur, /\(.*\)$/)) cur = substr(cur, RSTART + 1, RLENGTH - 2); next }
        cur == m && NF >= 3 && $2 ~ /^[TtWwDdBbVvRr]$/ { print $3 }'
done | sort -u > "$W/deleted-defines"

nm "$LIBC" 2>/dev/null | awk -v del="$(printf '%s' "$members" | tr '\n' ' ')" '
    /^[^ \t].*:$/ { cur = substr($0, 1, length($0) - 1)
                    if (match(cur, /\(.*\)$/)) cur = substr(cur, RSTART + 1, RLENGTH - 2)
                    drop = 0
                    n = split(del, d, " ")
                    for (i = 1; i <= n; i++) if (cur == d[i]) drop = 1
                    next }
    !drop && $1 == "U" && NF >= 2 { print $2 }' | sort -u > "$W/survivor-needs"

grep -Fxv -f "$W/repl-defines" "$W/deleted-defines" > "$W/unsupplied" 2>/dev/null || true
stranded=$(grep -Fxf "$W/survivor-needs" "$W/unsupplied" 2>/dev/null || true)

if [ -n "$stranded" ]; then
    echo "surgery: REFUSING -- the deletion would strand symbols the rest of libc.a" >&2
    echo "surgery: still references, and $REPL does not define them:" >&2
    printf '%s\n' "$stranded" | sed 's/^/    /' >&2
    echo "surgery: this libc has fused its allocator into unrelated machinery." >&2
    echo "surgery: exit 3 -- unsupported on this distribution, with a reason." >&2
    exit 3
fi
echo "guard: the deletion strands nothing libc.a still references  "
echo

# --- 4. splice --------------------------------------------------------------
[ -f "$LIBC.orig" ] || cp "$LIBC" "$LIBC.orig"

{
    echo "CREATE $LIBC.new"
    echo "ADDLIB $LIBC.orig"
    for m in $members; do echo "DELETE $m"; done
    echo "ADDLIB $REPL"
    echo "SAVE"
    echo "END"
} > /tmp/surgery.mri

ar -M < /tmp/surgery.mri || { echo "surgery: ar -M failed" >&2; exit 1; }
[ -s "$LIBC.new" ] || { echo "surgery: ar wrote no archive" >&2; exit 1; }
mv "$LIBC.new" "$LIBC"
echo "=== the archive, after ==="
echo "libc.a: $(wc -c < "$LIBC") bytes, $(ar t "$LIBC" | wc -l) members"
echo

rc=0
for s in malloc free; do
    n=$(nm --defined-only "$LIBC" 2>/dev/null | awk -v s="$s" '
        NF >= 3 && $3 == s && $2 ~ /^[TtWw]$/ { c++ } END { print c + 0 }')
    if [ "$n" -eq 1 ]; then
        echo "   exactly one definition of $s in the spliced archive"
    else
        echo "   $n definitions of $s in the spliced archive (want exactly 1)" >&2
        rc=1
    fi
done

if [ "$rc" -ne 0 ]; then
    echo "surgery: restoring $LIBC.orig" >&2
    cp "$LIBC.orig" "$LIBC"
    exit 1
fi
echo
echo "surgery: done. Any -static or -static-pie link in this image now gets the"
echo "surgery: replacement allocator, with no extra flags."
exit 0
