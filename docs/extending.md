# Extending the benchmark

An extension is complete only when planning, execution, metadata, validation,
reporting, documentation, and tests agree.

## Add an allocator

1. Add policy and supported mechanisms to `allocators/allocators.toml`.
2. Add `allocators/<id>/build.sh` using the recipe contract in
   [`allocator-integration.md`](allocator-integration.md).
3. Add unique identity signatures in `crates/alloc-runner/src/ident.rs`.
4. Add a shim backend and feature if `rust-global` is supported.
5. Resolve and commit the exact source revision with `alloc-bench update`.
6. Add at least one matrix cell for every declared mechanism.
7. Test supported and unsupported paths in Linux containers.

Do not declare a capability that no suite exercises. An unsupported combination
must have a technical reason and must remain visible in the plan and report.

## Add a distribution

Add an image Dockerfile, map it in the orchestrator, define its libc and
architecture support, and include it in a focused suite with a system control.
Record the distribution identity, compiler versions, and image ID. Test package
installation, extra-CA handling, native architecture, static and dynamic link
kinds, and container output ownership.

## Add a suite

Add a `[[suite]]` entry to `benchmarks/matrix.toml`. State one question, vary
only the dimensions needed to answer it, and retain a control in each comparison
group. Check expansion with:

```sh
./target/release/alloc-bench plan --suite <id>
```

Avoid a full Cartesian product. More cells add cost without improving an
experiment unless they distinguish a hypothesis.

## Add a profile or workload

Profiles must define link kind, PIC, LTO, and expected ASLR behavior explicitly.
Update build flags, identity validation, grouping, and architecture support
together. Workloads need deterministic input, an independent correctness
oracle, warm-up behavior, bounded execution, and stable machine-readable
output.

## Acceptance

Run unit tests for planning and validation, inspect the expanded matrix, clear
affected caches, then run the strict gate and container smoke suite. A change to
statistics or report generation also requires regenerating and checking rolling
aggregates.
