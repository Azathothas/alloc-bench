# Rolling aggregate

The last **6** run(s) of this suite, on **2** distinct CPU model(s). Primary workload `literal`.

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
| jemalloc | `rust-global` | **0.871** | 0.838 | 0.886 | 5.6% | 0.6%–1.8% | 1/1/1/1/1/1 | 5.547 |
| rpmalloc | `rust-global` | **0.888** | 0.858 | 0.907 | 5.5% | 0.6%–3.3% | 2/2/2/2/2/2 | 7.958 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.4%–2.6% | 3/3/4/3/3/3 | 1.000 |
| mimalloc | `rust-global` | **1.003** | 0.998 | 1.035 | 3.7% | 1.2%–2.7% | 4/4/3/4/4/4  | 3.088 |
| snmalloc | `rust-global` | **1.130** | 1.115 | 1.152 | 3.2% | 1.5%–2.6% | 5/5/5/5/5/5 | 2.711 |
| hardened_malloc | `rust-global` | **1.240** | 1.204 | 1.263 | 4.8% | 1.1%–2.0% | 6/6/6/6/6/6 | 6.215 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 2, 3, 2, 2, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **jemalloc**: it moved **5.6%** between runs while its own samples never spread more than **1.8%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-24T08:30:32Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `ed51ec8` | [`35975475439`](https://github.com/Azathothas/alloc-bench/actions/runs/35975475439) |
| 2026-09-21T08:59:38Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `6a420a9` | [`35580691061`](https://github.com/Azathothas/alloc-bench/actions/runs/35580691061) |
| 2026-09-17T08:41:57Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `f20b844` | [`35200972464`](https://github.com/Azathothas/alloc-bench/actions/runs/35200972464) |
| 2026-09-14T08:58:58Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `4663693` | [`34825316597`](https://github.com/Azathothas/alloc-bench/actions/runs/34825316597) |
| 2026-09-10T08:11:39Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `a86d5a6` | [`34453653215`](https://github.com/Azathothas/alloc-bench/actions/runs/34453653215) |
| 2026-09-07T08:21:58Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `8ba0fdd` | [`34100027540`](https://github.com/Azathothas/alloc-bench/actions/runs/34100027540) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
