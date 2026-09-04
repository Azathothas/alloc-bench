# `preload`, all eight allocators - and the first numbers Mesh, rpmalloc and hardened_malloc have ever produced through this mechanism

**16 cells, 10 samples each. 14 `ok`, 2 `unsupported` with reasons, 0
`build_failed`, 0 validator errors, 21 `noisy` warnings.**

 **Three allocators appear here for the first time.**

| allocator | why it had no preload number before | what changed |
| --- | --- | --- |
| **mesh** | its build was reported as producing "no library at all" on both distributions, run after run |  **it always produced one.** mesh's `CMakeLists.txt` redirects `CMAKE_LIBRARY_OUTPUT_DIRECTORY` into the **source** tree, and the recipe searched only the directory it passed to `-B`. [`experiments/100-mesh-artefacts.sh`](../../../experiments/100-mesh-artefacts.sh) |
| **rpmalloc** | `allocators.toml` declared `preload`; the recipe refused it, accurately, as this project's gap | implemented with `ENABLE_PRELOAD=1`, which rpmalloc requires for a library loaded into a process that knows nothing about it |
| **hardened_malloc** | the same | implemented by linking the archive's own objects with upstream's own rule |

 **And the suite had to change too**, which is the more interesting half: all
three were *declared* in `allocators.toml` and the `preload` suite listed six of
eight allocators, so **no cell paired any of them with the mechanism** and
nothing ever took the path. `plan --suite preload --arch x86_64` went from 12
cells to 16. A declared capability that no cell exercises is indistinguishable
from one that works.

## Conditions

| | |
| --- | --- |
| run id | `20260903-003445`, started 2026-09-03T00:34:45Z |
| `git_commit` | `b5baa3a9e4d7c02cc9b26e15ee0d1d6bb0aa1b5f` |
| `git_dirty` / `git_untracked` | **false** / **0** |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v24` |
| runtime | docker 29.3.1 |
| corpus | `standard`, seed 20260901 |
| suite | `preload`, `--arch x86_64`, 10 repetitions |

 **Quiescence:** no container build, `cargo` invocation or other benchmark
overlapped the measured cells. Documents were edited alongside; nothing heavier.

 **That commit is reachable, and it took a merge rather than a rebase to keep
it so.** `bench.yml`'s `distros` dispatch finished while this run was measuring
and its `roll` job pushed to `main`, so the local branch had to take the remote
commit. A rebase would have rewritten `b5baa3a` into a different sha and left
this file naming a commit `git cat-file` could not resolve - which is precisely
what happened to `e24709b` and what
[`T-012`](../../../docs/history/todo/instrument.md) exists to prevent. It was merged instead.

##  The headline: five of six beat musl's allocator, five of six lose to glibc's, and both exceptions are ties

`alpine / x86_64 / dynamic / distro`, workload `literal`, **lower is better**:

| allocator | vs control | its MAD | peak RSS vs control |
| --- | --- | --- | --- |
| snmalloc | **0.601×** (39.9% faster) | 3.9% | 1.529× |
| mimalloc | **0.617×** (38.3% faster) | 2.1% | 3.265× |
| **mesh** | **0.636×** (36.4% faster) | 3.6% | **1.339×** |
| jemalloc | **0.656×** (34.4% faster) | 3.1% | 1.338× |
| **rpmalloc** | **0.741×** (25.9% faster) | 5.0% |  **1.086×** |
| system *(control)* | 1.000× | 3.3% | 1.000× |
| **hardened_malloc** | 1.008×  ≈ control | 1.7% | 2.749× |

`debian / x86_64 / dynamic / distro`:

| allocator | vs control | its MAD | peak RSS vs control |
| --- | --- | --- | --- |
| system *(control)* | 1.000× | 5.0% | 1.000× |
| snmalloc | 1.028×  ≈ control | 3.6% | 1.335× |
| mimalloc | 1.194× (19.4% slower) | 2.9% | 3.070× |
| **rpmalloc** | 1.199× (19.9% slower) | 3.6% | **1.010×** |
| jemalloc | 1.217× (21.7% slower) | 1.9% | 1.247× |
| **mesh** | 1.250× (25.0% slower) | 2.3% | 1.252× |
| **hardened_malloc** |  **2.108×** (110.8% slower) | 0.9% | 2.438× |

 **Symmetric, and the exceptions are the same shape on both sides.** Five of
the six candidates beat musl's allocator by 26–40% and the sixth
(hardened_malloc, 1.008× against a 1.7% MAD) **ties** it; five of the six lose
to glibc's by 19–111% and the sixth (snmalloc, 1.028× against 3.6%) **ties**
it.  Neither tie is counted as a win or a loss: §9's rule is that a difference
smaller than the cell's own MAD is no result, and the tables above mark both
rows ` ≈ control` rather than printing a percentage. The previous `preload`
run reached this conclusion with three allocators; this one reaches it with six,
including two that had never run at all.

 **hardened_malloc's `2.108×` is the largest slowdown this project has
measured anywhere**, and it is against a **0.9%** MAD - the tightest cell in the
run.  That is what hardened_malloc is *for*: slab canaries, guard slabs,
quarantines and zero-on-free. This project makes no claim about whether those
mitigations work.  The interesting half is the contrast: the same allocator is
**level with the control on musl** (1.008×, inside its own 1.7% MAD), because
musl's allocator is slow enough to erase the whole cost.

 **rpmalloc is the memory answer.** 1.086× on musl and **1.010×** on glibc -
essentially free - where mimalloc costs 3.07–3.27× for a result that is not
better on either libc. A memory-capped container ranks these differently from a
latency-bound one, which is why every component is published separately.

 **Mesh's first number is a good one and it is one machine.** 0.636× on musl is
third of six; 1.250× on glibc is second-worst. Nothing here has been repeated.

## The two `unsupported` rows, and they are different kinds

| cell | reason |
| --- | --- |
| `alpine-…-tcmalloc-preload` |  **upstream's**: Google tcmalloc does not support musl and says so. Not this project's gap. |
| `debian-…-tcmalloc-preload` |  **this network's**: bazelisk downloads its own JDK, whose trust store is not the image's, so it cannot fetch `bcr.bazel.build` through a TLS-inspecting proxy.  **NOT** an upstream limitation - a GitHub-runner dispatch got past it and Bazel built. |

 **So Google tcmalloc still has no number**, and the recipe changed this
session in a way this run could not exercise: upstream declares **no
shared-library target at all** - 0 occurrences of `cc_shared_library` and 0 of
`linkshared` across all four of its BUILD files - so the recipe now generates a
`cc_binary(linkshared = 1)` over `//tcmalloc`. That change is **unverified**;
only a runner without the proxy can run it. [`T-003`](../../../docs/history/todo/mechanisms.md).

