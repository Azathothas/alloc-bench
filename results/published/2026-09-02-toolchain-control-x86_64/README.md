# `toolchain-control` on x86_64 - the first numbers this project has that are not Alpine

The `toolchain-control` suite had **never been run**, and `zig` had never
compiled anything here at all: it installs in every image and was then unused.

6 cells - three distributions × {mimalloc, the control}, `static-pie`,
`TOOLCHAIN=zig`, 10 samples. **6 `ok`, 0 `build_failed`, 0 validator errors,
13 `noisy` warnings.**

 **Every measurement this project had published before today was
Alpine/musl.** Two thirds of this run is not.

##  The finding: mimalloc's musl win does not survive the move to glibc

Each allocator against **the control in its own image**, `literal`:

| distribution | libc | control | mimalloc | `rel` | lead | its MADs | §9 verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| alpine | musl | 0.0728 s | 0.0472 s | **0.649×** | 35.2% | 7.8% / 17.2% |  mimalloc |
| archlinux | glibc | 0.0403 s | 0.0413 s | **1.027×** | 2.7% *slower* | 3.4% / 5.2% |  **no result** |
| debian | glibc | 0.0424 s | 0.0412 s | **0.973×** | 2.7% faster | 4.4% / 3.3% |  **no result** |

 **On both glibc distributions the difference is inside the run's own noise**,
and it does not even agree in sign - mimalloc is nominally slower on Arch and
nominally faster on Debian. §9's rule is that a lead smaller than the run's own
MAD is no result, so this run names no winner on glibc in either direction.

 **The absolute times say why, and this is the part worth keeping.** mimalloc's
own time barely moves across three distributions while the system allocator's
moves enormously:

| | slowest | fastest | spread |
| --- | --- | --- | --- |
| the **control** | alpine 0.0728 s | archlinux 0.0403 s | **1.807×** |
| **mimalloc** | alpine 0.0472 s | debian 0.0412 s | 1.145× |

 So the gap an alternative allocator closes on Alpine is mostly **musl's
allocator being slow**, not mimalloc being fast. glibc's allocator is already
where mimalloc gets to.

 **This is one run and the Alpine control is the noisiest cell in it** (17.2%
relative MAD on `literal`, against 3.3–5.2% for the four glibc cells). The 35%
figure is therefore the *least* reliable number on this page - but it is also
the one four earlier datasets already establish. What is **new** here is the
glibc half, and that half is the tight one.

##  What this suite controls is NOT what its `why` claimed

The suite exists so that a `distros` difference is not silently a compiler
difference. Running it showed the control is **partial**, and the record now
says which half:

| | alpine | archlinux | debian |
| --- | --- | --- | --- |
| `alloc_cc` - builds the **allocator** | `clang 21.1.0` | `clang 21.1.0` | `clang 21.1.0` |
| `cc` - what **rustc linked through** | gcc 15.2.0 | **gcc 16.2.1** | **gcc 14.2.0** |

 **Three different gccs linked the three ripgreps.** `TOOLCHAIN=zig` sets
`CC`/`CXX` for the allocator recipe; rustc links through its own target default
and nothing passes `-C linker`. So the suite removes the compiler from the
*allocator*, and leaves it in the *application*.

 **That was invisible until this run.** `build.json` recorded a single field
`cc`, populated from `$CC` - so all six cells claimed `clang version 21.1.0`,
and the two baseline cells claimed it while zig had compiled **nothing** in
them, a baseline having no allocator to build. The field now splits in two, and
`alloc_cc` reads `(none: this cell builds no allocator)` where that is the truth.

 **Read against [`T-007`](../../../docs/history/todo/measurement.md), this bounds what
`distros` can conclude**: a difference this suite reproduces is not attributable
to the libc alone, because the application compiler moved too.

##  And `zig cc` silently ignores `-static-pie`

Probed in the Alpine image before trusting the toolchain, zig 0.16.0:

| invocation | result | bytes |
| --- | --- | --- |
| *(no flags)* | dynamic | 6 928 |
| `-static` | static | 138 008 |
| **`-static-pie`** |  **dynamic** | **6 928** |
| `-static -pie` |  static-pie | 142 224 |

The `-static-pie` binary is byte-for-byte the size of the one built with no
flags, and keeps `/lib/ld-musl-x86_64.so.1` as its interpreter. zig's clang
driver does not know the flag - it is absent from `zig cc --help` - and reports
`warning: argument unused during compilation`, which reads like a harmless note.

 **No cell here is affected**, precisely because rustc does the link. The trap
is armed for whoever wires zig as the Rust linker.

##  The Debian image could never have built

Its first build ever, and it failed before installing a single package:

```
/bin/sh: 1: cannot create /etc/ssl/certs/ca-certificates.crt: Directory nonexistent
```

`debian:latest` has **no `/etc/ssl` at all** until `ca-certificates` is
installed. Alpine and Arch both ship the directory, which is why an identical
extra-CA block in three Dockerfiles survived until Debian was first built.
Probed rather than guessed (`docker run --rm debian:latest ls -la /etc/ssl`),
and fixed in all three so they stay identical.

## Conditions

| | |
| --- | --- |
| run id | `20260902-070731`, started 2026-09-02T07:07:31Z |
| `git_commit` | `970bcbd0bac7a721ff1d51fa0ecba85eaede2f53`, reachable from `main` |
|  `git_dirty` | **false** - and this is the first snapshot that records it |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
| samples | 10 per workload |

 **`git_dirty` exists because of this run.** An earlier attempt at the same six
cells was measured from a tree carrying the Dockerfile fix uncommitted, and
recorded a real, reachable `git_commit` that had not produced its binaries -
`git rev-parse HEAD` is blind to the working tree. That dataset was discarded
rather than published, the field was added, and these cells were re-measured
from a committed tree. `scripts/check-snapshots.py` now refuses a `git_dirty:
true` snapshot whose README does not own up to it.

 **Full disclosure on that field for this run:** it is sampled when the run
starts, and the tree was clean then. Four **markdown** files were edited ten
minutes in, while cells 2–6 were building - `docs/troubleshooting.md`,
`docs/static-linking.md`, `docs/allocator-integration.md` and
`docs/history/todo/measurement.md`. None is read by any build step, so no binary here differs
from `970bcbd`; it is recorded because the alternative is a reader discovering
it from timestamps.

 **Host quiescence:** the three images were built at the start of the run, all
before the first measurement, and nothing else of this session ran on the host
during the cells.  That does not explain the 17.2% MAD on the Alpine control,
and nothing here does - it is reported, not accounted for.

## The rest of what it measured

 **ASLR: 6 distinct load addresses in 6 samples, in all six cells** - including
the glibc static-PIE binaries, which this project had never built before.

 **Peak RSS is the one thing that transfers.** mimalloc costs **3.36–3.47×**
the control's peak RSS in every distribution - 4.57 → 15.84 MiB on alpine,
5.58 → 18.76 on archlinux, 5.40 → 18.75 on debian. Binary size grows by
**1.11–1.12 MiB** everywhere, equally consistently.

 **13 validator warnings, all `noisy`**, spread across all six cells and every
workload. This run is materially noisier than the `profiles` run on the same
host the same morning (3.3–17.2% here against 0.7–9.6% there), and the reason is
not established.
