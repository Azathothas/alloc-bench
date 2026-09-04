# Rolling aggregate

The last **3** run(s) of this suite, on **3** distinct CPU model(s). Primary workload `literal`.

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

 **The ordering does not transfer** in `alpine / x86_64 / static-pie-lto / distro`. 5 allocator(s) changed rank between runs: **hardened_malloc**, **jemalloc**, **mimalloc**, **rpmalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **hardened_malloc**, **mimalloc**, **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / static-pie-lto / distro`: **jemalloc, rpmalloc** beat the control in all 3 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static-pie-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| snmalloc | `rust-global` | **0.595** | 0.553 | 1.138 | 98.3% | 1.3%–8.4% | 1/5/1  | 1.583  (1.49–2.69) |
| mimalloc | `rust-global` | **0.660** | 0.577 | 1.004 | 64.7% | 1.4%–3.5% | 2/4/2  | 3.446 |
| rpmalloc | `rust-global` | **0.754** | 0.616 | 0.879 | 34.8% | 1.3%–5.5% | 4/2/3  | 1.135  (1.12–8.01) |
| jemalloc | `rust-global` | **0.762** | 0.592 | 0.878 | 37.6% | 0.7%–4.2% | 3/1/4  | 1.693  (1.63–5.55) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.4%–4.1% | 6/3/5 | 1.000 |
| hardened_malloc | `rust-global` | **1.075** | 0.890 | 1.225 | 31.2% | 0.5%–6.4% | 5/6/6  | 2.929  (2.85–6.24) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 5, 2, 4.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **rpmalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **98.3%** between runs while its own samples never spread more than **8.4%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-01T11:02:31Z | Intel(R) Xeon(R) Processor @ 2.10GHz | 4 | `Linux 6.18.44-fc-v22` | `194ed63` | local |
| 2026-09-01T11:00:58Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `194ed63` | [`33500081741`](https://github.com/Azathothas/alloc-bench/actions/runs/33500081741) |
| 2026-09-01T03:52:24Z | Intel(R) Xeon(R) Processor @ 2.80GHz | 4 | `Linux 6.18.44-fc-v22` | `unknown` | local |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
