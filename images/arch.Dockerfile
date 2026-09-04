ARG BASE_IMAGE=archlinux:latest
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

# Arch Linux ARM images carry a different keyring package; both paths are tried
# because the same Dockerfile serves both and neither is the "wrong" one.
RUN (pacman-key --init >/dev/null 2>&1 || true) \
    && pacman -Sy --noconfirm --needed archlinux-keyring 2>/dev/null \
       || pacman -Sy --noconfirm --needed archlinuxarm-keyring 2>/dev/null \
       || true \
    && pacman -Syu --noconfirm --needed \
        base-devel cmake ninja git curl \
        autoconf automake libtool binutils python perl pkgconf \
        xz file unzip which \
    && pacman -Scc --noconfirm >/dev/null 2>&1 || true

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/zig:$PATH

WORKDIR /opt/alloc-bench
COPY toolchains ./toolchains
COPY scripts ./scripts

# The pinned rustup toolchain, not Arch's `rust` package: the distribution's
# Rust moves on its own schedule and would make the Rust version a hidden
# variable that differs per distribution.
RUN . ./toolchains/pins.env \
    && curl --proto '=https' --tlsv1.2 -sSf --retry 5 https://sh.rustup.rs \
       | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" \
    && rustc --version && cargo --version

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

# `distro` is decided by what the image actually is, not by which Dockerfile
# built it. On aarch64 this reports archlinuxarm.
RUN set -eu; \
    d=archlinux; \
    if [ "$(uname -m)" != "x86_64" ]; then d=archlinuxarm; fi; \
    { \
      echo "distro=$d"; \
      echo "distro_version=$(pacman -Q pacman 2>/dev/null | head -1)"; \
      echo "libc=glibc"; \
      echo "libc_version=$(ldd --version 2>&1 | head -1)"; \
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
    } > /opt/alloc-bench/image-env.txt; \
    cat /opt/alloc-bench/image-env.txt

ENV ALLOC_BENCH_LIBC=glibc \
    ALLOC_BENCH_DISTRO=archlinux
