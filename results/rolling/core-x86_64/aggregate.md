# Rolling aggregate

The last **6** run(s) of this suite, on **3** distinct CPU model(s). Primary workload `literal`.

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
| jemalloc | `rust-global` | **0.855** | 0.814 | 0.871 | 6.7% | 0.5%–1.7% | 1/1/1/1/1/1 | 5.459 |
| rpmalloc | `rust-global` | **0.879** | 0.863 | 0.906 | 4.9% | 0.7%–3.3% | 2/2/2/2/2/2 | 7.843 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.5%–3.3% | 3/4/3/3/3/3 | 1.000 |
| mimalloc | `rust-global` | **1.005** | 0.982 | 1.018 | 3.6% | 1.3%–2.3% | 4/3/4/4/4/4  | 3.041 |
| snmalloc | `rust-global` | **1.137** | 1.035 | 1.175 | 12.4% | 1.1%–2.6% | 5/5/5/5/5/5 | 2.694 |
| hardened_malloc | `rust-global` | **1.228** | 1.217 | 1.255 | 3.2% | 1.0%–2.0% | 6/6/6/6/6/6 | 6.160 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 3, 2, 2, 2, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **12.4%** between runs while its own samples never spread more than **2.6%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-10-12T10:53:47Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `8a46416` | [`38238999385`](https://github.com/Azathothas/alloc-bench/actions/runs/38238999385) |
| 2026-10-08T10:40:36Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `0be77d7` | [`37764613358`](https://github.com/Azathothas/alloc-bench/actions/runs/37764613358) |
| 2026-10-05T10:30:01Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `a3fd77b` | [`37296820293`](https://github.com/Azathothas/alloc-bench/actions/runs/37296820293) |
| 2026-10-01T10:12:40Z | INTEL(R) XEON(R) PLATINUM 8573C | 4 | `Linux 6.17.0-1022-azure` | `6ae9bde` | [`36847381898`](https://github.com/Azathothas/alloc-bench/actions/runs/36847381898) |
| 2026-09-28T09:50:28Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `2c1bf17` | [`36405842357`](https://github.com/Azathothas/alloc-bench/actions/runs/36405842357) |
| 2026-09-24T08:30:32Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `ed51ec8` | [`35975475439`](https://github.com/Azathothas/alloc-bench/actions/runs/35975475439) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
