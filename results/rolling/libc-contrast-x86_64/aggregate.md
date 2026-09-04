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

 **The ordering does not transfer** in `alpine / x86_64 / static-pie / distro`. 4 allocator(s) changed rank between runs: **hardened_malloc**, **mimalloc**, **rpmalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **hardened_malloc**, **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `archlinux / x86_64 / static-pie / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **rpmalloc**, **snmalloc**. **No ordering is published for this group.**

 **The ordering does not transfer** in `debian / x86_64 / static-pie / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**, **snmalloc**. **No ordering is published for this group.**

 **The ordering does not transfer** in `ubuntu / x86_64 / static-pie / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**, **snmalloc**. **No ordering is published for this group.**

 **The ordering does not transfer** in `void / x86_64 / static-pie / distro`. 4 allocator(s) changed rank between runs: **hardened_malloc**, **jemalloc**, **rpmalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **hardened_malloc**, **mimalloc**, **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

 **The ordering does not transfer** in `wolfi / x86_64 / static-pie / distro`. 3 allocator(s) changed rank between runs: **hardened_malloc**, **jemalloc**, **mimalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **hardened_malloc**, **mimalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / static-pie / distro`: **jemalloc, rpmalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
  -  **below the control every run but never by more than that run's own MAD:** **mimalloc**. Not counted above: a lead smaller than the run's own spread is no result.
- `archlinux / x86_64 / static-pie / distro`:  **no allocator beat the control in every run.**
- `debian / x86_64 / static-pie / distro`:  **no allocator beat the control in every run.**
- `ubuntu / x86_64 / static-pie / distro`:  **no allocator beat the control in every run.**
- `void / x86_64 / static-pie / distro`: **jemalloc, rpmalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.
- `wolfi / x86_64 / static-pie / distro`: **jemalloc** beat the control in all 2 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| rpmalloc | `rust-global` | **0.749** | 0.638 | 0.860 | 29.6% | 0.7%–8.5% | 1/3  | 2.907  (1.07–4.75) |
| jemalloc | `rust-global` | **0.752** | 0.638 | 0.865 | 30.2% | 0.9%–3.8% | 2/2 | 2.328  (1.62–3.04) |
| mimalloc | `rust-global` | **0.823** | 0.650 | 0.997 | 42.2% | 0.8%–2.1% | 3/4  | 3.262 |
| snmalloc | `rust-global` | **0.889** | 0.619 | 1.160 | 60.7% | 2.2%–3.9% | 5/1  | 1.619 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.9%–2.4% | 4/6 | 1.000 |
| hardened_malloc | `rust-global` | **1.086** | 0.919 | 1.253 | 30.7% | 1.3%–2.2% | 6/5  | 3.423  (2.88–3.97) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 3, 5.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **rpmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **60.7%** between runs while its own samples never spread more than **3.9%** within one.

## archlinux / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.1%–2.4% | 1/1 | 1.000 |
| rpmalloc | `rust-global` | **1.068** | 1.053 | 1.083 | 2.8% | 0.6%–4.2% | 3/2  | 4.955  (1.04–8.87) |
| jemalloc | `rust-global` | **1.098** | 1.036 | 1.160 | 11.3% | 1.1%–4.1% | 2/5  | 3.421  (1.50–5.34) |
| mimalloc | `rust-global` | **1.200** | 1.147 | 1.253 | 8.8% | 2.2%–7.2% | 4/4 | 3.539 |
| snmalloc | `rust-global` | **1.253** | 1.145 | 1.361 | 17.2% | 1.5%–7.1% | 5/3  | 2.110  (1.39–2.83) |
| hardened_malloc | `rust-global` | **1.761** | 1.564 | 1.957 | 22.3% | 1.5%–3.3% | 6/6 | 4.717  (2.54–6.90) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 0.** It did not move across this window.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **rpmalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **hardened_malloc**: it moved **22.3%** between runs while its own samples never spread more than **3.3%** within one.

