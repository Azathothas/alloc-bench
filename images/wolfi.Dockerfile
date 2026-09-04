ARG BASE_IMAGE=cgr.dev/chainguard/wolfi-base:latest
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
    done; \
    rm -rf /tmp/extra-ca

RUN apk add --no-cache \
        build-base cmake samurai git curl bash xz \
        autoconf automake libtool binutils python3 linux-headers perl pkgconf file \
    && ln -sf /usr/bin/samu /usr/bin/ninja

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/zig:$PATH

WORKDIR /opt/alloc-bench
COPY toolchains ./toolchains
COPY scripts ./scripts

RUN . ./toolchains/pins.env \
    && curl --proto '=https' --tlsv1.2 -sSf --retry 5 https://sh.rustup.rs \
       | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" \
    && rustc --version && cargo --version \
    && rustup target add "$(uname -m)-unknown-linux-musl" \
    && rustup target list --installed

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
      echo "distro=wolfi"; \
      echo "distro_version=$( . /etc/os-release; echo "${VERSION_ID:-rolling}" )"; \
      echo "libc=musl"; \
      echo "libc_version=$( (apk info -d musl 2>/dev/null | head -1) || echo unknown)"; \
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
    ALLOC_BENCH_DISTRO=wolfi
