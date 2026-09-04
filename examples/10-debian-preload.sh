#!/bin/sh
set -u

. /examples/verify.sh
trust_extra_ca

echo "=== 1. install a replacement allocator from the distribution ==="
echo " No build step. Debian packages jemalloc, and this is the cheapest"
echo "   possible version of 'replace the allocator': one apt-get."
echo
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || { echo "apt-get update failed" >&2; exit 2; }
apt-get install -y -qq --no-install-recommends \
    libjemalloc2 gcc libc6-dev binutils file >/dev/null 2>&1 \
    || { echo "apt-get install failed" >&2; exit 2; }

print_conditions

LIB=$(find /usr/lib -name 'libjemalloc.so*' -type f 2>/dev/null | head -1)
[ -n "$LIB" ] || { echo "libjemalloc.so was not installed where expected" >&2; exit 2; }
echo "installed: $LIB ($(wc -c < "$LIB") bytes)"
echo "package:   $(dpkg-query -W -f='${Package} ${Version}' libjemalloc2 2>/dev/null)"
echo

echo "=== 2. the subject, built and linked exactly as it would be without us ==="
cc -O2 -pthread -o /tmp/allocprobe /examples/allocprobe.c \
    || { echo "the probe did not build" >&2; exit 2; }
echo "cc -O2 -pthread -o allocprobe allocprobe.c        # no allocator flags"
want_elf /tmp/allocprobe dynamic
echo "  linked against:"
ldd /tmp/allocprobe | sed 's/^/     /'
echo

echo "=== 3. run it with the replacement, and PROVE the replacement is there ==="
echo " The proof is /proc/<pid>/maps of the running process. Not the exit"
echo "   status, not the timing, not the absence of an error message."
echo
verify_reset

if nm -D --defined-only "$LIB" 2>/dev/null | grep -qE '[[:space:]][TWi][[:space:]]+malloc$'; then
    _ok "$(basename "$LIB") EXPORTS malloc in its dynamic symbol table"
else
    _bad "$(basename "$LIB") does not export malloc -- LD_PRELOAD would interpose nothing"
fi

want_resident     "$LIB" env LD_PRELOAD="$LIB" /tmp/allocprobe stress 4 40000
want_not_resident "$LIB" /tmp/allocprobe stress 1 100

want_run "stress, 4 threads, 40 000 iterations, with the replacement" \
    env LD_PRELOAD="$LIB" /tmp/allocprobe stress 4 40000
want_run "the same, single-threaded" \
    env LD_PRELOAD="$LIB" /tmp/allocprobe stress 1 40000

# The right answer, not merely a zero exit.
LD_PRELOAD=$LIB; export LD_PRELOAD
want_count /tmp/allocprobe 5000
unset LD_PRELOAD
echo

echo "=== 4.  THE SILENT FAILURE, PLANTED ON PURPOSE ==="
echo "A path that does not exist. Watch the program succeed anyway: this is"
echo "what 'I set LD_PRELOAD and my benchmark got faster' looks like when the"
echo "library was never loaded. The residency check is what tells them apart."
echo
LD_PRELOAD=/usr/lib/libthis-does-not-exist.so /tmp/allocprobe count 500 >/tmp/bogus.out 2>/tmp/bogus.err
rc=$?
echo "  LD_PRELOAD=/usr/lib/libthis-does-not-exist.so ./allocprobe count 500"
echo "    exit status: $rc          <-  SUCCESS. The loader did not fail."
echo "    stdout:      $(cat /tmp/bogus.out)"
echo "    stderr:      $(head -1 /tmp/bogus.err 2>/dev/null || echo '(empty)')"
want_not_resident "libthis-does-not-exist.so" \
    env LD_PRELOAD=/usr/lib/libthis-does-not-exist.so /tmp/allocprobe stress 1 200
echo
echo "   The loader writes a line to stderr and carries on. A program that"
echo "     does not read its own stderr -- which is most of them, under a"
echo "     supervisor -- reports nothing at all. Check residency, not exit codes."
echo

echo "=== 5. the system-wide version, and why to be careful with it ==="
echo "/etc/ld.so.preload applies to EVERY dynamically linked program on the"
echo "system, with no environment variable to forget. It is the closest thing"
echo "to literally 'replacing the system's allocator'."
echo
echo "$LIB" > /etc/ld.so.preload
echo "  # echo $LIB > /etc/ld.so.preload"
want_run "ls, an unrelated system binary, under the system-wide preload" ls /
want_resident "$LIB" /tmp/allocprobe stress 2 20000
rm -f /etc/ld.so.preload
echo "  # rm /etc/ld.so.preload      <- restored"
echo
echo "   IF THE LIBRARY IS BROKEN, EVERYTHING IS BROKEN, including the shell"
echo "     you would use to undo it. Test with LD_PRELOAD in one process first,"
echo "     and on a real machine keep a second session open before writing that"
echo "     file. In a container image it is safe: the blast radius is the image."
echo

echo "=== what this example establishes ==="
echo " A dynamically linked binary can be given a different allocator with no"
echo "   rebuild, and the replacement can be PROVEN to be in the process."
echo " It does not establish that it is faster. NOT ONE preloaded allocator"
echo "   this project has measured has beaten glibc's own on Debian: five of"
echo "   six are slower and the sixth ties, in"
echo "   results/published/2026-09-03-preload-x86_64-all-eight/."
echo " It says nothing about musl. See examples 30 and 40."
verify_summary