##  What this run does not establish

- **That any of these numbers transfer.** The project's central finding is that
  they do not: the same comparison has produced different orderings on every
  machine it has been run on. The previous `preload` run put snmalloc at
  `0.648×` on this class of host and `1.206×` on a GitHub runner.
- **A winner in either group.** The report refuses one in both: the top two rows
  are 2.7% and 2.8% apart against 3.9% and 5.0% MADs.
- **Anything about static binaries.** A preloaded allocator arrives at load
  time; every row here is the byte-identical dynamic binary - 7.87 MiB on
  Alpine and 7.94 MiB on Debian for all seven rows. That is the property that
  makes this table clean and also the reason it says nothing about the static
  mechanisms.
- **Anything about hardened_malloc's security.** See above.

## How each `ok` row was proven to be what it says

A preload cell's allocator is **not in its binary**, so the ELF oracle can only
establish that the binary is the plain system build it claims to be. The
identity claim is residency, read from `/proc/<pid>/maps` of the running
subject: **every `ok` cell is 4 of 4 sampled runs resident with `LD_PRELOAD` and
0 of 4 without.** The report's "Preloaded libraries, observed resident" table
carries every row, and  that table now states that its two columns are read in
**opposite** directions - the left one wants 4 of 4 and the right one wants 0.

## Files

`report.md` (regenerated with the direction-of-goodness work of
[`T-015`](../../../docs/history/todo/instrument.md)), `rankings.json`, `run.json`,
`plan.json`, `validation.txt`, `results/`, and the six charts.  No `cells/` or
`logs/`: a whole dataset is tens of megabytes.
