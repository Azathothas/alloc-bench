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

## Main results

Start with the
[cross-distribution x86_64 aggregate](results/rolling/libc-contrast-x86_64/aggregate.md).
It is the broadest current comparison: two native runs, six distributions, and
separate musl and glibc controls. The
[latest complete snapshot](results/published/2026-09-03-libc-contrast-x86_64/report.md)
contains its raw samples, build records, identity evidence, and validation.

| Goal | Evidence-backed starting point | Scope |
| --- | --- | --- |
| musl throughput | jemalloc; rpmalloc where it builds | jemalloc beat the system control on Alpine, Void, and Wolfi in both broad runs; rpmalloc did so on Alpine and Void, while its Wolfi cells failed to build |
| glibc general use | system allocator | it remained fastest and used the least peak RSS on the measured Arch, Debian, and Ubuntu groups |
| lowest peak RSS | system allocator | every measured alternative used more peak memory than its distribution control |

These are candidates to test, not universal winners. Allocator ordering changed
between machines, and the benchmark does not measure security properties or
predict allocation-heavy services.

Use the specialized views only when they match the question:

- [repeated Alpine x86_64](results/rolling/core-x86_64/aggregate.md): three
  hosts and the full core allocator set;
- [native aarch64](results/rolling/core-aarch64/aggregate.md): one run, so not a
  cross-run trend;
- [dynamic preload](results/rolling/preload-x86_64/aggregate.md): preload only,
  kept separate from linked builds;
- [all datasets and interpretation rules](docs/results.md).

The published runs also show that rewriting musl's `libc.a` beat Rust's
`#[global_allocator]` in four repeated mimalloc runs, but the margin varied.

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
