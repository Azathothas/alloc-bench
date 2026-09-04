# Rolling aggregate

The last **1** run(s) of this suite, on **1** distinct CPU model(s). Primary workload `literal`.

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

 **One run.** Nothing here is an aggregate yet: there is no second measurement to disagree with it. Every figure below is one machine on one day.

## What survives every run in the window

- `alpine / aarch64 / static-lto / distro`: **jemalloc, mimalloc, rpmalloc** beat the control in all 1 run(s), by more than that run's own MAD each time.
  -  **below the control every run but never by more than that run's own MAD:** **snmalloc**. Not counted above: a lead smaller than the run's own spread is no result.

## alpine / aarch64 / static-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.765** | 0.765 | 0.765 | 0.0% | 2.9% | 1 | 1.569 |
| rpmalloc | `rust-global` | **0.787** | 0.787 | 0.787 | 0.0% | 2.9% | 2 | 1.127 |
| mimalloc | `rust-global` | **0.923** | 0.923 | 0.923 | 0.0% | 2.1% | 3 | 5.075 |
| snmalloc | `rust-global` | **0.988** | 0.988 | 0.988 | 0.0% | 2.5% | 4 | 1.892 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 1.1% | 5 | 1.000 |
| hardened_malloc | `rust-global` | **1.106** | 1.106 | 1.106 | 0.0% | 1.3% | 6 | 3.702 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-02T02:09:47Z | aarch64 CPU part 0xd49 | 4 | `Linux 6.17.0-1022-azure` | `3147697` | [`33582107102`](https://github.com/Azathothas/alloc-bench/actions/runs/33582107102) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
