# alloc-bench

`alloc-bench` measures the performance and memory cost of alternative memory
allocators in Linux container binaries. It builds ripgrep across six
distributions, verifies which allocator is present, runs correctness checks,
and records the host and toolchain with each result.

Supported distributions:

- musl: Alpine, Void, and Wolfi
- glibc: Arch Linux, Debian, and Ubuntu

Supported architectures are x86_64 and aarch64. Allocator sources, ripgrep,
and toolchains are fetched at pinned revisions.

## Findings

Results depend on the workload and machine. The published ripgrep runs support
these narrower conclusions:

| Environment | Result | Cost |
| --- | --- | --- |
| musl | jemalloc was 13.5% to 37.1% faster than the system allocator; rpmalloc was 12.7% to 42.0% faster | 1.34x to 7.03x peak RSS for jemalloc; 1.09x to 9.47x for rpmalloc |
| glibc | no alternative allocator beat the system allocator across the measured distributions and machines | alternative allocators usually increased peak RSS |
| allocator ranking | no stable ordering transferred across machines | measure on the deployment hardware |
| integration method | rewriting musl's `libc.a` beat Rust's `#[global_allocator]` in four repeated mimalloc runs | the direction held; the margin did not |

These results do not identify a universally fastest allocator. They do not
measure allocator security properties or predict allocation-heavy services.
See [results](docs/results.md) for the datasets and limits.

## Quick start

Requirements:

- Linux
- Docker or Podman
- the Rust toolchain pinned in `toolchains/pins.env`
- enough disk for source trees, images, and results

```sh
cargo build --release -p alloc-bench
./target/release/alloc-bench doctor
./target/release/alloc-bench run --suite core --arch x86_64
```

Run the host-side checks with:

```sh
sh scripts/gate.sh --strict
```

The smoke suite exercises the complete container pipeline:

```sh
./target/release/alloc-bench run \
  --suite smoke --arch x86_64 --repeat 5 \
  --out results/local/smoke --strict
```

## Integration methods

| Method | Applies to | Scope |
| --- | --- | --- |
| `rust-global` | source builds | Rust allocations through the allocator's prefixed API |
| `libc-surgery` | compatible musl images | every later static link against the rewritten `libc.a` |
| `preload` | dynamic binaries | allocations resolved through `LD_PRELOAD` |
| `link-override` | experimental control | depends on the program's link closure and is not a supported deployment method |

The benchmark verifies allocator identity before timing. Failed, unsupported,
or unverifiable configurations remain in the report and are never ranked.

## Evidence

- [`results/published/`](results/published/) contains complete published
  datasets.
- [`results/rolling/`](results/rolling/) compares recent runs without averaging
  across machines.
- [`examples/`](examples/) contains runnable replacement examples and captured
  output.
- [`experiments/`](experiments/) contains focused regression probes and their
  output.
- [`docs/history/`](docs/history/) contains completed work records, withdrawn
  claims, and review notes. It is not current guidance.

## Documentation

Start with the [documentation index](docs/README.md).

| Topic | Document |
| --- | --- |
| replace an allocator | [`docs/replacing-the-allocator.md`](docs/replacing-the-allocator.md) |
| reproduce a result | [`docs/reproducing.md`](docs/reproducing.md) |
| interpret results | [`docs/results.md`](docs/results.md) |
| benchmark method | [`docs/methodology.md`](docs/methodology.md) |
| allocator recipes | [`docs/allocator-integration.md`](docs/allocator-integration.md) |
| CI | [`docs/ci.md`](docs/ci.md) |
| extend the matrix | [`docs/extending.md`](docs/extending.md) |
| troubleshoot a run | [`docs/troubleshooting.md`](docs/troubleshooting.md) |

## License

[0BSD](LICENSE). Third-party sources are fetched during builds and retain their
own licenses.
