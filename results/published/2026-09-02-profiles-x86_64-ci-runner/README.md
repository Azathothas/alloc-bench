# `profiles` on a second machine - and the "the profile changes the ordering" finding does not reproduce

The second run [`T-006`](../../../docs/history/todo/measurement.md) asked for, on hardware that
is not the development sandbox. 16 cells, four profiles × three allocators + the
control, 10 samples. **16 `ok`, 0 `build_failed`, 0 validator errors, 6 `noisy`
warnings.**

 **It also carries the acceptance for [`T-014`](../../../docs/history/todo/instrument.md)**: the
`roll` job of this dispatch made the first commit that job has ever made
(`3226ee4`), creating `results/rolling/profiles-x86_64/`.

## Conditions

| | |
| --- | --- |
| run id | `20260902-120754`, started 2026-09-02T12:07:54Z |
| `git_commit` | `7ba360c9c3bcc9f243b6d1bd76aa9b1b4a58c019` |
|  `git_dirty` | **false**, and `git_untracked: 2` |
| host | **`AMD EPYC 7763 64-Core Processor`**, 4 cores, kernel `Linux 6.17.0-1022-azure` |
| where | `ubuntu-24.04`, GitHub-hosted, native x86_64 |
| runtime | docker 28.0.4 |
| dispatch | `bench` run [`33628116410`](https://github.com/Azathothas/alloc-bench/actions/runs/33628116410), `suite=profiles`, `arches=x86_64`, conclusion **`success`** |

 **The `git_dirty` line is worth reading rather than skipping.** The previous
`profiles` dispatch ([`33603002893`](https://github.com/Azathothas/alloc-bench/actions/runs/33603002893))
recorded `git_dirty: true` at a commit nobody had touched, because
`bench.yml` writes `conditions.txt` into the repository root before it measures
and the flag counted untracked files. That was fixed in `a3eb76e`, and this is
the first CI dataset published under the corrected definition.  Its predecessor
was **not** published: the settled rule is that a dataset whose tree is in doubt
is re-measured rather than annotated, and re-measuring cost one dispatch.

##  The headline finding of run 1 does not reproduce

Run 1 (`../2026-09-02-profiles-x86_64/`, 2.80GHz Xeon, dev sandbox) reported
**three different orderings across four profiles** and concluded *"the profile
changes the answer, which is what the suite was written to ask"*.

**On this machine there is one ordering, and it is the same in all four
profiles.**

| allocator | `static` | `static-lto` | `static-pie` | `static-pie-lto` |
| --- | --- | --- | --- | --- |
| jemalloc | **0.849×** | **0.848×** | **0.823×** | **0.845×** |
| mimalloc | 1.007× | 0.998× | 0.982× | 0.994× |
| system *(control)* | 1.000× | 1.000× | 1.000× | 1.000× |
| snmalloc | 1.150× | 1.141× | 1.102× | 1.129× |
| *within-run MAD* | *0.9–2.0%* | *0.9–2.1%* | *0.7–2.2%* | *0.5–1.4%* |

```
run 1, Xeon @ 2.80GHz          run 2, EPYC 7763
static          sn < mi < je   static          je < mi < sys < sn
static-lto      je < sn < mi   static-lto      je < mi < sys < sn
static-pie      mi < sn < je   static-pie      je < mi < sys < sn
static-pie-lto  sn < mi < je   static-pie-lto  je < mi < sys < sn
```

 **On the Xeon all three candidates beat the control in every profile, by
28.1–47.3%. Here only jemalloc does**, by 15.2–17.7%, and snmalloc is
**10.2–15.0% slower than musl**.

 **"Only jemalloc" means "by more than the run's own spread", and mimalloc is
the row that makes the distinction matter.** Its ratio is *nominally* below the
control in three of the four profiles - 0.998×, 0.982×, 0.994× - which a reader
scanning the table would call a win. It is not one under §9: the margins are
0.16%, 1.85% and 0.64% against MADs of 2.1%, 2.2% and 0.5% (and control MADs of
1.1–1.3%), so **every one of the four is inside the noise**.  The rolling
aggregate says the same thing in its own words - *"below the control every run
but never by more than that run's own MAD: mimalloc"*.

 **So run 1's finding was about the machine, not about the profile.** The
profile did not change the ordering on this host at all - which is a different
statement from "the profile does not matter", and both runs are published so a
reader can see which claim each supports.

 **What survives both runs:** jemalloc beats musl's allocator in every profile
on every machine measured. That is the same claim `results/rolling/core-x86_64/`
already makes, arriving independently through a different suite.

 **This run's verdicts are decisive, which makes the disagreement worse rather
than better.** The validator named jemalloc the winner in all four profiles, by
17.6–19.3%, each *outside* the run's own spread. Run 1 could name a winner in
only one of four. Two confident, self-consistent, contradictory answers is
exactly `docs/AGENTS.md` §11.1, now reproduced in a second suite.

##  The static-PIE cost is still not established, and now there are four estimates

`T-006` left this open with two disagreeing numbers. This run adds two more, on
the control, which is the only row where a cross-profile comparison is
like-for-like:

| | run 1 (Xeon) | **run 2 (EPYC)** |
| --- | --- | --- |
| `static-pie ÷ static` | 1.016, +1.6% (MADs 3.4/1.8%) → **no result** | **1.030**, +3.0% (MADs 1.8/1.3%) → outside both |
| `static-pie-lto ÷ static-lto` | 1.113, +11.3% (MADs 4.6/3.5%) → outside both | **1.011**, +1.1% (MADs 1.1/1.3%) → **no result** |

 **+1.1%, +1.6%, +3.0%, +11.3%.** Each run's own pair disagrees with itself,
and the two runs disagree about *which half* of their pair clears the noise -
run 1 can only speak for the LTO pair, run 2 only for the plain one, and they
give 11.3% and 3.0%. The honest reading is not "the cost is small" but **"the
cost of static-PIE is not a transferable number on this workload"**, and it must
not be quoted as one.

 **The run-2 LTO figure is inside the noise by one cell's MAD and outside by
the other's** (+1.14% against 1.26% and 1.08%). §9's rule reports that as no
result, and it is written here as no result rather than as a near miss.

 **LTO makes the control faster in all four measurements, and its magnitude
does not transfer either.** `static-lto ÷ static` = 0.845 (run 1) and **0.985**
(run 2); `static-pie-lto ÷ static-pie` = 0.926 and **0.967**.  All four ratios
are below 1, but run 2's plain pair (−1.5% against a 1.8% MAD) is **inside its
own noise**, so the direction holds in four of four and is a *result* in three.
Magnitude across the three: 3.3% to 15.5%.

##  The builds are reproducible across the two machines - 12 of 16 byte-identical

Comparing `binary_bytes` cell by cell against run 1:

| | |
| --- | --- |
| byte-identical | **12 of 16** |
| differ | 4, and **all four are jemalloc**: −8, −8, −18 192, −22 272 bytes |

 jemalloc's autotools build embeds build-time strings, which is the recorded
explanation for the 8-byte differences and for the 1 496-byte difference seen
between `core` runs A and B.  It is **not** established that it explains the
two ~20 KB differences, which are on the `PIC=0` (`static`, `static-lto`) cells;
that was not investigated and is written here as unexplained rather than folded
into the same sentence.

Control sizes are identical to run 1's to the byte: 7.787 MiB `static`, 6.345
`static-lto`, 8.147 `static-pie`, 6.629 `static-pie-lto`.

##  ASLR, observed rather than inferred - 16 of 16, no exceptions

| profile | link kind | distinct load addresses | randomised |
| --- | --- | --- | --- |
| `static`, `static-lto` | `static` | **1 of 6** | false |
| `static-pie`, `static-pie-lto` | `static-pie` | **6 of 6** | true |

Identical to run 1, on different hardware, for every allocator and the control.
 Along with 12 of the 16 binary sizes, this is what did reproduce exactly -
and both are properties of the *build*, not of the machine. Every measured
*timing* and every RSS ratio moved.

##  Peak RSS moves further between the machines than anything else here

Relative to the control:

| allocator | `static` | `static-lto` | `static-pie` | `static-pie-lto` | run 1, same four |
| --- | --- | --- | --- | --- | --- |
| jemalloc | **8.99×** | 8.60× | 5.50× | 5.50× | 1.58 / 1.60 / 1.55 / 1.59 |
| mimalloc | 4.91× | 4.76× | 3.05× | 3.09× | 3.71 / 3.74 / 3.47 / 3.44 |
| snmalloc | 4.36× | 4.20× | 2.66× | 2.73× | 1.58 / 1.61 / 1.52 / 1.51 |

 **jemalloc goes from 1.58× the control to 8.99×, and snmalloc from 1.58× to
4.36×, on binaries that are byte-identical for the PIE cells.** This is
`docs/AGENTS.md` §11.1's "peak RSS does not transfer" reproduced in a second
suite, and larger than the rpmalloc case it was first found on.

 **The absolute numbers say where it comes from, and it is mostly the
allocators rather than the control.** Peak RSS in kB, `static`:

| | control | jemalloc | mimalloc | snmalloc |
| --- | --- | --- | --- | --- |
| run 1, Xeon | 4 244 | 6 700 | 15 738 | 6 688 |
| **run 2, EPYC** | **3 544** | **31 864** | 17 396 | 15 452 |
| factor | 0.84× | **4.76×** | 1.11× | 2.31× |

 **mimalloc's absolute peak RSS is within 11% across the two machines while
jemalloc's is 4.8×**, on the same workload, the same corpus and the same
binary.  No explanation is offered: both hosts report 4 CPUs, so an
arena-per-core story does not fall out of the recorded conditions, and nothing
was measured that would settle it. It is written down because a memory-capped
deployment cannot be sized from either column.

 **And the apparent "PIE halves the relative RSS" in this run is the
denominator, not the allocators.** The control's own peak RSS goes 3 544 →
5 888 kB from `static` to `static-pie` (**+66%**) while jemalloc's moves 31 864
→ 32 364 (+1.6%). On the Xeon the same control step is +10%.  So the PIE
column is a statement about the musl control on this host, and reading it as
"PIE makes alternative allocators cheaper" would be exactly backwards.

## Files

`report.md`, `rankings.json` and `plan.json` as produced by the run;
`results/*.json` is one document per cell; `run.json` carries the conditions
above; `validation.txt` is `alloc-bench validate` re-run over this directory
after download - **0 errors, 6 warnings, 16 results**.  No `cells/` or `logs/`,
by the convention in `docs/AGENTS.md` §11.2: a whole dataset is tens of
megabytes.
