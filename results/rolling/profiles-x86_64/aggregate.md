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

 **The ordering does not transfer** in `alpine / x86_64 / static / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**, **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `alpine / x86_64 / static-lto / distro`. 2 allocator(s) changed rank between runs: **mimalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `alpine / x86_64 / static-pie / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `alpine / x86_64 / static-pie-lto / distro`. 2 allocator(s) changed rank between runs: **jemalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / static / distro`: **jemalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
- `alpine / x86_64 / static-lto / distro`: **jemalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
  -  **below the control every run but never by more than that run's own MAD:** **mimalloc**. Not counted above: a lead smaller than the run's own spread is no result.
- `alpine / x86_64 / static-pie / distro`: **jemalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
  -  **below the control every run but never by more than that run's own MAD:** **mimalloc**. Not counted above: a lead smaller than the run's own spread is no result.
- `alpine / x86_64 / static-pie-lto / distro`: **jemalloc, mimalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.733** | 0.617 | 0.848 | 31.6% | 0.9%–4.8% | 1/3  | 5.285  (1.58–8.99) |
| mimalloc | `rust-global` | **0.803** | 0.600 | 1.007 | 50.6% | 0.7%–2.0% | 3/2  | 4.308  (3.71–4.91) |
| snmalloc | `rust-global` | **0.838** | 0.527 | 1.150 | 74.3% | 1.7%–2.0% | 4/1  | 2.968  (1.58–4.36) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.8%–3.4% | 2/4 | 1.000 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 1, 3.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**, **mimalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **74.3%** between runs while its own samples never spread more than **2.0%** within one.

## alpine / x86_64 / static-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.753** | 0.657 | 0.848 | 25.3% | 0.9%–8.7% | 1/1 | 5.102  (1.60–8.60) |
| mimalloc | `rust-global` | **0.859** | 0.719 | 0.998 | 32.5% | 2.1%–3.9% | 2/3  | 4.248 |
| snmalloc | `rust-global` | **0.901** | 0.660 | 1.141 | 53.4% | 1.6%–9.6% | 4/2  | 2.905  (1.61–4.20) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.1%–4.6% | 3/4 | 1.000 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 3.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **53.4%** between runs while its own samples never spread more than **9.6%** within one.

## alpine / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.717** | 0.611 | 0.823 | 29.6% | 0.7%–2.3% | 1/3  | 3.522  (1.55–5.50) |
| mimalloc | `rust-global` | **0.790** | 0.599 | 0.981 | 48.4% | 2.2%–2.9% | 2/1  | 3.260 |
| snmalloc | `rust-global` | **0.854** | 0.606 | 1.102 | 58.1% | 0.9%–3.4% | 4/2  | 2.091  (1.52–2.66) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.3%–1.8% | 3/4 | 1.000 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 3.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **58.1%** between runs while its own samples never spread more than **3.4%** within one.

## alpine / x86_64 / static-pie-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.767** | 0.688 | 0.845 | 20.5% | 0.5%–3.2% | 1/3  | 3.545  (1.59–5.50) |
| mimalloc | `rust-global` | **0.775** | 0.557 | 0.994 | 56.3% | 0.5%–3.7% | 2/2 | 3.265 |
| snmalloc | `rust-global` | **0.834** | 0.539 | 1.129 | 70.8% | 1.4%–2.0% | 4/1  | 2.119  (1.51–2.73) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.3%–3.5% | 3/4 | 1.000 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 3.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **70.8%** between runs while its own samples never spread more than **2.0%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-02T12:07:54Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `7ba360c` | [`33628116410`](https://github.com/Azathothas/alloc-bench/actions/runs/33628116410) |
| 2026-09-02T02:46:10Z | Intel(R) Xeon(R) Processor @ 2.80GHz | 4 | `Linux 6.18.44-fc-v22` | `13bd3dc` | local |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
