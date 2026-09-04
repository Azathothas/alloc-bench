# Containers

Containers define the benchmark environments. The runner supports Docker and
Podman and chooses a runtime that answers `info`; a version-only response does
not prove that the engine can run containers.

```sh
docker info
# or
podman info

./target/release/alloc-bench doctor
```

## Images

| Dockerfile | Distribution | libc |
| --- | --- | --- |
| `images/alpine.Dockerfile` | Alpine | musl |
| `images/void.Dockerfile` | Void | musl |
| `images/wolfi.Dockerfile` | Wolfi | musl |
| `images/arch.Dockerfile` | Arch Linux | glibc |
| `images/debian.Dockerfile` | Debian | glibc |
| `images/ubuntu.Dockerfile` | Ubuntu | glibc |

Each image installs its distribution toolchain plus the Rust, Zig, and Bazel
versions pinned in `toolchains/pins.env`. It records the installed environment
at `/opt/alloc-bench/image-env.txt` and runs the measurement instrument's
self-test while building.

The orchestrator builds required images automatically. A manual build is:

```sh
podman build --platform linux/amd64 \
  --build-arg BASE_IMAGE=alpine:latest \
  -f images/alpine.Dockerfile \
  -t alloc-bench/alpine-x86_64:local .
```

Use absolute bind-mount paths. Docker and Podman may interpret a relative source
as a named volume, leaving the expected output directory empty.

## Windows hosts

On Windows, use WSL 2 with Docker or Podman. Validate the bridge with the
ToolKit doctor before project tests:

```powershell
pwsh -File scripts/windows/wsl-toolkit/wsl-toolkit.ps1 -Action Doctor
```

The command lives in the separate ToolKit repository. A working client,
running Podman machine or Docker engine, Linux container platform, and adequate
disk are required. Project builds and tests still run inside Linux containers.

## Proxies and trust stores

Put an organization CA in `images/extra-ca/*.crt` before building. Never disable
TLS verification. Set `ALLOC_BENCH_HTTPS_PROXY` only to an address reachable
from containers; a host loopback address refers to the container itself.

## Architecture

Native execution is required for ranked results. Cross-architecture emulation
may be enabled for functional testing, but the dataset records emulation and
excludes those cells from rankings. No normal project operation requires a
privileged container.

## Disk and cache

Full suites consume tens of gigabytes. `alloc-bench doctor` warns when free
space is low. Cache keys include allocator revision and build dimensions but
not recipe contents, so remove the affected allocator cache after changing a
recipe. Use runtime prune commands only after confirming no other project needs
the cached images.
