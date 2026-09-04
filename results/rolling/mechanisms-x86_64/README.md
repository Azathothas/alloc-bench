# Why this window holds one of four published `mechanisms` runs

 **Four `mechanisms` datasets are published and this window holds one. No data
is lost, and the other three are not comparable to it.**

This window was created on 2026-09-03, when
[`scripts/check-snapshots.py`](../../../scripts/check-snapshots.py) gained the
rule that a published dataset must reach a rolling window or be accounted for
here ([`T-021`](../../../docs/history/todo/instrument.md)). `mechanisms` had **no window at
all**, so four datasets - the suite behind `docs/AGENTS.md` §5.1 and §11.2 - took
no part in what the project claims transfers across machines.

 **Folding all four was tried first, and the aggregator refused it**, correctly:

```
aggregate: results/rolling/mechanisms-x86_64: alpine / x86_64 / static-pie /
           distro / jemalloc appears in 1 of 4 runs
```

## The candidate sets, which is the whole reason

Read off each dataset's own `rankings.json`, group
`alpine / x86_64 / static-pie / distro`:

| run | dataset | candidates | what it was |
| --- | --- | --- | --- |
| `20260901-043321` | [`…-mechanisms-x86_64/`](../../published/2026-09-01-mechanisms-x86_64/) | **3** | mimalloc only: `rust-global` vs `libc-surgery` vs the control |
| `20260901-112518` | [`…-run-c/`](../../published/2026-09-01-mechanisms-x86_64-run-c/) | **7** | all five allocators, 7 ok / 9 build_failed - `libc-surgery` worked for mimalloc and nobody else |
| `20260902-013141` | [`…-run-d/`](../../published/2026-09-02-mechanisms-x86_64-run-d/) | **3** | the same three cells as the first, re-measured to confirm the nine-symbol `link-override` collision |
| `20260902-021113` | [`…-run-e/`](../../published/2026-09-02-mechanisms-x86_64-run-e/) | **10** | after [`T-005`](../../../docs/history/todo/mechanisms.md): 10 ok / 6 build_failed, `libc-surgery` working for four of five |

 **A rolling window's `rank` column is not comparable across runs with
different candidate sets.** "Position within the run, fastest = 1" means one
thing in a field of three and another in a field of ten, so every candidate
would appear to have *moved* for a reason that is not the machine - and moved
ranks are precisely what this window uses to refuse an ordering.

 **So the window holds the run whose candidate set is the suite's current
one** - run E - and the other three stay published in full. This is the rule
already ruled for [`preload`](../preload-x86_64/README.md) on 2026-09-03, applied
to the suite that needed it next, not a new decision.

##  What this costs, stated rather than glossed

The window has **one run on one machine**, so it establishes nothing whatever
about transfer, and its own " One run" banner says so.  The four-run
comparison this suite is famous for - `libc-surgery` beating the
`#[global_allocator]` in all four runs, by 4.8%, 13%, 14% and 32% - is **not
lost and was never in a window**: it is `docs/AGENTS.md` §11.2, computed from
those four published snapshots, and it is a comparison between two *mechanisms*
inside each run rather than between runs.

 **What would fix it is a second dispatch of the current suite**, not a
different bookkeeping choice here. `bench.yml` with `suite=mechanisms,
arches=x86_64` folds automatically and this window then has something to say.

##  What was rejected

- **Folding all four and letting `--check` go red.** A window that fails its own
  coherence check every run trains a reader to ignore the failure, which is the
  same trade `.github/workflows/bench.yml` refused when it stopped a
  "nothing to do here" job going red.
- **Teaching `--check` to accept a missing candidate.** Rejected for `preload` on
  2026-09-03 for a reason that has not changed: the window stores `rankings.json`
  and `run.json`, and neither says whether a candidate is absent because the
  suite did not include it or because its cell **failed and was dropped** - which
  is the case the check exists to catch. Weakening it to pass a legitimate
  widening blinds it to an illegitimate disappearance.
- **Keeping runs B and D instead**, which share a candidate set with each other
  and would give a 2-run window.  They are the *narrower* comparison and the
  *older* suite: a window following them would drift away from what the suite
  now measures, and the next automatic fold from `bench.yml` would be refused
  rather than accepted. The window follows the current suite.
