# Results

Published datasets are under `results/published/`; rolling comparisons are
under `results/rolling/`. Each run records its host, tools, source revisions,
image identity, corpus seed, cells, raw samples, validation findings, and
rankings.

Start with the
[cross-distribution x86_64 aggregate](../results/rolling/libc-contrast-x86_64/aggregate.md).
It is the main result because it compares all six supported distributions over
two native hosts. Use the
[latest complete snapshot](../results/published/2026-09-03-libc-contrast-x86_64/report.md)
when raw samples or per-cell evidence are needed. The README gives the current
evidence-backed allocator shortlist.

## Current findings

The published ripgrep runs support these scoped conclusions:

- On the three measured musl distributions, jemalloc was 13.5% to 37.1% faster
  than the system allocator and rpmalloc was 12.7% to 42.0% faster. Their peak
  RSS ranged from 1.34x to 7.03x and 1.09x to 9.47x the control, respectively.
- Across the measured glibc distributions and machines, no alternative
  allocator consistently beat the system allocator. Alternatives usually used
  more peak memory.
- Allocator ordering changed across hosts. Do not transfer a ranking without
  measuring the deployment hardware.
- For mimalloc on musl, `libc-surgery` beat `rust-global` in four repeated runs,
  but the margin varied and one run could not resolve the difference beyond its
  own dispersion.
- hardened_malloc's `light` variant was about twice as fast as its default in
  two same-commit runs and reduced peak RSS substantially. This is a performance
  result, not a security assessment.

These statements are narrower than “fastest allocator.” Workload, libc,
compiler, integration mechanism, profile, and machine all affect the result.

## Reading a run

Start with `report.md`, then inspect `rankings.json` and the cell directories.

| File | Meaning |
| --- | --- |
| `run.json` | run identity, host, tools, sources, image, and corpus |
| `rankings.json` | comparable groups, medians, MADs, ratios, and exclusions |
| `report.md` | human-readable summary generated from the same data |
| `validation.json` | errors and warnings found after the run |
| `cells/<id>/build.json` | exact build inputs and compiler identities |
| `cells/<id>/identity.json` | allocator and link-kind evidence |
| `cells/<id>/correctness.json` | expected and observed correctness checks |
| `cells/<id>/measure-*.json` | raw workload samples |

Cell outcomes are `ok`, `unsupported`, `build_failed`, `identity_failed`,
`correctness_failed`, or `measurement_failed`. Only `ok` cells with a valid
control in the same group may be ranked.

## Interpreting ratios

Time and RSS ratios use the system cell in the same group as 1.0. Lower time is
faster; lower RSS uses less peak memory. A null ratio means no valid comparison,
not zero cost. Treat a difference within the reported dispersion as unresolved.

Do not compare:

- runs from different machines as if they were replicates;
- emulated and native runs;
- static, static-PIE, and dynamic binaries;
- different corpus profiles or application profiles;
- preload results with linked allocator results.

## Rolling windows

Rolling windows retain recent runs and publish per-run ranges. They do not
average across machines. An ordering is stable only when it holds in every
eligible run; otherwise the aggregate names the disagreement and claims no
winner. Regenerate them with `scripts/report/aggregate.py`.

## Validation

Recheck a committed dataset without rerunning it:

```sh
./target/release/alloc-bench validate --run results/published/<run>
python3 scripts/check-snapshots.py --strict
python3 scripts/report/aggregate.py --check
```

Published values are evidence. Do not edit them by hand. Record a correction
under `docs/history/` and regenerate derived reports from an explicit transform.
