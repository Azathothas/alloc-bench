# Rolling results

Each suite and architecture has a bounded window:

```text
results/rolling/<suite>-<arch>/
  runs/<started>-<source>/
    run.json
    rankings.json
  aggregate.json
  aggregate.md
```

Published snapshots under `results/published/` are permanent. Rolling windows
rotate and keep only the configured recent runs.

The aggregate does not average measurements across machines. For each allocator
it reports the range of relative medians, between-run spread, within-run MAD,
per-run rank, and RSS range. It publishes no ordering when ranks move. A claim
that an allocator beat the control requires a lead larger than that run's MAD
in every eligible run.

Emulated runs, missing rankings, missing CPU identity, and windows that mix
suites are rejected. Only `run.json` and `rankings.json` are copied into the
window; full datasets remain published snapshots or workflow artifacts.

Regenerate and verify with:

```sh
python3 scripts/report/aggregate.py \
  --window results/rolling/core-x86_64 --add DATASET
python3 scripts/report/aggregate.py \
  --window results/rolling/core-x86_64
python3 scripts/report/aggregate.py \
  --window results/rolling/core-x86_64 --check
python3 scripts/report/aggregate.py --selftest
```

`aggregate.md` and `aggregate.json` are generated files. Do not edit them by
hand.
