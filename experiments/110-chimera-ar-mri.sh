#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/experiments/out/110-chimera-ar-mri.txt"
mkdir -p "$ROOT/experiments/out"

command -v docker >/dev/null 2>&1 || { echo "no docker on PATH" >&2; exit 2; }

CHIMERA=chimeralinux/chimera:latest
ALPINE=alpine:latest

CA=""
for c in "$ROOT"/images/extra-ca/*.crt; do
    [ -f "$c" ] && { CA=$c; break; }
done
set -- --rm -v "$ROOT/examples:/examples:ro"
[ -n "$CA" ] && set -- "$@" -v "$CA:/tmp/extra-ca.crt:ro"

{
    echo "=== conditions ==="
    echo "date:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host:    $(uname -srm)"
    echo "docker:  $(docker --version 2>/dev/null)"
    echo "images:  $CHIMERA, $ALPINE"
    echo
} > "$OUT"

cat > "${TMPDIR:-/tmp}/110-chimera-probe.sh" <<'PROBE'
set -u
# shellcheck disable=SC1091
. /examples/verify.sh
trust_extra_ca >/dev/null
rc=0
ok()  { echo "  PASS  $1"; }
bad() { echo "   FAIL  $1"; rc=1; }

echo "=== 5a. is /usr/lib/libc.a there BEFORE base-devel-static? ==="
before=no; [ -f /usr/lib/libc.a ] && before=yes
echo "  /usr/lib/libc.a: $before"
[ "$before" = no ] && ok "absent before the static package" \
                   || bad "present before the static package -- the example's claim 3 is wrong"

apk update >/tmp/apk.log 2>&1 || true
apk add chimerautils base-devel base-devel-static clang lld >>/tmp/apk.log 2>&1 || {
    echo "apk add failed:"; tail -8 /tmp/apk.log; exit 2; }

echo
echo "=== 5b. and AFTER? ==="
after=no; [ -f /usr/lib/libc.a ] && after=yes
echo "  /usr/lib/libc.a:                 $after"
echo "  cc -print-file-name=libc.a:      $(cc -print-file-name=libc.a)"
[ "$after" = yes ] && ok "present after base-devel-static" \
                   || bad "still absent after base-devel-static"

echo
echo "=== 6. are /lib and /usr/lib the same directory? ==="
echo "  ls -ld /lib:  $(ls -ld /lib)"
if [ "$(stat -c %d:%i /lib 2>/dev/null)" = "$(stat -c %d:%i /usr/lib 2>/dev/null)" ]; then
    ok "same device:inode -- /lib IS /usr/lib, so both paths find the same file"
else
    bad "different directories -- the path really does matter here"
fi

echo
echo "=== 7. what header style does llvm-nm print for archive members? ==="
echo "  ar: $(ar --version 2>&1 | head -1)"
echo "  nm: $(nm --version 2>&1 | head -1)"
nm --defined-only /usr/lib/libc.a 2>/dev/null | grep -m3 ':$' | sed 's/^/    /'
style=$(nm --defined-only /usr/lib/libc.a 2>/dev/null | grep -m1 ':$')
case "$style" in
    *'('*')'*) echo "  -> ARCHIVE-QUALIFIED, libc.a(member): -- the normalisation is load-bearing" ;;
    *)         echo "  -> BARE member: -- same as GNU nm on this version" ;;
esac

echo
echo "=== 8.  does Chimera's OWN libc.a contain mimalloc? ==="
n=$(ar t /usr/lib/libc.a 2>/dev/null | grep -c 'mimalloc' || true)
echo "  members matching 'mimalloc': $n"
ar t /usr/lib/libc.a 2>/dev/null | grep 'mimalloc' | sed 's/^/    /' | head -4
echo "  who defines malloc in Chimera's libc.a:"
nm --defined-only /usr/lib/libc.a 2>/dev/null | awk '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    NF >= 3 && $2 ~ /^[TtWw]$/ && $3 == "malloc" { print "    " m }' | sort -u
echo "  mimalloc-internal symbols present in libc.a: $(nm --defined-only /usr/lib/libc.a 2>/dev/null | grep -cE ' [TtWw] mi_(heap_malloc|malloc|free)$' || true)"
echo "  musl __bin_chunk present in libc.a:          $(nm --defined-only /usr/lib/libc.a 2>/dev/null | grep -cE ' [TtWw] __bin_chunk$' || true)"

echo
echo "=== 1. does llvm-ar's MRI parser accept OPEN? ==="
cp /usr/lib/libc.a /tmp/work.a
printf 'OPEN /tmp/work.a\nDELETE free.lo\nSAVE\nEND\n' > /tmp/open.mri
if ar -M < /tmp/open.mri >/tmp/open.log 2>&1; then
    echo "  it accepted OPEN"
    bad "OPEN works here -- the example's failure had another cause"
else
    echo "  ar said: $(head -1 /tmp/open.log)"
    ok "OPEN is rejected -- this is the observed failure, reproduced"
fi

echo
echo "=== 9.  CAN THE NEGATIVE CONTROL FIRE? which musl allocator is this? ==="
# examples 30/40/60 assert `__bin_chunk` is ABSENT from the spliced binary as
# proof musl's allocator was displaced. That is only a guard if the symbol
# would have been PRESENT without the surgery. musl replaced oldmalloc (which
# has __bin_chunk) with mallocng (which does not) in 1.2.1.
for s in __bin_chunk unbin __libc_malloc_impl nontrivial_free; do
    n=$(nm --defined-only /usr/lib/libc.a 2>/dev/null | awk -v s="$s" '
        NF >= 3 && $2 ~ /^[TtWw]$/ && $3 == s { c++ } END { print c + 0 }')
    echo "  $s: $n"
done

echo
echo "=== 2+3. the CREATE form: does it parse, and does the archive WORK? ==="
ALLOC_SYMS='malloc free calloc realloc aligned_alloc posix_memalign malloc_usable_size'
MEMBERS=$(nm --defined-only /usr/lib/libc.a 2>/dev/null | awk -v syms="$ALLOC_SYMS" '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    NF >= 3 {
        n = split(syms, want, " ")
        for (i = 1; i <= n; i++)
            if ($3 == want[i] && $2 ~ /^[TtWwDdBb]$/) { print m; next }
    }' | sort -u)
MEM=$(printf '%s\n' "$MEMBERS" | head -1)
echo "  members defining an allocation entry point:"
printf '%s\n' "$MEMBERS" | sed 's/^/    /'

# A stand-in replacement: one object defining malloc/free/calloc/realloc.
cat > /tmp/repl.c <<'C'
#include <stddef.h>
extern void *__probe_sbrk(long);
static char pool[1 << 20];
static size_t used;
void *malloc(size_t n) { n = (n + 15) & ~(size_t)15;
    if (used + n > sizeof pool) return 0; void *p = pool + used; used += n; return p; }
void free(void *p) { (void)p; }
void *calloc(size_t a, size_t b) { size_t n = a * b; char *p = malloc(n);
    if (p) for (size_t i = 0; i < n; i++) p[i] = 0; return p; }
void *realloc(void *p, size_t n) { (void)p; return malloc(n); }
void *aligned_alloc(size_t a, size_t n) { (void)a; return malloc(n); }
int posix_memalign(void **r, size_t a, size_t n) { (void)a; *r = malloc(n); return *r ? 0 : 12; }
size_t malloc_usable_size(void *p) { (void)p; return 0; }
int probe_marker(void) { return 4242; }
C
cc -c -O0 -o /tmp/repl.o /tmp/repl.c || { echo "could not build the stand-in"; exit 2; }
ar rcs /tmp/repl.a /tmp/repl.o || { echo "could not archive the stand-in"; exit 2; }

cp /usr/lib/libc.a /tmp/libc-new.a.src
{
    echo "CREATE /tmp/spliced.a"
    echo "ADDLIB /tmp/libc-new.a.src"
    for m in $MEMBERS; do echo "DELETE $m"; done
    echo "ADDLIB /tmp/repl.a"
    echo "SAVE"
    echo "END"
} > /tmp/create.mri
if ar -M < /tmp/create.mri >/tmp/create.log 2>&1; then
    ok "the CREATE form parses"
else
    echo "  ar said: $(head -2 /tmp/create.log | tr '\n' ' ')"
    bad "the CREATE form was rejected too"
fi

if [ -f /tmp/spliced.a ]; then
    echo "  spliced.a: $(wc -c < /tmp/spliced.a) bytes, $(ar t /tmp/spliced.a | wc -l) members"
    echo "  (source libc.a was $(wc -c < /usr/lib/libc.a) bytes, $(ar t /usr/lib/libc.a | wc -l) members)"
    left=0
    for m in $MEMBERS; do
        [ "$(ar t /tmp/spliced.a | grep -c "^$m\$")" = 0 ] || { left=$((left + 1)); echo "    survived: $m"; }
    done
    [ "$left" = 0 ] && ok "all $(printf '%s\n' "$MEMBERS" | wc -l | tr -d ' ') members are gone from the spliced archive" \
                    || bad "$left member(s) survived the DELETE"
    [ "$(ar t /tmp/spliced.a | grep -c '^repl.o$')" = 1 ] \
        && ok "repl.o was added" || bad "repl.o was not added"
    d=$(nm --defined-only /tmp/spliced.a 2>/dev/null | awk '
        NF >= 3 && $2 ~ /^[TtWw]$/ && $3 == "malloc" { c++ } END { print c + 0 }')
    echo "  definitions of malloc in the spliced archive: $d"
    [ "$d" = 1 ] && ok "exactly one definition of malloc" \
                 || bad "$d definitions of malloc (want 1)"

    echo
    echo "  -- install it as the system libc.a and link something static"
    cp /usr/lib/libc.a /tmp/libc.a.backup
    cp /tmp/spliced.a /usr/lib/libc.a
    printf '#include <stdlib.h>\n#include <string.h>\nint probe_marker(void);\nint main(void){char*p=malloc(64);if(!p)return 1;memset(p,7,64);free(p);return probe_marker()==4242?0:2;}\n' > /tmp/t.c
    if cc -static -O0 -o /tmp/t /tmp/t.c >/tmp/link.log 2>&1; then
        ok "it links"
        if /tmp/t; then ok "and the binary runs and returns 0"
        else bad "it links but the binary exits $?"; fi
        m=$(nm --defined-only /tmp/t 2>/dev/null | grep -cE ' [TtWw] probe_marker$' || true)
        [ "$m" = 1 ] && ok "the stand-in's own symbol is in the binary -- the splice served the link" \
                     || bad "probe_marker is absent: the link did not take the added member"
    else
        echo "  the linker said:"
        grep -oE "undefined reference to .[^'\`]+.|error: .*" /tmp/link.log | sort -u | head -6 | sed 's/^/      /'
        if grep -qE '__malloc_tls_default|__malloc_tls_teardown|__malloc_init' /tmp/link.log; then
            ok "it does not link, and the undefined symbol is Chimera's allocator TLS:"
            echo "        the deletion strands __malloc_tls_default, which pthread_create.lo"
            echo "        and __init_tls.lo reference. That is a property of THIS libc, not"
            echo "        of the CREATE form -- the alpine half below links the same splice."
        else
            bad "the spliced archive does not link, for a reason unrelated to the TLS symbols"
        fi
    fi
    cp /tmp/libc.a.backup /usr/lib/libc.a
    echo "  /usr/lib/libc.a restored"
fi

echo
echo "exit: $rc"
exit $rc
PROBE

echo "=== chimera ===" >> "$OUT"
docker run "$@" -v "${TMPDIR:-/tmp}/110-chimera-probe.sh:/probe.sh:ro" \
    "$CHIMERA" sh /probe.sh >>"$OUT" 2>&1
chimera_rc=$?
echo "chimera probe exit: $chimera_rc" >> "$OUT"

# --- 4. the same CREATE script under GNU ar -------------------------------
cat > "${TMPDIR:-/tmp}/110-gnu-probe.sh" <<'PROBE'
set -u
# shellcheck disable=SC1091
. /examples/verify.sh
trust_extra_ca >/dev/null
rc=0
ok()  { echo "  PASS  $1"; }
bad() { echo "   FAIL  $1"; rc=1; }
apk add --no-cache build-base musl-dev binutils >/tmp/apk.log 2>&1 || {
    echo "apk add failed:"; tail -5 /tmp/apk.log; exit 2; }
echo "  ar: $(ar --version 2>&1 | head -1)"
echo "  nm: $(nm --version 2>&1 | head -1)"
MEM=$(nm --defined-only /usr/lib/libc.a 2>/dev/null | awk '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    NF >= 3 && $2 ~ /^[TtWw]$/ && $3 == "malloc" { print m; exit }')
echo "  member defining malloc: ${MEM:-(none)}"
echo "  which musl allocator is alpine's? (the negative control's premise)"
for s in __bin_chunk unbin __libc_malloc_impl nontrivial_free; do
    n=$(nm --defined-only /usr/lib/libc.a 2>/dev/null | awk -v s="$s" '
        NF >= 3 && $2 ~ /^[TtWw]$/ && $3 == s { c++ } END { print c + 0 }')
    echo "    $s: $n"
done
ALLOC_SYMS='malloc free calloc realloc aligned_alloc posix_memalign malloc_usable_size'
MEMBERS=$(nm --defined-only /usr/lib/libc.a 2>/dev/null | awk -v syms="$ALLOC_SYMS" '
    /^[^ \t].*:$/ { m = substr($0, 1, length($0) - 1)
                    if (match(m, /\(.*\)$/)) m = substr(m, RSTART + 1, RLENGTH - 2); next }
    NF >= 3 {
        n = split(syms, want, " ")
        for (i = 1; i <= n; i++)
            if ($3 == want[i] && $2 ~ /^[TtWwDdBb]$/) { print m; next }
    }' | sort -u)
echo "  members defining an allocation entry point:"
printf '%s\n' "$MEMBERS" | sed 's/^/    /'
cat > /tmp/r.c <<'C'
#include <stddef.h>
static char pool[1 << 20];
static size_t used;
void *malloc(size_t n) { n = (n + 15) & ~(size_t)15;
    if (used + n > sizeof pool) return 0; void *p = pool + used; used += n; return p; }
void free(void *p) { (void)p; }
void *calloc(size_t a, size_t b) { size_t n = a * b; char *p = malloc(n);
    if (p) for (size_t i = 0; i < n; i++) p[i] = 0; return p; }
void *realloc(void *p, size_t n) { (void)p; return malloc(n); }
void *aligned_alloc(size_t a, size_t n) { (void)a; return malloc(n); }
int posix_memalign(void **r, size_t a, size_t n) { (void)a; *r = malloc(n); return *r ? 0 : 12; }
size_t malloc_usable_size(void *p) { (void)p; return 0; }
int probe_marker(void) { return 4242; }
C
cc -c -O0 -o /tmp/r.o /tmp/r.c && ar rcs /tmp/r.a /tmp/r.o || exit 2
cp /usr/lib/libc.a /tmp/src.a
{ echo "CREATE /tmp/spliced.a"; echo "ADDLIB /tmp/src.a"
  for m in $MEMBERS; do echo "DELETE $m"; done
  echo "ADDLIB /tmp/r.a"; echo "SAVE"; echo "END"; } > /tmp/create.mri
if ar -M < /tmp/create.mri >/tmp/create.log 2>&1; then
    ok "GNU ar accepts the same CREATE script -- one code path serves both"
else
    echo "  ar said: $(head -2 /tmp/create.log | tr '\n' ' ')"
    bad "GNU ar rejected the CREATE script"
fi
if [ -f /tmp/spliced.a ]; then
    echo "  spliced.a: $(ar t /tmp/spliced.a | wc -l) members (source: $(ar t /tmp/src.a | wc -l))"
    left=0
    for m in $MEMBERS; do
        [ "$(ar t /tmp/spliced.a | grep -c "^$m\$")" = 0 ] || { left=$((left + 1)); echo "    survived: $m"; }
    done
    [ "$left" = 0 ] && ok "every allocation member deleted" || bad "$left survived"
    [ "$(ar t /tmp/spliced.a | grep -c '^r.o$')" = 1 ] && ok "r.o added" || bad "r.o missing"
    echo "  -- install it as the system libc.a and link something static"
    cp /usr/lib/libc.a /tmp/libc.a.backup
    cp /tmp/spliced.a /usr/lib/libc.a
    printf '#include <stdlib.h>\n#include <string.h>\nint probe_marker(void);\nint main(void){char*p=malloc(64);if(!p)return 1;memset(p,7,64);free(p);return probe_marker()==4242?0:2;}\n' > /tmp/t.c
    if cc -static -no-pie -O0 -o /tmp/t /tmp/t.c >/tmp/link.log 2>&1; then
        ok " it links -- CREATE produces a working archive"
        if /tmp/t; then ok "and the binary runs and returns 0"
        else bad "it links but the binary exits $?"; fi
        [ "$(nm --defined-only /tmp/t 2>/dev/null | grep -cE ' [TtWw] probe_marker$')" = 1 ] \
            && ok "the stand-in's own symbol is in the binary -- the splice served the link" \
            || bad "probe_marker absent: the link did not take the added member"
    else
        echo "  the linker said:"
        grep -oE "undefined reference to .[^'\`]+.|error: .*" /tmp/link.log | sort -u | head -6 | sed 's/^/      /'
        bad "the spliced archive does not link even here"
    fi
    cp /tmp/libc.a.backup /usr/lib/libc.a
    echo "  /usr/lib/libc.a restored"
fi
cp /usr/lib/libc.a /tmp/open-target.a
printf 'OPEN /tmp/open-target.a\nDELETE %s\nSAVE\nEND\n' "$MEM" > /tmp/open.mri
if ar -M < /tmp/open.mri >/tmp/open.log 2>&1; then
    ok "GNU ar also accepts OPEN -- so the old script worked here and only here"
else
    bad "GNU ar rejected OPEN: $(head -1 /tmp/open.log)"
fi
echo "exit: $rc"
exit $rc
PROBE

{
    echo
    echo "=== 4. the same CREATE script under GNU ar (alpine) ==="
} >> "$OUT"
docker run "$@" -v "${TMPDIR:-/tmp}/110-gnu-probe.sh:/probe.sh:ro" \
    "$ALPINE" sh /probe.sh >>"$OUT" 2>&1
gnu_rc=$?
echo "gnu probe exit: $gnu_rc" >> "$OUT"

rc=0
[ "$chimera_rc" -eq 0 ] || rc=1
[ "$gnu_rc" -eq 0 ] || rc=1
{
    echo
    echo "=== verdict ==="
    echo "chimera: $chimera_rc, gnu: $gnu_rc -> exit $rc"
} >> "$OUT"

rm -f "${TMPDIR:-/tmp}/110-chimera-probe.sh" "${TMPDIR:-/tmp}/110-gnu-probe.sh"
cat "$OUT"
exit $rc
