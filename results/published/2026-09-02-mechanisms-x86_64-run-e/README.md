# `mechanisms` on alpine/x86_64 - run E, where `libc-surgery` stopped being mimalloc-only

Run C established that **`libc-surgery` worked for mimalloc and no other
allocator**, because deleting musl's malloc members strands its own internal
`__libc_malloc` / `__libc_free` / `__libc_calloc` calls and mimalloc happens to
define them. This run is the same suite after
[`T-005`](../../../docs/history/todo/mechanisms.md) made the surgery supply them.

16 cells, `alpine` / `x86_64` / `static-pie`, 10 samples.
**10 `ok`, 6 `build_failed`, 0 validator errors.**

## Conditions

| | |
| --- | --- |
| run id | `20260902-021113`, started 2026-09-02T02:11:13Z |
| `git_commit` | `31476973fae90d40d3a7e562c41b855387a6b986` - reachable from `main`.  The run started before this session's later commits; the surgery and oracle changes it exercises are in that tree, the documents describing them are not |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
|  host quiescence | **not quiescent** - see below |

 **THE HOST WAS NOT IDLE DURING THIS RUN, and that is recorded because a
measurement carries its conditions (`docs/AGENTS.md` §15).** `sh scripts/gate.sh
--strict` - which builds the Rust workspace - was run once while these cells
were measuring, overlapping at most one or two of the sixteen for about two
minutes.

 **Do not treat any single cell's absolute time here as clean.** What the run
is cited for is the *within-run* comparison between two mechanisms of the same
allocator, whose margins are 12.5–37.5%; a two-minute overlap on one cell cannot
produce that, and the direction is the same for all four allocators.  But the
magnitudes are one more reason the magnitude is published as unestablished, and
a session wanting clean absolute numbers should re-run on an idle host.

##  One of five became four of five

| allocator | `rust-global` | `libc-surgery` | `link-override` |
| --- | --- | --- | --- |
| mimalloc |  0.676× |  **0.495×** |  **9** `multiple definition` |
| jemalloc |  0.681× |  **0.495×** - *was * |  |
| rpmalloc |  0.548× |  **0.468×** - *was * |  **5** `multiple definition` |
| hardened_malloc |  0.996× |  **0.886×** - *was * |  **5** `multiple definition` |
| snmalloc |  0.599× |  **a new reason** - the C++ runtime |  **5** `multiple definition` |
| system |  1.000× (control) | - | - |

Every `libc-surgery` cell above passes the identity gate with
`libc_allocator_detected: []` - the negative control confirming musl's allocator
is gone - and the correctness gate's exact needle counts.

##  The mechanism finding, no longer resting on one allocator

Until now "the surgery beats the shim" was a mimalloc claim, repeated four times,
and run D's margin fell **inside** its own MAD. Here it is four allocators in one
run, and **every margin clears that cell's own MAD**:

| allocator | `libc-surgery` | `rust-global` | shim ÷ surgery − 1 | surgery's own MAD |
| --- | --- | --- | --- | --- |
| jemalloc | 0.4954× | 0.6812× | **37.5%** | 3.4% |
| mimalloc | 0.4948× | 0.6758× | **36.6%** | 7.4% |
| rpmalloc | 0.4684× | 0.5476× | **16.9%** | 4.2% |
| hardened_malloc | 0.8855× | 0.9962× | **12.5%** | 3.8% |

 **Direction: four for four, each outside its own noise.** That is consistent
with the two mechanisms doing different things - the shim catches Rust's
allocations, the surgery catches everything the process allocates, musl's own
internal ones included.

 **The magnitude is still not established.** Across runs A–E the same mimalloc
comparison has produced 4.8%, 13%, 14%, 32%, 37%.  Publish the direction.

 **Peak RSS stays flat between the two mechanisms**, as it should if both run
the same allocator: mimalloc 3.465× vs 3.469×, rpmalloc 1.055× vs 1.068×,
jemalloc 1.370× vs 1.561×, hardened_malloc 2.902× vs 2.875×.

 **hardened_malloc is the clean illustration that the mechanism matters.** Its
shim lands on the control (0.996×, inside its 3.3% MAD - no result); its surgery
beats it (0.886×, outside its 3.8%). Same allocator, different amount of the
program reaching it.

##  snmalloc: a different wall, and it is informative

The alias problem is **solved** for snmalloc too - zero `multiple definition`,
the synthesis fired and named the same three aliases, and the surgery's
assertions passed with `malloc`/`free` provided once each by `malloc.cc.o`. What
fails is the **C++ runtime**:

```
     10 undefined reference to `__cxa_thread_atexit'
      2 undefined reference to `__gxx_personality_v0'
      2 undefined reference to `__cxa_call_terminate'
```

 **And the links that fail are cargo's own build scripts** - `libc` and
`serde_core` - which this project does not put flags on.
`allocators/snmalloc/build.sh` solves this for `rust-global` by locating
`libstdc++.a` and putting it on the ripgrep link line; a build script's link line
is not ours.

 **So `libc-surgery` looks like a C-allocator technique.** mimalloc, jemalloc,
rpmalloc and hardened_malloc are C and all four pass; snmalloc is the registry's
only C++ allocator and it is the one that fails.
[`T-013`](../../../docs/history/todo/mechanisms.md) carries it.

## `link-override` - one property explains every row

 Still fails for all five, and the symbol counts now have a complete account:

| allocator | `multiple definition` symbols |
| --- | --- |
| mimalloc | **9** - the five below **plus** `__libc_free`, `__libc_malloc`, `__libc_realloc`, `strdup` |
| jemalloc, rpmalloc, hardened_malloc, snmalloc | **5** - `aligned_alloc`, `calloc`, `free`, `posix_memalign`, `realloc` |

 **The four extra are exactly the aliases mimalloc alone defines** - the same
property that made its surgery link and everyone else's fail. One fact, both
mechanism columns, all five allocators.

## Reading `evidence/`

Six extracts, one per failing cell, written by
[`../../../scripts/report/extract-evidence.py`](../../../scripts/report/extract-evidence.py):
diagnostic lines by class, de-duplicated, every class that fired given a floor,
and a header naming the full log's byte count and what was elided.  Nothing
chosen by its position in the file.

```sh
python3 scripts/report/extract-evidence.py --check \
  results/published/2026-09-02-mechanisms-x86_64-run-e/evidence \
  --expect 'multiple definition of .__libc_malloc' --expect '__cxa_thread_atexit'
```
