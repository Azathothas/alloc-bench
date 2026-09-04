# shellcheck shell=sh
# verify.sh -- the checks every example under examples/ runs after replacing an
# allocator. Sourced INSIDE the container; never run on its own.
#
#  THIS FILE IS THE ANSWER TO "how do I know it worked and will not segfault".
# Replacing an allocator has three failure modes and only the first is loud:
#
#   1. the build breaks           -- you find out immediately;
#   2. the program crashes        -- you find out on the first bad allocation,
#                                    which may be under load, in production, in
#                                    a thread you were not watching;
#   3.  NOTHING HAPPENS AT ALL  -- the binary runs, the tests pass, the
#                                    allocator you meant to install is simply
#                                    not there, and every number you take is
#                                    the system allocator's under another name.
#
# The third is the one this project was built against (docs/AGENTS.md:
# upstream mimalloc-bench issues 245 and 247 report exactly it). So the checks
# below are in an order that refuses to time or trust anything before identity:
#
#   want_elf        what KIND of binary is this -- static, static-PIE, dynamic
#   want_symbol     the replacement's own symbols are IN it
#   want_no_symbol  the displaced libc allocator's private symbols are NOT
#   want_resident   for LD_PRELOAD: the loader really mapped the library,
#                   and the control run really did not
#   want_run        it runs, and a signal is reported as a signal
#   want_count      it produces the RIGHT ANSWER, known before it ran
#   want_aslr       a binary claiming to be position-independent moves
#
#  EVERY CHECK READS AN EXIT CODE FROM THE PROCESS THAT PRODUCED IT. Nothing
# here is piped into anything whose status would replace it. docs/history/todo/RULES.md §4
# records what that cost this project when it was not done.
#
#  These use only binutils, coreutils and /proc, deliberately: an example you
# cannot paste into your own image is not an example. The project's own,
# stronger oracle is `alloc-runner identify`, which additionally knows each
# allocator's symbol signature and each libc's negative control
# (crates/alloc-runner/src/ident.rs). Use that where you have it; use this to
# understand what it is doing.

VERIFY_PASS=0
VERIFY_FAIL=0

_ok()   { VERIFY_PASS=$((VERIFY_PASS + 1)); printf '   %s\n' "$1"; }
_bad()  { VERIFY_FAIL=$((VERIFY_FAIL + 1)); printf '   %s\n' "$1"; }

verify_reset() { VERIFY_PASS=0; VERIFY_FAIL=0; }

verify_summary() {
    printf '\n  %d passed, %d FAILED\n' "$VERIFY_PASS" "$VERIFY_FAIL"
    [ "$VERIFY_FAIL" -eq 0 ]
}

elf_kind() {   # $1 = binary -> prints: static | static-pie | dynamic | unknown
    _t=$(readelf -h "$1" 2>/dev/null | awk '/^[[:space:]]*Type:/ {print $2}')
    if readelf -l "$1" 2>/dev/null | grep -q 'Requesting program interpreter'; then
        printf 'dynamic\n'
    elif [ "$_t" = "DYN" ]; then
        printf 'static-pie\n'
    elif [ "$_t" = "EXEC" ]; then
        printf 'static\n'
    else
        printf 'unknown\n'
    fi
}

want_elf() {   # $1 = binary, $2 = expected kind
    _got=$(elf_kind "$1")
    if [ "$_got" = "$2" ]; then
        _ok "$1 is a $2 binary"
    else
        _bad "$1 is a $_got binary; expected $2"
        readelf -h "$1" 2>/dev/null | sed -n '1,12p' | sed 's/^/       /'
    fi
}

_nm_defined() {   # $1 = binary
    nm --defined-only "$1" 2>/dev/null
}

want_symbol() {   # $1 = binary, $2... = symbols that MUST be defined
    _b=$1; shift
    if ! _tbl=$(_nm_defined "$_b"); then
        _bad "cannot read the symbol table of $_b with nm -- this says NOTHING about the binary"
        return
    fi
    for _s in "$@"; do
        if printf '%s\n' "$_tbl" | grep -qE "[[:space:]][A-Za-z][[:space:]]+$_s\$"; then
            _ok "$_b defines $_s"
        else
            _bad "$_b does NOT define $_s -- the replacement is not in this binary"
        fi
    done
}

