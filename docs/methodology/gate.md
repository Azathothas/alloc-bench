# Validation gate

Run the smallest gate that fully exercises the changed surface. Before a
release or migration, run the strict gate:

```sh
sh scripts/gate.sh --strict
```

The strict gate checks:

- Rust formatting, linting, tests, and release builds;
- shell syntax and `shellcheck`;
- documentation links and source pins;
- published snapshot structure and generated aggregate freshness;
- the runner's environment diagnostics.

Linux is required for Rust and container validation. A skipped required check
is a strict-gate failure. Changes to building, patching, allocator recipes,
measurement, validation, images, or the benchmark matrix also require the
container smoke suite:

```sh
./target/release/alloc-bench run \
  --suite smoke --arch x86_64 --repeat 5 \
  --out results/local/smoke --strict
```

Record the failing command and first actionable error. Do not weaken a check to
make an unrelated failure disappear.
