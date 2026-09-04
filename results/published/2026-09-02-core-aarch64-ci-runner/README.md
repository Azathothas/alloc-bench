# `core` on alpine/aarch64 -  the first aarch64 measurement this project has

Every number this project had published before this one was x86_64. The
architecture was declared, planned for, and **unmeasurable**: the first aarch64
dispatch (2026-09-01, run
[`33500081741`](https://github.com/Azathothas/alloc-bench/actions/runs/33500081741))
built six cells and the identity gate correctly rejected all six, because
static-PIE does not exist on `aarch64-unknown-linux-musl`.

**6 measurable cells, 6 `ok`, 2 `unsupported` with reasons, 0 validator errors.**
Native -  not emulated, which the run refuses to rank.

## Conditions

| | |
| --- | --- |
| run | `bench` [`33582107102`](https://github.com/Azathothas/alloc-bench/actions/runs/33582107102), job `aarch64`, `success` |
| `git_commit` | `31476973fae90d40d3a7e562c41b855387a6b986` |
| host | `ubuntu-24.04-arm`, **Neoverse-N2**, 4 cores, 1 thread/core, kernel `Linux 6.17.0-1022-azure` |
| `run.json` `cpu_model` | `aarch64 CPU part 0xd49` -  the raw `/proc/cpuinfo` string. `conditions.txt` carries `lscpu`'s `Neoverse-N2` |
| runtime | docker 28.0.4 |
| samples | 8 per workload |
|  allocator flags | taken **before** `pic_cflags` gained `-fno-PIE` on 2026-09-02. These cells are PIC=0 (`static-lto`) and were built with `-O3 -fno-PIC`, which each cell's `build_flags` records. A later aarch64 run will use `-O3 -fno-PIC -fno-PIE` and its numbers are not required to match this one to the last digit |
| profile | **`static-lto`**, not `static-pie-lto` - see below |

##  This is NOT the same build as the x86_64 `core` rows

`core` on x86_64 runs `static-pie-lto`. On aarch64 it runs **`static-lto`**,
because static-PIE does not exist for that target: rustc leaves
`static-position-independent-executables` unset in the
`aarch64-unknown-linux-musl` target definition and emits `-static -no-pie`.
[`../../../experiments/70-aarch64-static-pie.sh`](../../../experiments/70-aarch64-static-pie.sh)
is the measurement; [`../../../docs/history/todo/platform.md`](../../../docs/history/todo/platform.md) `T-002` is
the decision.

 **So these binaries buy no ASLR, and the report says so rather than implying
otherwise.** Its own table reads **1 of 6 distinct load addresses, randomised
false**, for all six cells - the expected behaviour of a non-PIE executable, and
the honest cost of measuring this architecture at all.

 **Ratios never cross a profile group**, so nothing here is compared with an
x86_64 row by machinery. A reader can, and should not.

## The numbers

`alpine / aarch64 / static-lto / distro`, workload `literal`, against musl's own
allocator:

| allocator | time | MAD | peak RSS | binary MiB | rel size |
| --- | --- | --- | --- | --- | --- |
| jemalloc | **0.765×** | 2.9% | 1.569× | 12.30 | 1.910× |
| rpmalloc | **0.787×** | 2.9% | **1.127×** | 6.83 | 1.060× |
| mimalloc | 0.923× | 2.1% | 5.075× | 6.68 | 1.036× |
| snmalloc | 0.988× | 2.5% | 1.892× | 6.99 | 1.085× |
| system *(control)* | 1.000× | 1.1% | 1.000× | 6.44 | 1.000× |
| hardened_malloc | 1.106× | 1.3% | 3.702× | 6.46 | 1.002× |

`mesh` and `tcmalloc` are `unsupported` with their reasons, as everywhere.

##  What this does to the project's one surviving claim

`docs/AGENTS.md` §11.1 says the ordering does not transfer between machines and
that **exactly one** claim has held on every machine measured: *jemalloc and
rpmalloc beat musl's allocator*. Three x86_64 machines supported it.

 **A fourth machine - and a second architecture - supports it again**, and
here they are the top two, by 21–24%.

 **And the rest disagrees again, as expected.** snmalloc lands at **0.988×** -
a fourth distinct position for it across four machines (0.595×, 0.553×, 1.138×,
0.988×), and here it is inside its own 2.5% MAD of the control, which this
project reports as **no result**. mimalloc is 0.923×.

 **Do not read this as "aarch64 agrees with the sandbox".** It is a different
profile on a different architecture on a different machine, and only the
jemalloc/rpmalloc claim is being compared across them.

 **Peak RSS does not transfer here either.** mimalloc is **5.08×** the control
against 3.45× on the sandbox; hardened_malloc 3.70× against 2.85×. rpmalloc
stays cheapest at 1.13×, as it was on the sandbox and unlike on the x86_64 CI
runner where it was 8.01×.
