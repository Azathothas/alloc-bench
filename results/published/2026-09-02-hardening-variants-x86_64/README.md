# `hardening-variants` - what hardened_malloc's own `light` build buys back

`HM_VARIANT` has been plumbed through the recipe and the allocator cache key
since this project began, and `variants` sat on the allocator spec being parsed
and never read. No suite could set either, so  **only the default
configuration had ever been built** - the project reported hardened_malloc as
the slowest row in **three of its four** `core` datasets without ever building
the configuration upstream ships for exactly that trade-off.

 **Three of four, not four** - corrected during this session's own review of
this file. In `core` run B hardened_malloc is **0.890×** and ranks 5 of 6; the
*control* is the slowest row there. It is slowest in run A (1.075×), on the CI
runner (1.225×) and on aarch64 (1.106×).  The stronger sentence was written
here first and was not true of the data this repository already held.

3 cells: the control, and hardened_malloc twice. **3 `ok`, 0 validator errors**,
10 samples.  **Run twice from the same commit**; run B is in
[`../2026-09-02-hardening-variants-x86_64-run-b/`](../2026-09-02-hardening-variants-x86_64-run-b/)
and the two are compared below, because one of the three claims does not
survive the second run.

 **THIS IS NOT A SECURITY MEASUREMENT.** `light` turns mitigations off. What
it turns off is upstream's own table below; whether any of them work is a
question this project makes **no claim about**. Time, memory and size are all
that is measured.

## What `light` changes - upstream's own config, diffed

`config/default.mk` against `config/light.mk` at the pinned commit
`1d7fc7ffe0f8`, five settings and nothing else:

| setting | `default` | `light` |
| --- | --- | --- |
| `CONFIG_WRITE_AFTER_FREE_CHECK` | true | **false** |
| `CONFIG_SLOT_RANDOMIZE` | true | **false** |
| `CONFIG_SLAB_QUARANTINE_RANDOM_LENGTH` | 1 | **0** |
| `CONFIG_SLAB_QUARANTINE_QUEUE_LENGTH` | 1 | **0** |
| `CONFIG_GUARD_SLABS_INTERVAL` | 1 | **8** |

 **Two quarantines to zero and guard slabs from every slab to every eighth**
is what the memory column below is measuring.

## Run A

| row | time (s) | `rel` | MAD | peak RSS | `rel` RSS |
| --- | --- | --- | --- | --- | --- |
| hardened_malloc **`light`** | 0.0441 | **0.729×** | 4.8% | 5.38 MiB | **1.178×** |
| system *(control)* | 0.0605 | 1.000× | 4.1% | 4.57 MiB | 1.000× |
| hardened_malloc | 0.0656 | 1.084× | 1.2% | 13.13 MiB | **2.875×** |

##  What survives BOTH runs, and the one claim that does not

| claim | run A | run B | verdict |
| --- | --- | --- | --- |
| `light` is faster than `default` | **+48.7%** | **+50.9%** |  far outside every MAD in both |
| `light` beats the control | 0.729× | 0.665× |  outside the MADs in both |
| `light` peak RSS | **1.178×** | **1.178×** |  identical to three decimals |
| `default` peak RSS | **2.875×** | **2.875×** |  identical to three decimals |
| `default` is *slower* than the control | 1.084×  | **1.003×**  |  **not established** |

 **The two runs disagree about whether the default configuration is slower
than musl's allocator at all.** Run A puts it at 1.084× against MADs of 1.2% and
4.1% - outside, a result. Run B puts it at **1.003×**, level with the control
and well inside its own 2.1% and 1.0%.  Do not quote a slowdown for
hardened_malloc's default from this dataset. (The `core` suite is no more
settled: 1.075×, 0.890× and 1.225× on three machines.)

 **Memory is the reliable axis, and it is the large one.** The two variants
came out at **1.178×** and **2.875×** of the control in *both* runs, to three
decimals - a **2.44× reduction** in peak RSS from turning off the quarantines
and thinning the guard slabs. Nothing else here is that stable.

 **Binary size is not the axis.** `light` is 8 565 368 bytes against
`default`'s 8 565 344 - **24 bytes apart**, and in the same direction in both
runs. These are `-D` values, not code paths, so the runtime and memory effects
arrive with essentially no change in size.

 **Run B's host was slower across the board** - the control alone went 0.0605 s
→ 0.0768 s - which is why the *ratios* above agree far better than the absolute
times, and why the ratios are what is quoted.

## Conditions

| | |
| --- | --- |
| run id | `20260902-073754`, started 2026-09-02T07:37:54Z |
| `git_commit` | `3ce29e999b9d02093ca68aec67806df636d80b5d`, reachable from `main` |
| `git_dirty` | **false** |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
| samples | 10 per workload |
| run B | `20260902-074405`, same commit, same host, ~6 minutes later |

 **4 validator warnings, all `noisy`.**

##  The control appears once, on purpose

`system` declares no variants, so the suite yields **one** control cell rather
than one per variant.  That is what makes the two hardened_malloc rows
comparable *with each other*: both ratios are taken against the same binary. A
`system-light` cell would be a control no recipe could build and would leave the
`light` row with nothing to be a ratio against.

 **And both rows land in the same comparison group**, so the variant had to
reach the row label - otherwise the table prints `hardened_malloc` twice,
identically, with different numbers. That was caught by reading the first real
`rankings.json`, which did exactly that.
