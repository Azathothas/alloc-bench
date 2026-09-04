#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/tmp/apt.log 2>&1 || { echo "apt-get update failed:"; tail -5 /tmp/apt.log; exit 2; }
apt-get install -y -qq --no-install-recommends gcc libc6-dev binutils \
    >>/tmp/apt.log 2>&1 || { echo "apt-get install failed:"; tail -5 /tmp/apt.log; exit 2; }
trust_extra_ca
cc -O2 -pthread -o /tmp/dyn /examples/allocprobe.c || { echo "probe build failed" >&2; exit 2; }
cc -O2 -static -no-pie -pthread -o /tmp/sta /examples/allocprobe.c 2>/dev/null || cp /tmp/dyn /tmp/sta

printf 'int displaced_marker(void){return 1;}\nint main(void){return displaced_marker()-1;}\n' > /tmp/before.c
printf 'int main(void){return 0;}\n' > /tmp/after.c
cc -O0 -o /tmp/dm-before /tmp/before.c || { echo "marker build failed" >&2; exit 2; }
cc -O0 -o /tmp/dm-after  /tmp/after.c  || { echo "marker build failed" >&2; exit 2; }

rc=0
n=0

must_fail() {   # $1 = case name; rest = the check and its arguments
    _name=$1; shift
    verify_reset
    "$@" >/tmp/case.out 2>&1
    n=$((n + 1))
    if [ "$VERIFY_FAIL" -ge 1 ] && [ "$VERIFY_PASS" -eq 0 ]; then
        printf '   %-46s refused, as it must\n' "$_name"
    else
        rc=1
        printf '   %-46s DID NOT REFUSE (pass=%s fail=%s)\n' \
            "$_name" "$VERIFY_PASS" "$VERIFY_FAIL"
        sed 's/^/       /' /tmp/case.out | head -6
    fi
}

must_pass() {   # the positive direction, so a check that ALWAYS fails is caught too
    _name=$1; shift
    verify_reset
    "$@" >/tmp/case.out 2>&1
    n=$((n + 1))
    if [ "$VERIFY_PASS" -ge 1 ] && [ "$VERIFY_FAIL" -eq 0 ]; then
        printf '   %-46s accepted, as it must\n' "$_name"
    else
        rc=1
        printf '   %-46s DID NOT ACCEPT (pass=%s fail=%s)\n' \
            "$_name" "$VERIFY_PASS" "$VERIFY_FAIL"
        sed 's/^/       /' /tmp/case.out | head -6
    fi
}

echo "=== conditions ==="
print_conditions

echo "=== each check, given something it MUST refuse ==="
must_fail "want_elf: a dynamic binary called static"     want_elf /tmp/dyn static
must_fail "want_elf: a dynamic binary called static-pie" want_elf /tmp/dyn static-pie
must_fail "want_symbol: a symbol nothing defines"        want_symbol /tmp/dyn mi_malloc_that_is_not_there
must_fail "want_no_symbol: a symbol that IS defined"     want_no_symbol /tmp/dyn main
must_fail "want_resident: a library nobody preloads"     want_resident /nonexistent/libnope.so /tmp/dyn stress 1 200
must_fail "want_not_resident: libc, always mapped"       want_not_resident /lib/x86_64-linux-gnu/libc.so.6 /tmp/dyn stress 1 400
must_fail "want_run: a command that exits non-zero"      want_run "false" false
must_fail "want_run: a command killed by SIGSEGV"        want_run "corrupt" sh -c 'kill -SEGV $$'
must_fail "want_count: the wrong expected count"         want_count /bin/true 5000
must_fail "want_aslr: a PIE told to be fixed"            want_aslr /tmp/dyn 6 fixed
must_fail "want_displaced: the symbol survived"          want_displaced /tmp/dm-before /tmp/dm-before displaced_marker
must_fail "want_displaced: absent from BOTH (no evidence)" want_displaced /tmp/dm-after /tmp/dm-after displaced_marker
printf 'this is not an ELF file at all\n' > /tmp/notelf
must_fail "want_symbol: a file nm cannot read"           want_symbol /tmp/notelf main
must_fail "want_no_symbol: a file nm cannot read"        want_no_symbol /tmp/notelf main
echo

echo "=== and the positive direction, so a check that always fails is caught ==="
must_pass "want_elf: a dynamic binary called dynamic"    want_elf /tmp/dyn dynamic
must_pass "want_symbol: a symbol that IS defined"        want_symbol /tmp/dyn main
must_pass "want_no_symbol: a symbol nothing defines"     want_no_symbol /tmp/dyn mi_malloc_that_is_not_there
must_pass "want_run: a command that exits 0"             want_run "true" true
must_pass "want_count: the right expected count"         want_count /tmp/dyn 5000
must_pass "want_aslr: a PIE told to move"                want_aslr /tmp/dyn 6 moves
must_pass "want_displaced: present before, gone after"   want_displaced /tmp/dm-before /tmp/dm-after displaced_marker
echo

echo "=== what this establishes ==="
echo "Every check in examples/verify.sh both refuses what it should and accepts"
echo "what it should, and records the verdict where verify_summary reads it."
echo " It does NOT establish that the six examples check the right things --"
echo "   that is a reading job, and it is what a review pass is for."
echo
printf '%d case(s), %s\n' "$n" "$( [ "$rc" -eq 0 ] && echo '0 failures' || echo 'FAILURES ABOVE' )"
exit "$rc"
