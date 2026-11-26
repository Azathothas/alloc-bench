# Rolling aggregate

The last **6** run(s) of this suite, on **4** distinct CPU model(s). Primary workload `literal`.

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

 **The ordering does not transfer** in `alpine / x86_64 / static-pie-lto / distro`. 1 allocator(s) changed rank between runs: **mimalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / static-pie-lto / distro`: **jemalloc, rpmalloc** beat the control in all 6 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static-pie-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.862** | 0.751 | 0.897 | 16.9% | 1.2%–3.3% | 1/1/1/1/1/1 | 1.605 |
| rpmalloc | `rust-global` | **0.874** | 0.817 | 0.911 | 10.7% | 1.3%–2.5% | 2/2/2/2/2/2 | 1.094 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.2%–2.1% | 3/3/4/3/3/3 | 1.000 |
| mimalloc | `rust-global` | **1.034** | 0.970 | 1.056 | 8.3% | 1.0%–3.7% | 4/4/3/4/4/4  | 3.876 |
| snmalloc | `rust-global` | **1.146** | 1.043 | 1.181 | 12.0% | 1.6%–3.0% | 5/5/5/5/5/5 | 1.513 |
| hardened_malloc | `rust-global` | **1.247** | 1.231 | 1.306 | 6.0% | 1.5%–4.5% | 6/6/6/6/6/6 | 2.868 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 2, 3, 2, 2, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **jemalloc**: it moved **16.9%** between runs while its own samples never spread more than **3.3%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-11-26T12:38:58Z | AMD EPYC 9V45 96-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `0382827` | [`45821286657`](https://github.com/Azathothas/alloc-bench/actions/runs/45821286657) |
| 2026-11-23T12:48:45Z | INTEL(R) XEON(R) PLATINUM 8573C | 4 | `Linux 7.0.0-1017-azure` | `8c9fa1e` | [`45177353300`](https://github.com/Azathothas/alloc-bench/actions/runs/45177353300) |
| 2026-11-19T11:43:30Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `56f19fb` | [`44517095199`](https://github.com/Azathothas/alloc-bench/actions/runs/44517095199) |
| 2026-11-16T11:24:27Z | Intel(R) Xeon(R) 6975P-C | 4 | `Linux 7.0.0-1014-aws` | `b808112` | [`43857029324`](https://github.com/Azathothas/alloc-bench/actions/runs/43857029324) |
| 2026-11-12T11:16:34Z | AMD EPYC 9V45 96-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `e720292` | [`43207393489`](https://github.com/Azathothas/alloc-bench/actions/runs/43207393489) |
| 2026-11-09T11:37:47Z | AMD EPYC 9V45 96-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `070e321` | [`42610175428`](https://github.com/Azathothas/alloc-bench/actions/runs/42610175428) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
