# Rolling aggregate

The last **6** run(s) of this suite, on **4** distinct CPU model(s). Primary workload `literal`.

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

 **The ordering does not transfer** in `alpine / x86_64 / static-pie-lto / distro`. 4 allocator(s) changed rank between runs: **jemalloc**, **mimalloc**, **rpmalloc**, **snmalloc**. **No ordering is published for this group.**

 **Changed which side of the control they sit on:** **mimalloc**, **snmalloc**. A recommendation naming one of these is a statement about a machine, not about the allocator.

## What survives every run in the window

- `alpine / x86_64 / static-pie-lto / distro`: **jemalloc, rpmalloc** beat the control in all 6 run(s), by more than that run's own MAD each time.

## alpine / x86_64 / static-pie-lto / distro

| allocator | mech | rel median ↓ | rel min ↓ | rel max ↓ | between-run spread ↓ | within-run MAD ↓ | rank | RSS rel ↓ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| jemalloc | `rust-global` | **0.866** | 0.846 | 0.889 | 5.0% | 0.8%–1.8% | 2/1/1/2/1/1  | 3.364  (1.58–5.52) |
| rpmalloc | `rust-global` | **0.868** | 0.798 | 0.908 | 12.7% | 0.8%–2.6% | 1/2/2/1/2/2  | 4.480  (1.09–7.91) |
| system *(control)* | `baseline` | **1.000** | 1.000 | 1.000 | 0.0% | 0.8%–3.4% | 3/3/4/4/3/3 | 1.000 |
| mimalloc | `rust-global` | **1.012** | 0.990 | 1.024 | 3.4% | 0.3%–3.1% | 4/4/3/5/4/4  | 3.474  (3.04–3.93) |
| snmalloc | `rust-global` | **1.125** | 0.992 | 1.166 | 15.5% | 1.1%–10.5% | 5/5/5/3/5/5  | 2.095  (1.51–2.72) |
| hardened_malloc | `rust-global` | **1.232** | 1.207 | 1.300 | 7.6% | 1.0%–4.1% | 6/6/6/6/6/6 | 4.497  (2.85–6.16) |

 **`rank` is this cell's position in each run, newest first**, fastest = 1. A candidate marked  moved, and a moved rank is why no ordering is claimed.

 **The control's own position is how many allocators beat it that run: 2, 2, 3, 3, 2, 2.** That number moving is the same finding as the rank changes above, stated as a count.

 **Peak RSS does not transfer either**, for **hardened_malloc**, **jemalloc**, **mimalloc**, **rpmalloc**, **snmalloc**. A memory-capped deployment cannot be sized from the median column alone; the range is the honest figure.

 **The within-run MAD is a floor on the uncertainty, not a bound.** The widest cell here is **snmalloc**: it moved **15.5%** between runs while its own samples never spread more than **10.5%** within one.

## The runs in this window

| started | CPU | cores | kernel | commit | CI run |
| --- | --- | --- | --- | --- | --- |
| 2026-11-05T10:59:31Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `5218b16` | [`42014989721`](https://github.com/Azathothas/alloc-bench/actions/runs/42014989721) |
| 2026-11-02T11:13:22Z | AMD EPYC 9V45 96-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `eebb121` | [`41434684550`](https://github.com/Azathothas/alloc-bench/actions/runs/41434684550) |
| 2026-10-29T10:02:52Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 7.0.0-1017-azure` | `5b1f83a` | [`40853952902`](https://github.com/Azathothas/alloc-bench/actions/runs/40853952902) |
| 2026-10-26T08:59:56Z | INTEL(R) XEON(R) PLATINUM 8573C | 4 | `Linux 6.17.0-1022-azure` | `d64c26a` | [`40295895029`](https://github.com/Azathothas/alloc-bench/actions/runs/40295895029) |
| 2026-10-22T08:40:43Z | AMD EPYC 7763 64-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `9fe050d` | [`39749224084`](https://github.com/Azathothas/alloc-bench/actions/runs/39749224084) |
| 2026-10-19T08:57:33Z | AMD EPYC 9V74 80-Core Processor | 4 | `Linux 6.17.0-1022-azure` | `75156b9` | [`39226163030`](https://github.com/Azathothas/alloc-bench/actions/runs/39226163030) |

 **A measurement carries its conditions.** Never quote a figure above without naming which of these machines it came from - and where the window spans several, the figure is a range, not a number.