## debian / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 0.5%–3.6% | 1/1 | 1.000 |
| jemalloc | `rust-global` | **1.030** | 1.029 | 1.031 | 0.2% | 1.4%–2.7% | 2/4  | 3.520  (1.50–5.54) |
| rpmalloc | `rust-global` | **1.037** | 1.008 | 1.065 | 5.5% | 0.9%–1.8% | 3/3 | 5.121  (1.05–9.19) |
| mimalloc | `rust-global` | **1.175** | 1.094 | 1.255 | 13.7% | 1.9%–6.0% | 4/5  | 3.657 |
| snmalloc | `rust-global` | **1.198** | 1.007 | 1.390 | 32.0% | 1.9%–3.4% | 5/2  | 2.184  (1.43–2.94) |
| hardened_malloc | `rust-global` | **1.646** | 1.569 | 1.724 | 9.4% | 2.2%–3.4% | 6/6 | 4.877  (2.59–7.17) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 0.** It did not move across this window.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **rpmalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **32.0%** between runs while its own samples never spread more than **3.4%** within one.

## ubuntu / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.0%–6.0% | 1/1 | 1.000 |
| jemalloc | `rust-global` | **1.047** | 1.013 | 1.082 | 6.5% | 0.9%–9.4% | 2/4  | 3.425  (1.47–5.38) |
| rpmalloc | `rust-global` | **1.065** | 1.048 | 1.081 | 3.2% | 0.7%–1.1% | 3/3 | 4.962  (1.01–8.91) |
| mimalloc | `rust-global` | **1.209** | 1.164 | 1.254 | 7.4% | 0.8%–4.8% | 4/5  | 3.550 |
| snmalloc | `rust-global` | **1.225** | 1.074 | 1.376 | 24.6% | 3.0%–3.9% | 5/2  | 2.120  (1.38–2.86) |
| hardened_malloc | `rust-global` | **1.656** | 1.528 | 1.785 | 15.5% | 0.9%–6.0% | 6/6 | 4.739  (2.54–6.94) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 0, 0.** It did not move across this window.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **rpmalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **24.6%** between runs while its own samples never spread more than **3.9%** within one.

## void / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| rpmalloc | `rust-global` | **0.726** | 0.580 | 0.873 | 40.3% | 2.2%–3.3% | 2/1  | 4.501  (1.13–7.87) |
| jemalloc | `rust-global` | **0.754** | 0.655 | 0.853 | 26.2% | 1.1%–5.6% | 1/3  | 3.566  (1.66–5.47) |
| mimalloc | `rust-global` | **0.847** | 0.668 | 1.026 | 42.2% | 1.4%–3.4% | 4/4 | 3.372 |
| snmalloc | `rust-global` | **0.871** | 0.601 | 1.141 | 62.0% | 0.8%–1.2% | 5/2  | 2.151  (1.62–2.69) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 2.1%–6.5% | 3/6 | 1.000 |
| hardened_malloc | `rust-global` | **1.090** | 0.946 | 1.234 | 26.5% | 1.9%–2.2% | 6/5  | 4.590  (3.03–6.15) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 5.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **rpmalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **62.0%** between runs while its own samples never spread more than **1.2%** within one.

## wolfi / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.746** | 0.629 | 0.863 | 31.4% | 1.2%–3.0% | 1/2  | 3.606  (1.73–5.48) |
| mimalloc | `rust-global` | **0.812** | 0.602 | 1.021 | 51.7% | 1.2%–2.5% | 3/1  | 3.824  (3.04–4.61) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 2.2%–4.5% | 2/4 | 1.000 |
| hardened_malloc | `rust-global` | **1.114** | 0.993 | 1.235 | 21.7% | 1.6%–4.8% | 4/3  | 4.687  (3.29–6.09) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 1, 3.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **mimalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **mimalloc**: it moved **51.7%** between runs while its own samples never spread more than **2.5%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-03T06:51:52Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `28f3d93` | [`33723379020`](https://github.com/Azathothas/alloc-bench/actions/runs/33723379020) |
| 2026-09-03T03:50:21Z | Intel(R) Xeon(R) Processor @ 2.10GHz | 4 | `Linux 6.18.44-fc-v24` | `eb689d4` | local |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