want_no_symbol() {   # $1 = binary, $2... = symbols that must NOT be defined
    _b=$1; shift
    if ! _tbl=$(_nm_defined "$_b"); then
        _bad "cannot read the symbol table of $_b with nm -- CANNOT say the displaced allocator is gone"
        return
    fi
    for _s in "$@"; do
        if printf '%s\n' "$_tbl" | grep -qE "[[:space:]][A-Za-z][[:space:]]+$_s\$"; then
            _bad "$_b STILL defines $_s -- the original allocator is still linked in"
        else
            _ok "$_b does not define $_s (the displaced allocator is gone)"
        fi
    done
}

want_displaced() {   # $1 = before binary, $2 = after binary, $3... = symbols
    _before=$1; _after=$2; shift 2
    for _s in "$@"; do
        _in_before=0; _in_after=0
        nm --defined-only "$_before" 2>/dev/null \
            | grep -qE "[[:space:]][A-Za-z][[:space:]]+$_s\$" && _in_before=1
        nm --defined-only "$_after" 2>/dev/null \
            | grep -qE "[[:space:]][A-Za-z][[:space:]]+$_s\$" && _in_after=1
        if [ "$_in_before" -eq 0 ]; then
            _bad "$_s is absent from the UNMODIFIED build too -- this symbol proves nothing here"
        elif [ "$_in_after" -eq 1 ]; then
            _bad "$_s survived the surgery -- the original allocator is still linked in"
        else
            _ok "$_s: present before the surgery, gone after (the control fires)"
        fi
    done
}

want_resident() {   # $1 = library, $2... = command to run
    _lib=$1; shift
    _base=$(basename "$_lib")

    # The subject is started, its /proc/<pid>/maps is read while it lives, and
    # its status is reaped. Reading maps after it exits finds nothing and would
    # look identical to "the library was not mapped".
    "$@" >/dev/null 2>&1 &
    _pid=$!
    _hit=0
    _i=0
    while [ "$_i" -lt 200 ]; do
        if [ ! -d "/proc/$_pid" ]; then break; fi
        if grep -q "$_base" "/proc/$_pid/maps" 2>/dev/null; then _hit=1; break; fi
        _i=$((_i + 1))
    done
    wait "$_pid" 2>/dev/null
    if [ "$_hit" -eq 1 ]; then
        _ok "$_base is mapped into the running process (LD_PRELOAD took effect)"
    else
        _bad "$_base is NOT mapped -- LD_PRELOAD was ignored and the system allocator ran"
    fi
}

want_not_resident() {   # $1 = library, $2... = command to run WITHOUT LD_PRELOAD
    _lib=$1; shift
    _base=$(basename "$_lib")
    "$@" >/dev/null 2>&1 &
    _pid=$!
    _hit=0
    _i=0
    while [ "$_i" -lt 200 ]; do
        if [ ! -d "/proc/$_pid" ]; then break; fi
        if grep -q "$_base" "/proc/$_pid/maps" 2>/dev/null; then _hit=1; break; fi
        _i=$((_i + 1))
    done
    wait "$_pid" 2>/dev/null
    if [ "$_hit" -eq 0 ]; then
        _ok "control: $_base is absent without LD_PRELOAD (so the check above can fail)"
    else
        _bad "control: $_base is mapped even WITHOUT LD_PRELOAD -- the positive result proves nothing"
    fi
}

signal_name() {   # $1 = signal number
    case "$1" in
        4)  printf 'SIGILL' ;;
        6)  printf 'SIGABRT (an allocator assertion, or a hardening abort)' ;;
        7)  printf 'SIGBUS' ;;
        8)  printf 'SIGFPE' ;;
        9)  printf 'SIGKILL (out of memory, usually)' ;;
        11) printf 'SIGSEGV  THE SEGFAULT CASE' ;;
        *)  printf 'signal %s' "$1" ;;
    esac
}

want_run() {   # $1 = description, $2... = command
    _what=$1; shift
    _out=$("$@" 2>&1)
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        _ok "$_what -> exit 0: $(printf '%s' "$_out" | tr '\n' ' ')"
    elif [ "$_rc" -gt 128 ]; then
        _bad "$_what -> killed by $(signal_name $((_rc - 128)))"
        printf '%s\n' "$_out" | sed 's/^/       /' | head -10
    else
        _bad "$_what -> exit $_rc"
        printf '%s\n' "$_out" | sed 's/^/       /' | head -10
    fi
}

