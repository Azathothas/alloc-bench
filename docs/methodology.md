# Methodology

`alloc-bench` treats identity and correctness as prerequisites to measurement.
An unsupported, failed, incorrect, or unverifiable cell remains in the dataset
but is not ranked.

## Baseline

ripgrep selects jemalloc by default on 64-bit musl. `alloc-runner patch-rg`
removes that selection from every cell, including the system control, and then
checks the resulting number of `#[global_allocator]` declarations. Without
this step the musl control would be jemalloc rather than the distribution
allocator.

## Identity

`alloc-runner identify` reads the built artifact before timing. It requires:

- symbols unique to the requested allocator;
- no symbols belonging to another candidate allocator;
- the link kind required by the profile;
- absence of the displaced libc implementation for replacement builds.

A stripped artifact without a symbol table is unproven. Symbol presence proves
that allocator code is linked, not that every allocation reaches it; replacement
builds therefore require negative evidence for the displaced allocator too.
Preload cells add live process-map checks as described in
[`allocator-integration.md`](allocator-integration.md).

## Correctness

The deterministic corpus is generated from a seed and profile. Planted tokens
provide expected line and file counts independently of ripgrep. The searchable
data is kept below the manifest so the manifest cannot match its own tokens.

Before measurement, each cell must start and pass literal, case-insensitive,
Unicode, regex, no-match, single-thread, multithread, repeated, and JSON-output
checks. A wrong exit status or count rejects the cell.

## Measurement

The runner observes the child process from outside:

- `CLOCK_MONOTONIC` measures wall time;
- `wait4` supplies per-child peak RSS, CPU time, and fault counts;
- output goes to `/dev/null`, avoiding pipe backpressure;
- warm-up runs are discarded.

Every cell receives the same corpus, arguments, and repetition count. Cells run
serially in deterministic plan order, with all samples for one cell contiguous.
This prevents concurrent cells from competing for the host, but it does not
counterbalance slow thermal or host drift between allocators. Repeated runs on
the target hardware remain necessary.

The parent polls at a fixed interval. ASLR probes run after timed workloads and
do not contribute samples.

## Statistics

Reports use the median and scaled median absolute deviation (MAD). Missing
measurements remain null throughout parsing and ranking. A lead smaller than
the relevant run's dispersion is reported as unresolved.

Within-run MAD does not bound variation between runs. A direction that survives
repeated runs is stronger evidence than a precise ratio from one run. The
project therefore publishes individual datasets and rolling ranges instead of
pooling samples across machines.

## Comparison groups

Ratios are computed only within groups that share distribution, architecture,
profile, toolchain, integration mechanism, and link kind. Constant inputs
include pinned source revisions, Rust toolchain, corpus, Cargo profile settings,
and stack-size flags.

The `toolchain-control` suite holds the allocator compiler constant with Zig.
It does not replace Rust's distribution-specific link driver, so it cannot
isolate libc by itself. Both compiler identities are recorded.

## Architecture and emulation

Emulated runs are recorded and excluded from ranking. The stable Rust target
for aarch64 musl does not produce static-PIE, so suites use a non-PIE static
profile there and never compare it with x86_64 static-PIE.

## Limits

The results describe ripgrep, the recorded binaries, hosts, images, and run
conditions. They do not establish a universal allocator ordering, predict an
allocation-heavy service, or test allocator security properties.
