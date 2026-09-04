# `libc-contrast` - three musl distributions and three glibc distributions

**36 cells, 10 samples each. 34 `ok`, 2 `build_failed` with reasons, 0
unsupported, 0 validator errors.**

The first run in this project that can say anything about a **libc** rather than
about a distribution. Every earlier musl-versus-glibc claim here rested on
Alpine versus Debian.

| libc | distributions | package manager / compiler |
| --- | --- | --- |
| musl | `alpine`, `void`, `wolfi` | apk / gcc 15, xbps / gcc 14, apk / gcc 16 |
| glibc | `debian`, `ubuntu`, `archlinux` | apt / gcc 14, apt / gcc 14, pacman / gcc 16 |

One profile (`static-pie`), one mechanism (`rust-global`), so no cell is
unsupported for a reason unrelated to the distribution.

## Conditions

| | |
| --- | --- |
| run id | `20260903-035021`, started 2026-09-03T03:50:21Z |
| `git_commit` | `eb689d42d153…` |
| `git_dirty` / `git_untracked` | **false** / **0** |
| host | `Intel(R) Xeon(R) Processor @ 2.10GHz`, 4 cores, kernel `Linux 6.18.44-fc-v24` |
| runtime | docker 29.3.1 |
| corpus | `standard`, seed 20260901 |
| suite | `libc-contrast`, `--arch x86_64`, 10 repetitions |

##  The answer, per libc

**Lower is better.** A candidate "beat" a distribution only when its lead
exceeded that cell's own MAD; anything smaller is a tie.

### musl - jemalloc and mimalloc, in all three

| allocator | won | median | range | peak RSS |
| --- | --- | --- | --- | --- |
| **jemalloc** | **3 of 3** | **0.638×** | 0.629–0.655× | 1.616–1.735× |
| **mimalloc** | **3 of 3** | **0.650×** | 0.602–0.668× | 3.470–4.606× |
| rpmalloc | 2 of 2 measured | 0.609× | 0.580–0.638× | **1.068–1.132×** |
| snmalloc | 2 of 2 measured | 0.610× | 0.601–0.619× | 1.520–1.617× |
| hardened_malloc | 2 of 3 (ties on wolfi) | 0.946× | 0.919–0.993× | 2.875–3.287× |

 **jemalloc is the answer if you want one number**: it beat the system
allocator on all three musl distributions by 34–37%, at 1.6–1.7× the control's
peak RSS. mimalloc matched it on speed and costs **3.5–4.6×** the memory.

 **rpmalloc is the answer if memory is the constraint**: 0.580–0.638× the time
at **1.07–1.13×** the peak RSS - the only candidate whose memory cost is close
to free.  It could not be built on wolfi (below), so it has two distributions,
not three.

### glibc -  nothing

| allocator | won | lost | median | range | peak RSS |
| --- | --- | --- | --- | --- | --- |
| snmalloc | – | 2 of 3 | 1.074× | 1.007–1.145× | 1.382–1.426× |
| rpmalloc | – | 2 of 3 | 1.081× | 1.008–1.083× | **1.015–1.048×** |
| jemalloc | – | 2 of 3 | 1.082× | 1.031–1.160× | 1.467–1.502× |
| mimalloc | – | **3 of 3** | 1.147× | 1.094–1.164× | 3.354–3.463× |
| hardened_malloc | – | **3 of 3** | 1.785× | 1.724–1.957× | 2.537–2.587× |

 **No allocator beat glibc's own on any of the three distributions.** The best
any of them managed was a tie on Debian. Replacing glibc's allocator, for this
application on this machine, costs between 1% and 96%.

##  What the contrast actually shows

The control's own absolute time is what separates the two libcs, not the
candidates':

| | musl (alpine / void / wolfi) | glibc (debian / ubuntu / archlinux) |
| --- | --- | --- |
| best candidate vs its control | **0.580–0.668×** | 1.007–1.164× |
| what a candidate buys | 33–42% | nothing |

**The alternatives are not fast; musl's allocator is slow.** On glibc there is
nothing left for them to win back. That conclusion was reached before with one
distribution per libc; it now holds with three each, across three package
managers and three compiler versions per side.

 **The three musl distributions do not agree on the ORDER**, only on the
direction. rpmalloc leads on Void (0.580×), snmalloc on Alpine (0.619×) and
mimalloc on Wolfi (0.602×).  So "use jemalloc on musl" is supported here and
"jemalloc is the fastest on musl" is not.

## The two `build_failed` cells, and they are one cause

Both are Wolfi, and both are the **allocator compiled against the
distribution's musl, linked by rustc against rust's own bundled `self-contained`
musl**:

| cell | undefined symbol |
| --- | --- |
| `wolfi-…-rpmalloc` | `__isoc23_strtol` |
| `wolfi-…-snmalloc` | `__gcc_personality_v0` |

Wolfi's musl carries compatibility symbols that the reference musl rustc ships
does not.  This is a real limitation of the `static-pie` + `rust-global`
combination on that distribution, not a defect in either allocator, and it is
published rather than worked around: `-C link-self-contained=no` would fix it by
changing which libc every binary links, which is not a change one distribution
gets to make for the other five. Evidence: [`evidence/`](evidence/).

 **A third Wolfi failure was fixed rather than published**, because it was
this project's: Wolfi's gcc defines `_FORTIFY_SOURCE` by default and the other
five distributions do not, so its allocator objects referenced `__memset_chk`
and `__memcpy_chk`. `allocators/lib.sh` now passes `-U_FORTIFY_SOURCE` in every
recipe, holding the dimension constant across the comparison - the same rule
that keeps allocator-internal LTO off everywhere.

##  What this run does not establish

- **That any of it transfers to another machine.** One host, one day. This
  project's central finding is that the ranking is a property of the machine;
  the same `core` comparison has produced three different orderings on three
  CPUs.
- **An ordering within a libc.** The three musl distributions each name a
  different leader.
- **Anything about the other mechanisms.** `rust-global` only: `libc-surgery`
  reaches more of the program and has beaten it in every run that measured both.
- **Anything about hardened_malloc's security.** It is slower because of what it
  does.
- **Anything about aarch64.** x86_64 only; neither Wolfi nor Void has been
  exercised on another architecture here.
