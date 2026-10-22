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

 **The ordering does not transfer** in `alpine / x86_64 / static-pie-lto / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**, **rpmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / static-pie-lto / distro`: **jemalloc, rpmalloc** beat the control in all 6 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static-pie-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.863** | 0.853 | 0.909 | 6.5% | 0.5%–3.9% | 1/1/2/1/1/1  | 5.467 |
| rpmalloc | `rust-global` | **0.877** | 0.863 | 0.906 | 5.0% | 0.8%–2.9% | 2/2/1/2/2/2  | 7.853 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 0.8%–3.3% | 3/3/4/3/4/3 | 1.000 |
| mimalloc | `rust-global` | **1.012** | 0.982 | 1.018 | 3.6% | 0.9%–1.6% | 4/4/3/4/3/4  | 3.044 |
| snmalloc | `rust-global` | **1.133** | 1.117 | 1.175 | 5.2% | 1.1%–3.4% | 5/5/5/5/5/5 | 2.699 |
| hardened_malloc | `rust-global` | **1.241** | 1.217 | 1.259 | 3.4% | 1.0%–2.7% | 6/6/6/6/6/6 | 6.151 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 2, 3, 2, 3, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **jemalloc**: it moved **6.5%** between runs while its own samples never spread more than **3.9%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-10-22T08:40:43Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `9fe050d` | [`39749224084`](https://github.com/Azathothas/alloc-bench/actions/runs/39749224084) |
| 2026-10-19T08:57:33Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `75156b9` | [`39226163030`](https://github.com/Azathothas/alloc-bench/actions/runs/39226163030) |
| 2026-10-15T08:21:30Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `107e431` | [`38704856958`](https://github.com/Azathothas/alloc-bench/actions/runs/38704856958) |
| 2026-10-12T10:53:47Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `8a46416` | [`38238999385`](https://github.com/Azathothas/alloc-bench/actions/runs/38238999385) |
| 2026-10-08T10:40:36Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `0be77d7` | [`37764613358`](https://github.com/Azathothas/alloc-bench/actions/runs/37764613358) |
| 2026-10-05T10:30:01Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `a3fd77b` | [`37296820293`](https://github.com/Azathothas/alloc-bench/actions/runs/37296820293) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
