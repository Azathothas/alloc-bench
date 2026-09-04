# `distros` on x86_64 - the suite's first run, and two glibc distributions that disagree

The `distros` suite has existed since the matrix was written and had **never been
run**. Every published measurement in this project before 2026-09-02 was
Alpine/musl; [`T-008`](../../../docs/history/todo/measurement.md) added three glibc cells on
mimalloc alone, and this is the first dataset that puts three distributions,
three allocators and two profiles in one run.

18 cells, 10 samples each. **18 `ok`, 0 `build_failed`, 0 validator errors, 81
`noisy` warnings.**

 **It is also the first run of the `dynamic` profile anywhere in this
project** - nine of its eighteen cells - and running it found a defect in the
identity oracle before it found anything about distributions (below).

## Conditions

| | |
| --- | --- |
| run id | `20260902-122810`, started 2026-09-02T12:28:10Z |
| `git_commit` | `78df0feab783…` |
| `git_dirty` / `git_untracked` | **false** / **0** |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
| corpus | `standard`, seed 20260901 |

 **Host quiescence, stated rather than implied: this run was NOT fully
quiescent.** No container build, no `cargo` invocation and no other benchmark
overlapped it - but short host-side processes did, as the session edited
documents alongside: `check-docs.py`, `check-todo.py`,
`scripts/report/aggregate.py` and two `alloc-bench plan` calls, each a second or
two.  That is a weaker quiescence claim than
[`../2026-09-02-profiles-x86_64/`](../2026-09-02-profiles-x86_64/) makes, and it
is written here rather than omitted. The 81 `noisy` warnings below are
consistent with it and are not attributed to it, because nothing was measured
that would separate the two.

##  Running it found the identity oracle refusing a correct binary

The first attempt failed on cell 5,
`alpine-x86_64-system-baseline-dynamic-distro`:

```
identity_failed: baseline binary shows no libc allocator implementation;
                 expected musl or glibc
```

The binary was right and the rule was wrong. Read off it before anything was
touched, per the project's rule that if the oracle rejects a cell the cell is
wrong:

| probe | answer |
| --- | --- |
| `nm --defined-only rg \| grep -cE ' [TtWw] (malloc\|free\|realloc\|calloc)$'` | **0** |
| `nm -u rg \| grep -E ' (malloc\|free\|calloc\|realloc)$'` | **all four, undefined** |
| `readelf -d rg \| grep NEEDED` | `libc.musl-x86_64.so.1` |
| `nm rg \| grep -cE '__libc_malloc_impl\|__malloc_donate\|get_meta'` | **0** |

 **In a dynamically linked binary the libc allocator is in `libc.so`, not in
the executable.** The baseline rule demanded evidence that cannot exist in this
link kind - a static-binary rule, written when every measured profile was
static, meeting the first dynamic cell this project ever ran. The dynamic branch
now asserts what *is* there: the binary imports `malloc` and `free`, defines
neither, and carries a `PT_INTERP`.  `libc_allocator_detected` is untouched for
static baselines and the contamination check is untouched for both; six selftest
cases cover it, three of them refusals. Commit `78df0fe`.

 **This dataset is the re-run.** The first attempt was stopped at cell 5 rather
than completed and annotated, because a run whose oracle is being changed
mid-flight is not a measurement.

## The headline: musl's allocator is the thing being beaten

Median `literal` time for the **control** - the only cross-distribution
comparison that is like-for-like, because every other figure is a ratio inside
its own image:

| profile | alpine (musl) | archlinux (glibc) | debian (glibc) | musl ÷ fastest glibc |
| --- | --- | --- | --- | --- |
| `static-pie` | **0.0730 s** | 0.0411 s | 0.0429 s | **1.78×** |
| `dynamic` | **0.0713 s** | 0.0486 s | 0.0449 s | **1.59×** |

 **So the gap an alternative allocator closes on Alpine is largely musl being
slow**, which is what [`T-008`](../../../docs/history/todo/measurement.md) found on one allocator
and this run confirms on the control across two profiles. It is also ripgrep's
own stated reason for bundling jemalloc on musl.

##  And the two glibc distributions do not agree with each other

`static-pie`, `rust-global`, each allocator against the control **in its own
image**:

| allocator | alpine (musl) | archlinux (glibc) | debian (glibc) |
| --- | --- | --- | --- |
| mimalloc | **0.644×** | **1.178×** | **0.878×** |
| jemalloc | 0.739× | 1.095× | 0.975× |
| system *(control)* | 1.000× | 1.000× | 1.000× |
| *MADs* | *2.9–6.3%* | *5.2–6.0%* | *3.4–5.0%* |

 **mimalloc is 17.8% SLOWER than the control on Arch and 12.2% FASTER on
