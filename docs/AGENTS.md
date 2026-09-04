# Agent guide

Read [`../README.md`](../README.md) first. This file routes maintenance work and
states the invariants that are easy to violate. Technical details belong in the
linked topic documents.

## Routes

| Task | Read |
| --- | --- |
| change allocator recipes or integration modes | [`allocator-integration.md`](allocator-integration.md), [`extending.md`](extending.md) |
| change measurement, ranking, or validation | [`methodology.md`](methodology.md), [`results.md`](results.md) |
| change static linking or allocator replacement | [`static-linking.md`](static-linking.md), [`replacing-the-allocator.md`](replacing-the-allocator.md) |
| change containers | [`containers.md`](containers.md) |
| change CI | [`ci.md`](ci.md) |
| diagnose a failure | [`troubleshooting.md`](troubleshooting.md) |
| change prose, code, shell, or Git behavior | [`conventions/`](conventions/) |
| inspect completed work or withdrawn claims | [`history/`](history/) |

## Invariants

- The project targets Linux. Use a Linux host or an ephemeral Linux environment
  for build and runtime validation.
- Verify allocator identity before timing. A cell with missing, conflicting, or
  unverifiable identity is not ranked.
- Keep the system allocator as the control. On musl, remove ripgrep's built-in
  jemalloc selection from every cell, including the baseline.
- Record unsupported configurations with a technical reason. Do not omit them.
- Keep dynamic, static, and static-PIE results in separate comparison groups.
- Treat a lead smaller than the run's own dispersion as unresolved.
- Record source revisions, tools, host properties, image digests, and dirty-tree
  state with every dataset.
- Never average results across machines. Rolling windows publish ranges and
  reject orderings that do not hold across their runs.
- Generated rolling aggregates must match `scripts/report/aggregate.py`.
- Preserve published datasets. Add corrections under `docs/history/`; do not
  rewrite measured values without documenting the transformation.

## Commands

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --release --workspace
cargo build --release -p alloc-bench -p alloc-runner
sh scripts/gate.sh --strict
```

Run the container smoke test when a change affects building, execution,
measurement, images, allocator recipes, or the matrix:

```sh
./target/release/alloc-bench run \
  --suite smoke --arch x86_64 --repeat 5 \
  --out results/local/smoke --strict
```

## Ownership

| Path | Owns |
| --- | --- |
| `benchmarks/matrix.toml` | suites, cells, workloads, profiles, and support boundaries |
| `allocators/allocators.toml` | allocator capabilities and recipe metadata |
| `allocators/allocators.lock.json` | pinned upstream revisions |
| `allocators/*/build.sh` | allocator builds |
| `scripts/build/run-cell.sh` | the per-cell build and measurement sequence |
| `crates/alloc-runner/` | patching, ELF/archive checks, execution, and measurement |
| `crates/alloc-bench/` | planning, orchestration, validation, reports, and aggregates |
| `results/published/` | immutable published datasets |
| `results/rolling/` | generated cross-run summaries |

## Repository rules

- Keep changes scoped and run the relevant gate before committing.
- Use the repository's default Git identity. Do not add model, tool, or vendor
  attribution to commits.
- Do not push unless the task explicitly authorizes it.
- Do not hand-edit generated aggregates, lock files, or recorded measurements.
- Never commit credentials, local environment files, caches, or build output.
- Keep current guidance out of `docs/history/`; history is not an instruction
  source.
