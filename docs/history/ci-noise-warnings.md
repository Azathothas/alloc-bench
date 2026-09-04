# The `noisy` warnings in CI, and what they were mistaken for

**Answered 2026-09-01.** Kept because the misreading is the natural one, and
because the answer turned out to be the opposite of the worry.

 **This is history.** The live constraint that came out of it - that the answer
is a property of the machine - is in `docs/AGENTS.md` §11.1, where it belongs.

---

## The superseded wording, from `docs/AGENTS.md` §13, kept verbatim

>  **How to read the "noisy" warnings in CI, because they are easy to misread in
> both directions.** Every CI run of `smoke` trips the validator's 5% noise
> threshold: `bench.yml` run 1 on x86_64 reported relative MADs of 11.0% and
> 17.1% (jemalloc), 11.2% (the baseline) and four more between 5.1% and 5.9%;
> `ci.yml` reported 12 warnings of the same kind.
>
>  **This is NOT evidence that GitHub-hosted runners are too noisy to
> benchmark on**, which is what it looks like at a glance. The `smoke` corpus is
> 6 × 20 = **120 files** and a single search takes milliseconds, so the relative
> spread is large by construction - `corpus.rs` says so at the profile
> definition, and the workflow prints "It does NOT rank anything" under every
> smoke summary. The validator flagging it is the instrument working.
>
>  **ANSWERED, 2026-09-01, and the answer is the opposite of the worry.**
> `bench.yml` was dispatched with `suite: core, arches: both`
> ([run `33500081741`](https://github.com/Azathothas/alloc-bench/actions/runs/33500081741)).
> On the `standard` corpus the `ubuntu-24.04` runner reported relative MADs of
> **0.5%–1.4%** on the primary `literal` workload across all six cells - *tighter*
> than the dev sandbox's own 2.0–8.4%. A shared GitHub runner is **not** too noisy
> to benchmark on.
>
>  The six `noisy` warnings that run did raise are almost all on `startup`
> (7.7%–22.9%) plus one `nomatch` at 5.7%. `startup` is a sub-millisecond
> microbenchmark, so its relative spread is large by construction, exactly as with
> the smoke corpus. **No allocator was flagged on `literal`.** Read the warning
> list by workload before concluding anything about a machine.
>
>  **The noise question was never the real problem.** Each machine is tight and
> self-consistent and they still disagree with each other - see §11.1, where the
> quietest of the three runs is the one that inverts the ranking.

## What still transfers

 Two rules survive this episode and are live, so they stay on the reference
pages rather than here:

- **Read a warning list by workload before concluding anything about a machine.**
  A `startup` MAD and a `literal` MAD are not the same measurement.
  (`docs/troubleshooting.md`, "A cell is flagged `noisy`".)
- **A within-run MAD is a floor on the uncertainty, not a bound.**
  (`docs/methodology.md`, and `docs/history/todo/RULES.md` §4.)