Debian**, both outside their own spreads, on the same machine in the same run,
against the same libc. The validator names the control the winner on Arch (by
9.5%) and mimalloc the winner on Debian (by 11.0%).

 **What that is not evidence of.** It is *not* "glibc version X is better":
this suite does not hold the compiler still, and it is the caveat
[`T-008`](../../../docs/history/todo/measurement.md) established by running the control:

| | alpine | archlinux | debian |
| --- | --- | --- | --- |
| `cc` - what rustc linked through | gcc 15.2.0 | **gcc 16.2.1** | **gcc 14.2.0** |
| `alloc_cc` - the allocator's compiler | gcc 15.2.0 | gcc 16.2.1 | gcc 14.2.0 |

Three distributions, three compilers, three glibc/musl versions, three sets of
build defaults.  **A difference here is a difference between all of those at
once**, and this run cannot attribute it to the libc. `toolchain-control` holds
the *allocator's* compiler still and not the application's, so it does not
separate them either.

 **What is worth noticing anyway:** the control's absolute time is within 4.4%
between Arch and Debian (0.0411 vs 0.0429 s) while **mimalloc's differs by 28%**
(0.0484 vs 0.0377 s). Whatever the cause, it acts on the alternative allocator
and barely touches the distribution's own.

## The `dynamic` profile answers nothing on its own, and says so

| distribution | verdict |
| --- | --- |
| alpine | mimalloc 0.664×, jemalloc 0.678× -  the 2.1% lead is inside the 7.9% MAD, **no ordering between them** |
| archlinux | mimalloc 0.936× -  the 6.8% lead is inside the 9.5% MAD, **no result** |
| debian | jemalloc 0.980× -  the 2.0% lead is inside the 6.9% MAD, **no result** |

 **Every `dynamic` group is noisier than its `static-pie` sibling**, and the
Alpine dynamic control is the noisiest cell in the dataset at a **13.0%**
relative MAD.  Three of the six groups therefore support no ordering at all,
which is the honest output rather than a defect in the run.

## Peak RSS - the one thing that DOES transfer between distributions

Relative to the control in each image, `static-pie`:

| allocator | alpine | archlinux | debian |
| --- | --- | --- | --- |
| mimalloc | 3.470× | 3.366× | 3.460× |
| jemalloc | 1.561× | 1.479× | 1.467× |

and on `dynamic`, 3.264× / 3.040× / 3.112× and 1.571× / 1.403× / 1.406×.

 **mimalloc costs 3.0–3.5× the control's peak RSS and jemalloc 1.40–1.57× in
every distribution and both profiles** - twelve cells, one figure each. That
matches `T-008`'s 3.36–3.47× for mimalloc exactly.

 **This does not contradict "peak RSS does not transfer".** It transfers across
*distributions on one machine*; it emphatically does not transfer across
*machines* - [`../2026-09-02-profiles-x86_64-ci-runner/`](../2026-09-02-profiles-x86_64-ci-runner/)
has jemalloc at 1.58× the control on this Xeon and **8.99×** on an EPYC, on
byte-identical binaries.  Those are two different questions and this project
now has a measurement for each.

##  ASLR - 18 of 18, including the profile that had never run

| profile | link kind | distinct load addresses | randomised |
| --- | --- | --- | --- |
| `static-pie` | `static-pie` | **6 of 6** | true |
| `dynamic` | `dynamic` | **6 of 6** | true |

No exceptions, every allocator, all three distributions. The `dynamic` rows are
new: nine cells of a profile this project had never built before.

## Binary size

`static-pie`, MiB: control 8.147 (alpine) / 9.084 (arch) / 9.022 (debian);
mimalloc adds **0.21–0.23 MiB** on every distribution; jemalloc adds **6.05
(alpine) / 6.16 (arch) / 5.85 (debian) MiB**.  The `dynamic` control is
0.28 MiB smaller than the `static-pie` one on Alpine and **1.09–1.15 MiB**
smaller on the two glibc distributions, which is glibc not being copied in -
and musl being small enough that copying it in barely shows.

## Files

`report.md`, `rankings.json` and `plan.json` as produced by the run;
`results/*.json` is one document per cell; `run.json` carries the conditions
above; `validation.txt` is `alloc-bench validate` re-run over the dataset -
**0 errors, 81 warnings, 18 results**, every warning `noisy`.  No `cells/` or
`logs/`, per `docs/AGENTS.md` §11.2.
