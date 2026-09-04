# Continuous integration

The repository defines two workflows under `.github/workflows/`.

## `ci.yml`

Pushes to `main` and pull requests run three jobs:

- `instrument`: Rust formatting, linting, unit tests, release builds, and the
  runner self-test;
- `configuration`: matrix expansion, source pins, shell syntax and lint,
  documentation links, snapshot structure, evidence extracts, and generated
  aggregate freshness;
- `smoke`: one x86_64 Linux container run through image build, allocator build,
  source patching, linking, identity, correctness, measurement, validation, and
  reporting.

The smoke dataset is diagnostic and is uploaded even after a failure. Its small
corpus is not suitable for allocator ranking.

## `bench.yml`

The benchmark workflow runs on its schedule and by manual dispatch. Inputs
select the suite, repeat count, and architectures. x86_64 and aarch64 use native
Linux runners; the workflow does not label emulated measurements as native.

Each job records host conditions, frees enough disk for images and source
caches, runs the suite, validates the dataset separately, and uploads the full
result. Cell build failures remain data, while validation errors fail the job.

A single follow-up job folds completed datasets into
`results/rolling/<suite>-<arch>/`, keeps the configured recent window, regenerates
the aggregate, validates it, rebases, and pushes one commit. It never averages
measurements across machines or force-pushes.

## Permissions and dependencies

Workflow permissions are read-only except for the rolling job's documented
write to repository contents. Third-party actions are pinned to immutable
revisions. Dependency updates are configured in `.github/dependabot.yml`.

## Local equivalent

Run the host checks and container smoke suite before changing CI:

```sh
sh scripts/gate.sh --strict
./target/release/alloc-bench run \
  --suite smoke --arch x86_64 --repeat 5 \
  --out results/local/smoke --strict
```
