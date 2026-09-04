#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

echo "=== 1. toolchain, and a packaged allocator ==="
pacman -Sy --noconfirm archlinux-keyring >/tmp/pac.log 2>&1 || true
pacman -Syu --noconfirm --needed base-devel jemalloc binutils file >>/tmp/pac.log 2>&1 \
    || { echo "pacman failed. What it said:"; tail -12 /tmp/pac.log; exit 2; }
trust_extra_ca
print_conditions

LIB=$(find /usr/lib -name 'libjemalloc.so*' -type f 2>/dev/null | head -1)
[ -n "$LIB" ] || { echo "libjemalloc.so was not installed where expected" >&2; exit 2; }
echo "installed: $LIB ($(wc -c < "$LIB") bytes)"
echo "package:   $(pacman -Q jemalloc 2>/dev/null)"
echo

echo "=== 2. LD_PRELOAD, which works here exactly as it does on Debian ==="
cc -O2 -pthread -o /tmp/allocprobe /examples/allocprobe.c \
    || { echo "the probe did not build" >&2; exit 2; }
verify_reset
want_elf /tmp/allocprobe dynamic
if nm -D --defined-only "$LIB" 2>/dev/null | grep -qE '[[:space:]][TWi][[:space:]]+malloc$'; then
    _ok "$(basename "$LIB") EXPORTS malloc in its dynamic symbol table"
else
    _bad "$(basename "$LIB") does not export malloc -- LD_PRELOAD would interpose nothing"
fi
want_resident     "$LIB" env LD_PRELOAD="$LIB" /tmp/allocprobe stress 4 40000
want_not_resident "$LIB" /tmp/allocprobe stress 1 100
want_run "stress, 4 threads, 40 000 iterations" env LD_PRELOAD="$LIB" /tmp/allocprobe stress 4 40000
LD_PRELOAD=$LIB; export LD_PRELOAD
want_count /tmp/allocprobe 5000
unset LD_PRELOAD
echo

echo "=== 3.  THE STATIC REPLACEMENT, ATTEMPTED ==="
echo "Everything the musl examples do, on glibc, on a COPY of libc.a."
echo
GLIBC_A=$(cc -print-file-name=libc.a 2>/dev/null)
case "$GLIBC_A" in libc.a|"") GLIBC_A="" ;; esac
if [ -z "$GLIBC_A" ] || [ ! -f "$GLIBC_A" ]; then
    echo "  no static glibc on this image, so the attempt cannot even start."
    echo "   That is itself an answer: the static mechanism needs libc.a and"
    echo "    several glibc distributions do not ship one by default."
else
    echo "  libc.a: $GLIBC_A ($(wc -c < "$GLIBC_A") bytes, $(ar t "$GLIBC_A" | wc -l) members)"
    cp "$GLIBC_A" /tmp/libc-copy.a

    echo
    echo "  -- which members define the allocation entry points?"
    nm --defined-only /tmp/libc-copy.a 2>/dev/null | awk '
        /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1); next }
        NF >= 3 && $2 ~ /^[TtWwDdBb]$/ &&
            ($3 == "malloc" || $3 == "free" || $3 == "calloc" || $3 == "realloc") { print "     " m " defines " $3 }
    ' | sort -u | head -12

    echo
    echo "  -- and what ELSE does the member defining malloc define?"
    MEM=$(nm --defined-only /tmp/libc-copy.a 2>/dev/null | awk '
        /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1); next }
        NF >= 3 && $2 ~ /^[TtWwDdBb]$/ && $3 == "malloc" { print m; exit }')
    echo "     member: ${MEM:-(none found)}"
    if [ -n "$MEM" ]; then
        printf '     it defines %s symbols, including:\n' \
            "$(nm --defined-only /tmp/libc-copy.a 2>/dev/null | awk -v m="$MEM" '
                /^[^ \t].*:$/ { cur = substr($0, 1, length($0) - 1); next }
                cur == m && NF >= 3 { c++ } END { print c + 0 }')"
        nm --defined-only /tmp/libc-copy.a 2>/dev/null | awk -v m="$MEM" '
            /^[^ \t].*:$/ { cur = substr($0, 1, length($0) - 1); next }
            cur == m && NF >= 3 { print "       " $2 " " $3 }' | sort -u | head -16
    fi

    echo
    echo "  -- delete it and see what breaks"
    { echo "OPEN /tmp/libc-copy.a"; echo "DELETE $MEM"; echo "SAVE"; echo "END"; } > /tmp/g.mri
    if [ -n "$MEM" ] && ar -M < /tmp/g.mri 2>/tmp/ar.log; then
        echo "     deleted $MEM from the copy"
        cp "$GLIBC_A" "$GLIBC_A.orig"
        cp /tmp/libc-copy.a "$GLIBC_A"
        echo "     installed the modified archive as $GLIBC_A"
        echo 'int main(void){char*p=malloc(16);free(p);return 0;}' > /tmp/g.c
        echo "     cc -static -include stdlib.h -o /tmp/g /tmp/g.c        # no archive named"
        if cc -static -include stdlib.h -o /tmp/g /tmp/g.c >/tmp/glink.log 2>&1; then
            echo "      it linked. Look at WHAT it linked before trusting it:"
            printf '       definitions of malloc: %s\n' \
                "$(nm --defined-only /tmp/g 2>/dev/null | grep -cE ' [TtWw] malloc$')"
            printf '       glibc allocator internals still present: %s\n' \
                "$(nm --defined-only /tmp/g 2>/dev/null | grep -cE ' (_int_malloc|tcache_init)$')"
        else
            echo "      it does not link. The linker's own words:"
            grep -oE "undefined reference to \`[^']+'" /tmp/glink.log 2>/dev/null \
                | sort -u | head -12 | sed 's/^/       /'
            printf '       (%s undefined-reference lines in total)\n' \
                "$(grep -c 'undefined reference' /tmp/glink.log 2>/dev/null)"
        fi
        cp "$GLIBC_A.orig" "$GLIBC_A"
        echo "     $GLIBC_A restored"
    else
        echo "     ar refused to delete it: $(head -2 /tmp/ar.log 2>/dev/null | tr '\n' ' ')"
    fi
    rm -f /tmp/libc-copy.a
fi
echo

echo "=== what this example establishes ==="
echo " On glibc, LD_PRELOAD replaces the allocator in an unmodified dynamic"
echo "   binary, and residency proves it did."
echo " The static libc.a surgery that works on musl does NOT transfer to"
echo "   glibc, and the reason is visible above: the member defining malloc"
echo "   defines a great deal else that the rest of libc needs."
echo " This is why this project's planner marks glibc static-replacement cells"
echo "   unsupported with that reason rather than letting them fail every run."
verify_summary
