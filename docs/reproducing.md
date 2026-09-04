# Reproducing results

A reproduction uses the recorded source revisions, image, tools, corpus seed,
matrix dimensions, and native architecture. Matching only the allocator name
and workload is not sufficient.

## Validate an existing dataset

```sh
cargo build --release -p alloc-bench -p alloc-runner
./target/release/alloc-bench validate \
  --run results/published/<run>
python3 scripts/check-snapshots.py --strict
python3 scripts/report/aggregate.py --check
```

Inspect `run.json`, `rankings.json`, and the relevant `cells/<id>/` directory.
Confirm the recorded commit, dirty-tree state, image identity, host, architecture,
tool versions, compiler identities, corpus seed, profile, and integration mode.

## Re-run a suite

On a native Linux host with Docker or Podman:

```sh
cargo build --release -p alloc-bench -p alloc-runner
./target/release/alloc-bench doctor
./target/release/alloc-bench run \
  --suite core --arch x86_64 --repeat 12 \
  --out results/local/core --strict
```

Use the repeat count recorded by the source dataset. Do not enable emulation
for a performance reproduction. Preserve both runs even when their magnitudes
disagree.

## Re-run one cell

Use `alloc-bench plan --suite <id>` to obtain the cell dimensions, then follow
the manual container invocation in [`containers.md`](containers.md). Source
commits come from `allocators/allocators.lock.json`; ripgrep and toolchain pins
come from their committed lock files.

## Compare

Compare only cells in the same distribution, architecture, profile, toolchain,
mechanism, link kind, and corpus profile. A repeated direction across machines
is useful evidence; an exact ratio from one shared runner is not portable.

If a reproduction changes a published conclusion, add the new dataset and a
correction under `docs/history/`. Do not replace the earlier measurements.