# The known-answer test: the subject plants its own needles, so the expected
# count is arithmetic and not a golden file that could have been regenerated
# from a broken run.
want_count() {   # $1 = binary, $2 = n lines
    _b=$1; _n=$2
    _expect=$(( (_n + 6) / 7 ))
    _out=$("$_b" count "$_n" 2>&1)
    _rc=$?
    _found=$(printf '%s' "$_out" | sed -n 's/.*found=\([0-9]*\).*/\1/p')
    if [ "$_rc" -eq 0 ] && [ "$_found" = "$_expect" ]; then
        _ok "known-answer: found $_found of an expected $_expect needles in $_n lines"
    elif [ "$_rc" -gt 128 ]; then
        _bad "known-answer: killed by $(signal_name $((_rc - 128)))"
    else
        _bad "known-answer: expected $_expect, got '${_found:-nothing}' (exit $_rc)"
        printf '%s\n' "$_out" | sed 's/^/       /' | head -5
    fi
}

want_aslr() {   # $1 = binary, $2 = samples, $3 = expect "moves" | "fixed"
    _b=$1; _n=${2:-6}; _want=${3:-moves}
    _addrs=$(_i=0; while [ "$_i" -lt "$_n" ]; do "$_b" addr; _i=$((_i + 1)); done \
             | awk '{print $2}' | sort -u)
    _d=$(printf '%s\n' "$_addrs" | grep -c .)
    if [ "$_want" = moves ] && [ "$_d" -gt 1 ]; then
        _ok "ASLR: $_d distinct load addresses in $_n runs"
    elif [ "$_want" = fixed ] && [ "$_d" -eq 1 ]; then
        _ok "no ASLR, as expected for this link kind: 1 load address in $_n runs"
    elif [ "$_want" = moves ]; then
        _bad "ASLR: only $_d distinct load address(es) in $_n runs -- this binary does not move"
    else
        _bad "ASLR: $_d distinct load addresses in $_n runs; expected a fixed one"
    fi
}

trust_extra_ca() {
    [ -f /tmp/extra-ca.crt ] || return 0
    _did=0

    for store in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem \
                 /etc/ssl/certs.pem /etc/pki/tls/certs/ca-bundle.crt; do
        if [ -f "$store" ]; then
            if [ -f "$store.alloc-bench-extra-ca" ]; then
                echo "note: the proxy CA was already appended to $store"
            else
                cat /tmp/extra-ca.crt >> "$store"
                : > "$store.alloc-bench-extra-ca"
                echo "note: appended the sandbox's proxy CA to $store (see docs/AGENTS.md)"
            fi
            # git and curl read these too, and some images set neither.
            export GIT_SSL_CAINFO="$store" CURL_CA_BUNDLE="$store" SSL_CERT_FILE="$store"
            _did=1
            break
        fi
    done

    if [ -d /etc/ssl/certs ] && command -v openssl >/dev/null 2>&1 \
       && [ ! -e /etc/ssl/certs/.alloc-bench-extra-ca ]; then
        _split=$(mktemp -d 2>/dev/null || echo /tmp/ca-split)
        mkdir -p "$_split"
        ( cd "$_split" && awk 'BEGIN{n=0} /BEGIN CERT/{n++} {print > sprintf("c%04d.pem", n)}' \
            /tmp/extra-ca.crt )
        _n=0
        for _f in "$_split"/c*.pem; do
            [ -f "$_f" ] || continue
            _h=$(openssl x509 -hash -noout -in "$_f" 2>/dev/null) || continue
            [ -n "$_h" ] || continue
            _b="xtra-$(basename "$_f")"
            cp "$_f" "/etc/ssl/certs/$_b"
            _i=0
            while [ -e "/etc/ssl/certs/$_h.$_i" ]; do _i=$((_i + 1)); done
            ln -s "$_b" "/etc/ssl/certs/$_h.$_i"
            _n=$((_n + 1))
        done
        rm -rf "$_split"
        : > /etc/ssl/certs/.alloc-bench-extra-ca
        echo "note: also installed $_n certificate(s) into the OpenSSL hashed directory"
        _did=1
    fi

    [ "$_did" -eq 1 ] || \
        echo "note: no trust store yet -- call trust_extra_ca again after installing ca-certificates"
    return 0
}

print_conditions() {
    echo "=== conditions ==="
    echo "date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "kernel:   $(uname -srm)"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "distro:   ${PRETTY_NAME:-${NAME:-unknown}}"
    fi
    echo "cc:       $(${CC:-cc} --version 2>/dev/null | head -1)"
    _ldd=$(ldd --version 2>&1 | head -1)
    echo "libc:     $_ldd"
    echo "binutils: $(nm --version 2>/dev/null | head -1)"
    echo
}
