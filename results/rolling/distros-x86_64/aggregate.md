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

 **The ordering does not transfer** in `alpine / x86_64 / dynamic / distro`. 2 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `alpine / x86_64 / static-pie / distro`. 2 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `archlinux / x86_64 / dynamic / distro`. 1 allocator(s) changed rank between runs: **mimalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `debian / x86_64 / dynamic / distro`. 1 allocator(s) changed rank between runs: **jemalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **jemalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `debian / x86_64 / static-pie / distro`. 1 allocator(s) changed rank between runs: **mimalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **jemalloc**, **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / dynamic / distro`: **jemalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
- `alpine / x86_64 / static-pie / distro`: **jemalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
- `archlinux / x86_64 / dynamic / distro`:  **no allocator beat the control in every run.**
- `archlinux / x86_64 / static-pie / distro`:  **no allocator beat the control in every run.**
- `debian / x86_64 / dynamic / distro`:  **no allocator beat the control in every run.**
- `debian / x86_64 / static-pie / distro`:  **no allocator beat the control in every run.**

## alpine / x86_64 / dynamic / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.785** | 0.678 | 0.892 | 27.3% | 1.8%–6.4% | 1/2  | 4.303  (1.57–7.04) |
| mimalloc | `rust-global` | **0.875** | 0.664 | 1.086 | 48.3% | 0.8%–7.9% | 3/1  | 3.617 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.2%–13.0% | 2/3 | 1.000 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 1, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **mimalloc**: it moved **48.3%** between runs while its own samples never spread more than **7.9%** within one.

## alpine / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.806** | 0.739 | 0.873 | 16.6% | 1.2%–5.8% | 1/2  | 3.500  (1.56–5.44) |
| mimalloc | `rust-global` | **0.825** | 0.644 | 1.006 | 43.9% | 1.6%–2.9% | 3/1  | 3.254 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.9%–6.3% | 2/3 | 1.000 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 1, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **mimalloc**: it moved **43.9%** between runs while its own samples never spread more than **2.9%** within one.

## archlinux / x86_64 / dynamic / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.7%–3.7% | 1/2 | 1.000 |
| mimalloc | `rust-global` | **1.081** | 0.936 | 1.226 | 26.8% | 1.3%–9.5% | 2/1  | 3.198 |
| jemalloc | `rust-global` | **1.167** | 1.099 | 1.235 | 11.7% | 6.7%–21.0% | 3/3 | 3.022  (1.40–4.64) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 1.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **mimalloc**: it moved **26.8%** between runs while its own samples never spread more than **9.5%** within one.

## archlinux / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.1%–5.6% | 1/1 | 1.000 |
| jemalloc | `rust-global` | **1.056** | 1.018 | 1.095 | 7.3% | 1.2%–5.2% | 2/2 | 3.410  (1.48–5.34) |
| mimalloc | `rust-global` | **1.197** | 1.178 | 1.215 | 3.1% | 2.2%–6.0% | 3/3 | 3.542 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 0.** It did not move across this window.

 **Peak RSS does not transfer either**, for **jemalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **jemalloc**: it moved **7.3%** between runs while its own samples never spread more than **5.2%** within one.

## debian / x86_64 / dynamic / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.999** | 0.980 | 1.019 | 3.9% | 2.3%–6.2% | 2/1  | 3.031  (1.41–4.66) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.2%–6.9% | 1/2 | 1.000 |
| mimalloc | `rust-global` | **1.149** | 1.102 | 1.197 | 8.2% | 1.3%–8.4% | 3/3 | 3.235 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 1.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **mimalloc**: it moved **8.2%** between runs while its own samples never spread more than **8.4%** within one.

## debian / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.990** | 0.975 | 1.004 | 2.9% | 1.1%–4.0% | 2/2 | 3.503  (1.47–5.54) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 0.8%–3.4% | 1/3 | 1.000 |
| mimalloc | `rust-global` | **1.041** | 0.878 | 1.203 | 31.2% | 1.0%–5.0% | 3/1  | 3.649 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **jemalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **mimalloc**: it moved **31.2%** between runs while its own samples never spread more than **5.0%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-03T00:24:20Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `74dc127` | [`33699176109`](https://github.com/Azathothas/alloc-bench/actions/runs/33699176109) |
| 2026-09-02T12:28:10Z | Intel(R) Xeon(R) Processor @ 2.80GHz | 4 | `Linux 6.18.44-fc-v22` | `78df0fe` | local |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
