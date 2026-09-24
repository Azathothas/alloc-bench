# Rolling aggregate

The last **6** run(s) of this suite, on **1** distinct CPU model(s). Primary workload `literal`.

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

 **All 6 runs landed on the same CPU model.** Agreement between them is therefore evidence about repeatability on one machine, and says nothing about whether a result transfers to another.

 **The ordering does not transfer** in `alpine / aarch64 / static-lto / distro`. 3 allocator(s) changed rank between runs: **jemalloc**, **rpmalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / aarch64 / static-lto / distro`: **jemalloc, rpmalloc** beat the control in all 6 run(s), by more than that run's own MAD each time.
  -  **below the control every run but never by more than that run's own MAD:** **mimalloc**. Not counted above: a lead smaller than the run's own spread is no result.

## alpine / aarch64 / static-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.768** | 0.721 | 0.803 | 10.6% | 0.9%–3.2% | 1/1/1/2/1/2  | 1.554 |
| rpmalloc | `rust-global` | **0.771** | 0.755 | 0.794 | 5.1% | 1.2%–2.9% | 2/2/2/1/2/1  | 1.176 |
| mimalloc | `rust-global` | **0.926** | 0.901 | 0.962 | 6.7% | 2.3%–4.3% | 3/3/3/3/3/3 | 5.168 |
| snmalloc | `rust-global` | **0.992** | 0.965 | 1.049 | 8.5% | 1.8%–4.3% | 4/4/5/4/4/4  | 1.927 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.7%–3.2% | 5/5/4/5/5/5 | 1.000 |
| hardened_malloc | `rust-global` | **1.105** | 1.076 | 1.139 | 5.7% | 1.9%–4.7% | 6/6/6/6/6/6 | 3.733 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 4, 4, 3, 4, 4, 4.** That number moving is the same finding as the rank changes above, stated as a count.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **jemalloc**: it moved **10.6%** between runs while its own samples never spread more than **3.2%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-24T08:29:40Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `ed51ec8` | [`35975475439`](https://github.com/Azathothas/alloc-bench/actions/runs/35975475439) |
| 2026-09-21T08:59:15Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `6a420a9` | [`35580691061`](https://github.com/Azathothas/alloc-bench/actions/runs/35580691061) |
| 2026-09-17T08:41:24Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `f20b844` | [`35200972464`](https://github.com/Azathothas/alloc-bench/actions/runs/35200972464) |
| 2026-09-14T08:57:33Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `4663693` | [`34825316597`](https://github.com/Azathothas/alloc-bench/actions/runs/34825316597) |
| 2026-09-10T08:10:35Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `a86d5a6` | [`34453653215`](https://github.com/Azathothas/alloc-bench/actions/runs/34453653215) |
| 2026-09-07T08:20:47Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `8ba0fdd` | [`34100027540`](https://github.com/Azathothas/alloc-bench/actions/runs/34100027540) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
