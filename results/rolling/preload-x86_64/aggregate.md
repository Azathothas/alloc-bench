# Rolling aggregate

The last **2** run(s) of this suite, on **2** distinct CPU model(s). Primary workload `literal`.

 **Generated. Do not edit.** `scripts/report/aggregate.py` rewrites this file from the runs under `runs/`, and CI regenerates it after every weekly benchmark.

## How to read every table here

**Every measured column is one where lower is better**, marked `↓`: a ratio under `1.000` beat the control, and one over it lost.  The two exceptions are marked where they appear - `rank` (position, so `1` is best) and the run counts in the prose.

| column | means | good direction |
| --- | --- | --- |
| `rel median ↓` | the middle of this cell's per-run ratios to its own control | **lower**; `0.800` is 20% faster than the image's own allocator |
| `rel min ↓` / `rel max ↓` | the best and worst that ratio has ever been in this window | **lower**, and the GAP between them is the finding |
| `between-run spread ↓` | `(max − min) / median` across machines | **lower**; a large value means the result does not transfer |
| `within-run MAD ↓` | the spread of one run's own samples | **lower**;  it is a floor on the uncertainty, never a bound |
| `rank` | position within each run, newest first | **lower**, `1` = fastest.  A `` marks a candidate whose rank MOVED |
| `RSS rel ↓` | peak resident set relative to the control | **lower**; `3.500` means three and a half times the control's peak memory |

## What this aggregate does not establish

 Every allocator held its rank across every run in this window.  That is a statement about the machines sampled so far, not a guarantee - see the CPU models listed below.

## What survives every run in the window

- `alpine / x86_64 / dynamic / distro`: **jemalloc, rpmalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
- `debian / x86_64 / dynamic / distro`:  **no allocator beat the control in every run.**

## alpine / x86_64 / dynamic / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `preload` | **0.881** | 0.878 | 0.884 | 0.6% | 0.5%–1.2% | 1/1 | 6.914 |
| rpmalloc | `preload` | **0.897** | 0.894 | 0.900 | 0.6% | 0.8%–1.1% | 2/2 | 9.353 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 0.3%–0.8% | 3/3 | 1.000 |
| mimalloc | `preload` | **1.047** | 1.040 | 1.053 | 1.2% | 1.4%–2.8% | 4/4 | 3.916 |
| snmalloc | `preload` | **1.187** | 1.174 | 1.200 | 2.2% | 1.2%–2.1% | 5/5 | 3.487 |
| mesh | `preload` | **1.249** | 1.248 | 1.251 | 0.3% | 0.8%–0.8% | 6/6 | 7.709 |
| hardened_malloc | `preload` | **1.277** | 1.257 | 1.296 | 3.1% | 1.8%–1.9% | 7/7 | 7.765 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 2.** It did not move across this window.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **hardened_malloc**: it moved **3.1%** between runs while its own samples never spread more than **1.9%** within one.

## debian / x86_64 / dynamic / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.8%–1.8% | 1/1 | 1.000 |
| jemalloc | `preload` | **1.003** | 1.003 | 1.004 | 0.1% | 1.0%–2.3% | 2/2 | 4.749 |
| rpmalloc | `preload` | **1.027** | 1.022 | 1.032 | 0.9% | 1.2%–1.4% | 3/3 | 7.809 |
| mimalloc | `preload` | **1.223** | 1.203 | 1.244 | 3.4% | 1.5%–2.6% | 4/4 | 3.413 |
| tcmalloc | `preload` | **1.274** | 1.266 | 1.282 | 1.2% | 2.2%–2.5% | 5/5 | 2.875 |
| snmalloc | `preload` | **1.331** | 1.320 | 1.342 | 1.6% | 2.0%–3.0% | 6/6 | 2.333 |
| mesh | `preload` | **1.436** | 1.434 | 1.438 | 0.2% | 1.5%–4.0% | 7/7 | 6.569 |
| hardened_malloc | `preload` | **1.523** | 1.480 | 1.567 | 5.7% | 1.3%–1.7% | 8/8 | 6.320 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 0.** It did not move across this window.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **hardened_malloc**: it moved **5.7%** between runs while its own samples never spread more than **1.7%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-03T18:27:21Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `7ffeef4` | [`33790455334`](https://github.com/Azathothas/alloc-bench/actions/runs/33790455334) |
| 2026-09-03T07:47:50Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `c13689a` | [`33729832142`](https://github.com/Azathothas/alloc-bench/actions/runs/33729832142) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
