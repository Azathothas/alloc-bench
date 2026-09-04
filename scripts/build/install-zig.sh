#!/bin/sh
set -eu

PINS="${1:-/opt/alloc-bench/toolchains/pins.env}"
[ -f "$PINS" ] || { echo "install-zig: no pins file at $PINS" >&2; exit 2; }
# shellcheck disable=SC1090
. "$PINS"

ZIG_VERSION="${ZIG_VERSION:-}"
ZIG_SHA256_x86_64="${ZIG_SHA256_x86_64:-}"
ZIG_SHA256_aarch64="${ZIG_SHA256_aarch64:-}"

arch="$(uname -m)"
case "$arch" in
    x86_64)  want="$ZIG_SHA256_x86_64" ;;
    aarch64) want="$ZIG_SHA256_aarch64" ;;
    *)       echo "install-zig: no pin for architecture $arch" >&2; exit 2 ;;
esac

if [ -z "$ZIG_VERSION" ] || [ -z "$want" ]; then
    echo "install-zig: $PINS defines no ZIG_VERSION, or no sha256 pin for $arch" >&2
    exit 2
fi

url="https://ziglang.org/download/${ZIG_VERSION}/zig-${arch}-linux-${ZIG_VERSION}.tar.xz"
if ! curl -fsSL --retry 5 --connect-timeout 20 -o /tmp/zig.tar.xz "$url"; then
    echo "install-zig: could not download $url" >&2
    exit 2
fi

got="$(sha256sum /tmp/zig.tar.xz | cut -d' ' -f1)"
if [ "$want" != "$got" ]; then
    rm -f /tmp/zig.tar.xz
    echo "install-zig: sha256 mismatch for $url" >&2
    echo "  expected $want" >&2
    echo "  got      $got" >&2
    exit 1
fi

mkdir -p /usr/local/zig
tar xf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1
rm -f /tmp/zig.tar.xz

printf '#!/bin/sh\nexec /usr/local/zig/zig cc "$@"\n' > /usr/local/bin/zig-cc
printf '#!/bin/sh\nexec /usr/local/zig/zig c++ "$@"\n' > /usr/local/bin/zig-c++
chmod +x /usr/local/bin/zig-cc /usr/local/bin/zig-c++

# Probe by USE, not by presence. A tarball that unpacked is not a compiler that
# works: zig caches a libc build on first run and that step can fail on its own.
tmp=$(mktemp -d)
echo 'int main(void){return 0;}' > "$tmp/t.c"
if ! /usr/local/bin/zig-cc "$tmp/t.c" -o "$tmp/t" 2>"$tmp/err"; then
    echo "install-zig: zig cc unpacked but cannot compile: $(tail -3 "$tmp/err")" >&2
    rm -rf "$tmp"
    exit 1
fi
rm -rf "$tmp"

/usr/local/zig/zig version
