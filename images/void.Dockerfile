ARG BASE_IMAGE=ghcr.io/void-linux/void-musl-busybox:latest
FROM ${BASE_IMAGE}

# Optional trust anchor for networks that terminate TLS on the way out.
# A no-op when images/extra-ca/ holds no .crt -- see that directory's README.
COPY images/extra-ca /tmp/extra-ca
RUN set -eu; \
    for c in /tmp/extra-ca/*.crt; do \
      [ -e "$c" ] || continue; \
      echo "trusting extra CA: $c"; \
      mkdir -p /etc/ssl/certs /usr/local/share/ca-certificates; \
      cat "$c" >> /etc/ssl/certs/ca-certificates.crt; \
      cp "$c" /usr/local/share/ca-certificates/; \
      mkdir -p /tmp/ca-split; \
      ( cd /tmp/ca-split && awk 'BEGIN{n=0} /BEGIN CERT/{n++} {print > sprintf("c%04d.pem", n)}' "$c" ); \
      for f in /tmp/ca-split/c*.pem; do \
        h=$(openssl x509 -hash -noout -in "$f" 2>/dev/null) || continue; \
        [ -n "$h" ] || continue; \
        b="xtra-$(basename "$f")"; \
        cp "$f" "/etc/ssl/certs/$b"; \
        i=0; while [ -e "/etc/ssl/certs/$h.$i" ]; do i=$((i+1)); done; \
        ln -s "$b" "/etc/ssl/certs/$h.$i"; \
      done; \
      rm -rf /tmp/ca-split; \
    done; \
    rm -rf /tmp/extra-ca

RUN xbps-install -Suy xbps >/dev/null 2>&1 || true; \
    xbps-install -Sy \
        gcc make cmake ninja git curl bash coreutils findutils grep sed tar xz \
        autoconf automake libtool binutils python3 perl pkg-config file \
        musl-devel linux-headers

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/zig:$PATH

WORKDIR /opt/alloc-bench
COPY toolchains ./toolchains
COPY scripts ./scripts

RUN . ./toolchains/pins.env \
    && curl --proto '=https' --tlsv1.2 -sSf --retry 5 https://sh.rustup.rs \
       | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" \
    && rustc --version && cargo --version

# zig is a control, not a requirement: exit 2 means "unavailable here" and the
# image still works with the distribution's own gcc. Recorded either way.
RUN chmod +x scripts/build/*.sh \
    && ( sh scripts/build/install-zig.sh ./toolchains/pins.env > /opt/zig-version.txt 2>&1 \
         && echo "zig_available=yes" >> /opt/zig-version.txt ) \
    || echo "zig_available=no" >> /opt/zig-version.txt

COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY allocators ./allocators

RUN cargo build --release --locked -p alloc-runner \
    && install -m 0755 target/release/alloc-runner /usr/local/bin/alloc-runner \
    && chmod +x allocators/*/build.sh \
    && alloc-runner selftest

RUN { \
      echo "distro=void"; \
      echo "distro_version=rolling"; \
      echo "libc=musl"; \
      echo "libc_version=$(xbps-query -p pkgver musl 2>/dev/null || echo unknown)"; \
      echo "arch=$(uname -m)"; \
      echo "cc=$(cc --version | head -1)"; \
      echo "cxx=$(c++ --version | head -1)"; \
      echo "ld=$(ld --version | head -1)"; \
      echo "ar=$(ar --version | head -1)"; \
      echo "rustc=$(rustc --version)"; \
      echo "cargo=$(cargo --version)"; \
      echo "cmake=$(cmake --version | head -1)"; \
      echo "zig=$(head -1 /opt/zig-version.txt 2>/dev/null)"; \
      echo "zig_available=$(grep -o 'zig_available=.*' /opt/zig-version.txt | tail -1 | cut -d= -f2)"; \
    } > /opt/alloc-bench/image-env.txt && cat /opt/alloc-bench/image-env.txt

ENV ALLOC_BENCH_LIBC=musl \
    ALLOC_BENCH_DISTRO=void
