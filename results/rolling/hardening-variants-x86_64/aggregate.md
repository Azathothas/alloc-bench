# Rolling aggregate

The last **2** run(s) of this suite, on **1** distinct CPU model(s). Primary workload `literal`.

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

 **All 2 runs landed on the same CPU model.** Agreement between them is therefore evidence about repeatability on one machine, and says nothing about whether a result transfers to another.

 Every allocator held its rank across every run in this window.  That is a statement about the machines sampled so far, not a guarantee - see the CPU models listed below.

## What survives every run in the window

- `alpine / x86_64 / static-pie / distro`: **hardened_malloc (light)** beat the control in all 2 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static-pie / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hardened_malloc (light) | `rust-global` | **0.697** | 0.664 | 0.729 | 9.3% | 4.0%–4.8% | 1/1 | 1.178 |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 0.9%–4.1% | 2/2 | 1.000 |
| hardened_malloc | `rust-global` | **1.043** | 1.003 | 1.084 | 7.8% | 1.2%–2.1% | 3/3 | 2.875 |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 1, 1.** It did not move across this window.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **hardened_malloc (light)**: it moved **9.3%** between runs while its own samples never spread more than **4.8%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-09-02T07:44:05Z | Intel(R) Xeon(R) Processor @ 2.80GHz | 4 | `Linux 6.18.44-fc-v22` | `3ce29e9` | local |
| 2026-09-02T07:37:54Z | Intel(R) Xeon(R) Processor @ 2.80GHz | 4 | `Linux 6.18.44-fc-v22` | `3ce29e9` | local |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
