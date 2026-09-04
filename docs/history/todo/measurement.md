# measurement

What this project measures, and what it is entitled to say about the result.

[`INDEX.md`](INDEX.md) is the list. [`PROGRESS.md`](PROGRESS.md) is the work
order. Entries close **in place**, with the acceptance command actually run and
its output pasted underneath.

---

## T-001: Decide what the project claims, now that the ranking does not transfer

**Source:** `docs/AGENTS.md` §11.1, from the first `core` run on a GitHub runner
(CI run [`33500081741`](https://github.com/Azathothas/alloc-bench/actions/runs/33500081741)).
**Category:** measurement
**Priority:** P1
**Effort:** L
**Status:** done

### Problem

The README publishes a table of allocator ratios. `core` has been measured on
three CPUs and produced **three different orderings**. On the GitHub runner
snmalloc goes from the fastest allocator measured (0.595×) to the second slowest
(1.138×), and mimalloc lands on the control (1.004×). A reader who takes the
headline table as "which allocator is fastest" is reading a statement about one
Xeon.

### Premise

 **Measured, not read.** Three committed datasets, same suite, same lock file,
same corpus seed:

| | run A | run B | CI runner |
| --- | --- | --- | --- |
| dataset | `results/published/2026-09-01-core-x86_64/` | `…-run-b/` | `…-ci-runner/` |
| CPU | Xeon @ 2.80GHz | Xeon @ 2.10GHz | AMD EPYC 7763 (2c/4t) |
| snmalloc | 0.595× | 0.553× | **1.138×** |
| mimalloc | 0.660× | 0.577× | **1.004×** |
| within-run MAD | 2.0–8.4% | 2.0–6.4% | **0.5–1.4%** |

 **It is not noise.** The run that inverts the ordering reports the *tightest*
MADs of the three. Each machine gives a tight, self-consistent, different answer,
so a within-run statistic says nothing about whether a result transfers.

 **It is not the build.** Five of six ripgrep binaries are byte-identical
between the pre-cleanup image and the `194ed63` image; jemalloc differs by 1496
bytes in an autotools build that embeds build-time strings.

### Approach

This is a reporting-shape decision before it is a measurement task. One of three,
and the entry is not workable until the operator rules:

1. **Publish only what is invariant across machines.** Today that is exactly one
   claim: *jemalloc and rpmalloc beat musl's allocator on every machine measured.*
   Everything else becomes a per-machine appendix.
2. **Publish per-machine tables and refuse a global ranking.** `rank.rs` already
   groups by distro/arch/profile/toolchain; this adds the host as a group key so
   no ratio crosses a machine.
3. **Find the mechanism and make it a reported dimension.** Core count, SMT,
   µarch, page size, THP.  The runner is 2 physical cores + SMT against the
   sandbox's 4 - a plausible first hypothesis and **untested**.

 **What it must not do:** average the three runs into one table. That would
manufacture a ranking none of the three machines produced.

### Decision

**Recommendation: (2) now, (3) as follow-up work.** (2) is a small change to
`rank.rs`'s grouping plus the report template, it makes every published number
honest immediately, and it does not require another machine. (1) loses almost
all the project's output for a claim it can already make in prose. (3) is the
interesting answer but it is a research programme, and it is not blocked by
doing (2) first - a host-keyed table is exactly the substrate (3) needs.

 **Blocked on the operator's ruling.** Until then aarch64 ([`T-002`](platform.md))
is the better use of a session: a second architecture is a second machine class
and it sharpens whichever option is chosen.

### Prove

```sh
./target/release/alloc-bench report --run results/published/2026-09-01-core-x86_64-ci-runner
python3 - <<'EOF'
import json,sys
j=json.load(open("results/published/2026-09-01-core-x86_64-ci-runner/rankings.json"))
groups=[g["group"] for g in j["groups"]]
assert all("EPYC" in g or "host=" in g for g in groups), groups
print("OK: every ranking group names its host")
EOF
```

Passing means every ranking group in a regenerated report names the machine it
was measured on, and no table merges two hosts. Exit 0 from both commands.

### Partial, 2026-09-01: the machinery exists, the editorial decision does not

 **Option (2) is now implemented and running**, at the operator's request for a
rolling three-run window with an auto-updating aggregate.
`scripts/report/aggregate.py` keeps the last 6 runs per suite and arch under
`results/rolling/`, and `bench.yml`'s weekly `roll` job folds each new run in and
commits the regenerated aggregate to `main`.

 **It refuses an ordering rather than producing one.** Where any candidate's
rank moved between runs the aggregate publishes **no ordering** and names the
movers; the only positive claim it will make is *"beat the control in every run
in the window"*. Seeded with the three existing `core` runs it says exactly what
§11.1 says - 5 of 5 allocators changed rank, 3 crossed the control, and only
jemalloc and rpmalloc survive.

 **It also found something §11.1 had not stated: peak RSS does not transfer
either.** rpmalloc is **1.12×** the control on the sandbox and **8.01×** on the
GitHub runner; jemalloc 1.63× → 5.55×. A memory-capped deployment cannot be
sized from any single run.

 **What is still open, and it is the part that needed a ruling anyway:**

- the **README headline table** still presents a per-machine ordering as the
  project's answer. Deciding what it says instead is editorial and is yours;
- `rank.rs` still groups by distro/arch/profile/toolchain and **not by host**,
  so a single run's own `report.md` can still present a ranking without naming
  the machine in the group key. The aggregate compensates, the report does not;
-  **the window samples whatever CPU GitHub gives it**, which is not a designed
  experiment. It answers "did this hold on the machines we happened to land on",
  not "which property of the machine decides it" - option (3), still untouched.

 **A correction to this entry's own framing.** It was written as though the
choice were between three options. Building (2) showed they are not exclusive:
the per-machine window is the substrate (3) needs, and (1)'s invariant claim
falls out of it for free. The remaining decision is narrower than the entry
first stated - it is about what the README says, not about what to build.

### Done, 2026-09-03 - and the entry's own recommendation was wrong by then

 **DO NOT PUT THE HOST IN `rank::group_key`.** The *Approach* above recommends
exactly that - option (2), *"adds the host as a group key so no ratio crosses a
machine"* - and it was right when it was written and is wrong now. Building the
rolling window made it wrong: `scripts/report/aggregate.py` keys a window's
groups on **that same string** (`aggregate.py:189`, `name = g.get("group")`), so
a host-bearing group would put every run in a group of its own and the window
could never compare two machines again.  That would break the **one thing in
this repository that refuses an ordering**, in the name of an entry whose whole
subject is that orderings do not transfer.

 **So the machine is NAMED rather than grouped by.** Every `## Rankings`
section now opens with it:

```
 **Every ordering below is a statement about one machine - Intel(R) Xeon(R)
Processor @ 2.10GHz (4 core(s)), `Linux 6.18.44-fc-v24`.** The same six cells
have produced three different orderings on three CPUs, and the run that
inverted the result reported the *tightest* spread of the three. Never quote a
row from this table without naming this machine; `results/rolling/` is where a
claim about more than one lives.
```

 **The `Prove` block above is therefore deliberately not satisfied**, and that
is the finding rather than an omission: its assertion that every group heading
names its host would, if met, have disabled the aggregate. It is kept unedited
so the reasoning is visible.

**The README's editorial half, closed with the two-machine evidence that landed
the same day:**

- §1 already led with *"the ranking depends on the machine"* and *"quote a
  direction, never a magnitude, and always name the machine"*;
- §3 now reports what **transfers across two machines** - jemalloc and rpmalloc
  on musl, nothing on glibc - and states in the same breath that five of six
  candidates changed rank and three crossed the control, mesh from `0.636×` to
  `1.232×`;
- §3.1's memory table became a **range** rather than a number, because rpmalloc
  moved from the cheapest candidate measured (`1.086×`) to the most expensive
  (`9.474×`) between two machines.

 **What is NOT closed here, and it is now its own entry.** Option (3) - *which
property of the machine decides the ordering* - is untouched, and this entry's
own *Decision* called it follow-up work rather than part of this. It is
[`T-025`](#t-025-which-property-of-the-machine-decides-the-ordering), open, so
that a research programme is a row in the backlog rather than a paragraph inside
a closed entry.

---

## T-006: Run the `profiles` suite on x86_64

**Source:** `docs/AGENTS.md` §13, "Written but NOT yet executed".
**Category:** measurement
**Priority:** P2
**Effort:** M
**Status:** done

### Problem

`benchmarks/matrix.toml` declares a `profiles` suite - `static` vs `static-pie`
vs `static-lto` vs `static-pie-lto` - to answer "does the build profile change
which allocator wins, and what does static-PIE cost for the ASLR it buys". It has
never been run, so `docs/static-linking.md`'s profile table describes flags whose
measured consequences are unknown.

### Premise

 **Measured, not read.** `alloc-bench plan --suite profiles` expands, and no
dataset for it exists:

```
$ ls results/published | grep profiles
$ ./target/release/alloc-bench plan --suite profiles | tail -1
```

 The suite declares both architectures. On aarch64 every `static-pie*` cell will
fail the identity gate for the reason in [`T-002`](platform.md), so run x86_64
only until that entry closes.

### Approach

```sh
alloc-bench run --suite profiles --arch x86_64
```

Publish the snapshot under `results/published/<date>-profiles-x86_64/`, carrying
`run.json` per [`T-012`](instrument.md).

 **What it must not do:** report a profile difference smaller than the run's own
MAD as a result. The ASLR question in particular is a small effect and this
project has already established that its within-run spread is a floor, not a
bound - so run it **twice** and publish both, per `docs/methodology/experiments.md`.

### Prove

```sh
alloc-bench validate --run results/published/<date>-profiles-x86_64
```

Exit 0 with 0 errors, and the report's ASLR section showing distinct load
addresses for `static-pie*` and a single fixed address for `static*`.

### Done, 2026-09-02

`results/published/2026-09-02-profiles-x86_64/` - 16 cells, **16 `ok`, 0
`build_failed`, 0 validator errors**, 10 samples, on the 2.80GHz Xeon.

 **No cell was measured under contention**: the session's one overlapping
`gate.sh --strict` finished at 02:47:16 and the first measurement file was
written at 02:49:28, so the overlap was with the image build alone. Recorded in
the snapshot because a measurement carries its conditions.

####  Running it found a build that could not work, and had not worked for as long as the suite went unrun

Every `PIC=0` cell - `static` and `static-lto` - failed for **jemalloc** with
autoconf's `cannot run C compiled programs` (rc=77). The linker's own sentence,
from `.build/config.log` in the cache:

```
relocation R_X86_64_32 against `.rodata.str1.1' can not be used
when making a PIE object; recompile with -fPIE
```

`allocators/lib.sh`'s `pic_cflags` emitted `-fno-PIC` alone; Alpine's gcc is
`--enable-default-pie`, so the objects were non-PIC and the link still PIE.

 **Three probes that would each have said "fine".** mimalloc, snmalloc and the
control build at `PIC=0` without it - confirmed on a **second machine**, `bench`
run [`33582311135`](https://github.com/Azathothas/alloc-bench/actions/runs/33582311135),
where only jemalloc failed; the same `-fno-PIC` builds jemalloc on **aarch64**
(ADRP/ADD is PIE-safe); and a trivial `int main(void){return 0;}` links fine,
having no string constant to relocate.

**Fix:** `-fno-PIC -fno-PIE` on the compile, `-no-pie` on the link, applied only
where a recipe links - jemalloc's `configure`.  Deliberately **not** added to
mimalloc's or snmalloc's cmake: a flag a working build does not need would
change the very archive this suite compares.

### Prove - run, with the output

```
$ ./target/release/alloc-bench run --suite profiles --arch x86_64
[  1/16] alpine-x86_64-jemalloc-rust-global-static-distro           ok
…
[ 16/16] alpine-x86_64-system-baseline-static-pie-lto-distro        ok
alloc-bench: validation -> 0 error(s), 28 warning(s)
$ ./target/release/alloc-bench validate --run results/published/2026-09-02-profiles-x86_64
0 error(s), 28 warning(s) over 16 result(s).      # exit 0
```

 **The ASLR assertion the entry asked for, 16 of 16 cells, no exceptions:**

| profile | link kind | distinct load addresses | randomised |
| --- | --- | --- | --- |
| `static`, `static-lto` | `static` | **1 of 6** | false |
| `static-pie`, `static-pie-lto` | `static-pie` | **6 of 6** | true |

### What it answers, and what it refuses to

 **The profile changes the ordering - three different orderings across four
profiles**, same three allocators, one machine, one run:

```
static          snmalloc < mimalloc < jemalloc
static-lto      jemalloc < snmalloc < mimalloc
static-pie      mimalloc < snmalloc < jemalloc
static-pie-lto  snmalloc < mimalloc < jemalloc
```

 **And in three of the four this project cannot name a winner at all**, because
§9's rule is that a lead smaller than the run's own MAD is no result: the top-two
gaps are 0.5% (MADs 8.7/9.6%), 1.1% (2.9/3.4%) and 3.5% (2.0/3.7%). Only
`static` is clear - snmalloc by 13.9% against MADs of 2.0% and 0.7%.

 **What survives all four:** every candidate beat the control in every profile,
by **28–47%**.

 **The ASLR cost is NOT established, and the two estimates disagree by more
than either cell's MAD.** On the control, `static-pie ÷ static` = **1.016** (1.6%
- inside the noise, no result) while `static-pie-lto ÷ static-lto` = **1.113**
(11.3% - outside it).  Neither may be quoted as *the* cost of static-PIE.

 **LTO is the cleaner signal and points the same way twice:** on the control,
`static-lto ÷ static` = **0.845** and `static-pie-lto ÷ static-pie` = **0.926**,
both outside the MADs, with binary size falling 7.79 → 6.35 MiB plain and
8.15 → 6.63 MiB PIE.

 **The entry asked for the suite to be run TWICE and this is one run.** The
second is not missing by oversight: a `profiles` dispatch on the GitHub runner
(`bench` run `33582311135`) ran the **pre-fix** tree and its `PIC=0` jemalloc
cells failed, so it corroborates the defect and not the numbers.  A clean
second run - dispatch `bench.yml` with `suite=profiles, arches=x86_64` on a
commit at or after `13bd3dc` - is the first thing to do with this entry's
successor, and until then the ASLR figure above stays unestablished rather than
half-established.

###  The second run, 2026-09-02 - and it removes this entry's headline

[`../../../results/published/2026-09-02-profiles-x86_64-ci-runner/`](../../../results/published/2026-09-02-profiles-x86_64-ci-runner/),
`bench` run [`33628116410`](https://github.com/Azathothas/alloc-bench/actions/runs/33628116410)
at `7ba360c`, **`git_dirty: false`**, AMD EPYC 7763, 16 cells, **16 `ok`, 0
validator errors**, re-validated after download.

 **"Three different orderings across four profiles" does not reproduce.** On
this machine there is **one** ordering and it is the same in all four profiles -
`jemalloc < mimalloc < system < snmalloc` - and it is not any of run 1's three.
Only jemalloc beats the control **by more than the run's own spread**
(15.2–17.7%); snmalloc is **10.2–15.0% slower than musl** where run 1 had it
34.0–47.3% faster.  mimalloc is nominally below the control in three of the
four profiles (0.998×, 0.982×, 0.994×) and **inside its own noise in all
four** - 0.16–1.85% against MADs of 0.5–2.2% - so it is not a win under §9, and
writing "only jemalloc beats the control" without that clause overstates what
the table shows.

 **So this entry's finding was about the machine, not the profile**, and that
is `docs/AGENTS.md` §11.1 reproduced in a second suite.  The claim that
survives both: jemalloc beats musl's allocator in every profile on every machine
measured.

 **The static-PIE cost is still not established, and there are now four
estimates: +1.1%, +1.6%, +3.0%, +11.3%.** Each run's own pair disagrees with
itself and the runs disagree about which half clears the noise.  The successor
entry should stop treating this as "one more run away"; two runs on two machines
produced four numbers spanning a factor of ten, and a third would produce a
fifth.

 **What did reproduce, exactly:** the ASLR table (16 of 16, both runs) and 12
of 16 binary sizes byte-for-byte. Both are properties of the build. Every timing
and every RSS ratio moved.

 **And peak RSS moved further than anything else measured here** - jemalloc
1.58× the control on the Xeon, **8.99×** on the EPYC, on byte-identical PIE
binaries; its absolute peak RSS is 6 700 kB against **31 864 kB**. mimalloc's
absolute figure is within 11% across the two machines. Unexplained, recorded in
the snapshot's README rather than interpreted.

---

## T-007: Run the `distros` suite on x86_64

**Source:** `docs/AGENTS.md` §13, "Written but NOT yet executed".
**Category:** measurement
**Priority:** P2
**Effort:** M
**Status:** done

### Problem

Every measurement this project has published is Alpine/musl. The `distros` suite
exists to answer "how much of the answer is the libc" - glibc's allocator is
much better than musl's, so the gap an alternative closes should be far smaller
on Debian and Arch. That expectation is **asserted and unmeasured**.

 **The image-build risk is GONE, and this is the note that used to say
otherwise.** Until 2026-09-02 this entry read *"the Debian and Arch images have
never been built at all"*. [`T-008`](#t-008-run-the-toolchain-control-suite)
built both, which is one of the reasons it was ordered first: the Arch image
built on the first attempt, and  **the Debian one could never have built** -
its extra-CA step wrote into an `/etc/ssl` the base image does not have. Fixed
in all three Dockerfiles; `docs/troubleshooting.md` carries the message.

 **So `distros` now starts from three images that have each built and each
produced measured cells.** What is untested here is the *suite*: the
`libc-surgery` cells on glibc, which are expected to be unsupported and must
come out that way with a reason rather than as failures.

### Premise

 **Measured, not read.** No `distros` dataset exists, and the two Dockerfiles
have no build on record. `images/debian.Dockerfile` and `images/arch.Dockerfile`
are written and their base images resolve - `experiments/out/20-base-image-arch-support.txt`
establishes that Arch publishes no aarch64 image, which is why the planner
renames the distribution to `archlinuxarm` there.

### Approach

Build each image on its own first, so an image failure is not diagnosed as a
measurement failure:

```sh
docker build --platform linux/amd64 --build-arg BASE_IMAGE=debian:latest \
  -f images/debian.Dockerfile -t alloc-bench/debian-x86_64:local .
```

Then `alloc-bench run --suite distros --arch x86_64`.

 **Read the result against [`T-008`](#t-008-run-the-toolchain-control-suite).**
A static binary built with each distribution's own gcc embeds that gcc's codegen,
so a `distros` difference is a difference between three compilers as much as
between two libcs. The `distros` table is not interpretable on its own.

 **And the control is PARTIAL - established by running it, 2026-09-02.**
`TOOLCHAIN=zig` reaches the allocator recipe and nothing else; rustc links
ripgrep through its own target default, which was gcc 15.2.0, 16.2.1 and 14.2.0
in the three images. So a difference that survives `toolchain-control` is
attributable to the distribution **or to its Rust link driver**, not to the libc
alone.  Do not write the stronger sentence into the `distros` report.

 **T-008 also measured two of this suite's three cells' worth of the answer
already**, on mimalloc alone: the musl win (0.649×) does not survive to glibc
(1.027× on Arch, 0.973× on Debian, both inside their own noise). `distros`
extends that to the other allocators and the other mechanisms; it should not be
surprised by it.

### Prove

```sh
alloc-bench validate --run results/published/<date>-distros-x86_64
```

Exit 0 with 0 errors, and every `libc-surgery` cell on Debian present as
`unsupported` with the glibc reason rather than absent.

### Done, 2026-09-02

[`../../../results/published/2026-09-02-distros-x86_64/`](../../../results/published/2026-09-02-distros-x86_64/)
- 18 cells, **18 `ok`, 0 `build_failed`, 0 validator errors**, 81 `noisy`
warnings, 10 samples, at `78df0fe` on a clean tree (`git_dirty: false`,
`git_untracked: 0`), on the 2.80GHz Xeon.

 **The acceptance asked for the wrong thing and this is the second entry in a
row where that happened.** It wanted *"every `libc-surgery` cell on Debian
present as `unsupported`"* - but the `distros` suite declares
`integrations = ["rust-global"]` and contains **no** `libc-surgery` cell at all,
on Debian or anywhere. The glibc-static refusal it was thinking of is exercised
by the `mechanisms` suite, which does carry Debian.  So the criterion is
satisfied by `plan --suite mechanisms`, not by this run, and it is written here
rather than quietly reinterpreted:

```
$ ./target/release/alloc-bench plan --suite mechanisms --arch x86_64 | grep -c 'debian.*libc-surgery'
5
  unsupported debian-x86_64-hardened_malloc-libc-surgery-static-pie-distro
  unsupported debian-x86_64-jemalloc-libc-surgery-static-pie-distro
  unsupported debian-x86_64-mimalloc-libc-surgery-static-pie-distro
  unsupported debian-x86_64-rpmalloc-libc-surgery-static-pie-distro
  unsupported debian-x86_64-snmalloc-libc-surgery-static-pie-distro
```

All five carry the glibc reason, and none is absent - which is what the
criterion was after.

####  Running it found a defect in the identity oracle, not in the distributions

The first attempt stopped at cell 5.
`alpine-x86_64-system-baseline-dynamic-distro` came back `identity_failed` -
*"baseline binary shows no libc allocator implementation"* - and it was the
**oracle** that was wrong, established by reading the binary first:

```
nm --defined-only rg | grep -cE ' [TtWw] (malloc|free|realloc|calloc)$'   -> 0
nm -u rg            | grep -E  ' (malloc|free|calloc|realloc)$'  -> all four, UNDEFINED
readelf -d rg       | grep NEEDED            -> libc.musl-x86_64.so.1
nm rg | grep -cE '__libc_malloc_impl|__malloc_donate|get_meta'   -> 0
```

 **In a dynamic binary the libc allocator is in `libc.so`.** The baseline rule
was a static-binary rule meeting the first `dynamic` cell this project ever ran.
Fixed in `78df0fe`; the dynamic branch asserts the binary **imports** malloc and
free, defines neither, and has a `PT_INTERP`. Six selftest cases, three of them
refusals, and the static rule is re-asserted beside them.

 **The first attempt was stopped and discarded rather than finished and
annotated**, per the settled rule about datasets whose tree is in doubt - here
the doubt was the instrument rather than the tree.

### Prove - run, with the output

```
$ ./target/release/alloc-bench run --suite distros --arch x86_64
[  1/18] alpine-x86_64-jemalloc-rust-global-dynamic-distro          ok
…
[ 18/18] debian-x86_64-system-baseline-static-pie-distro            ok
alloc-bench: validation -> 0 error(s), 81 warning(s)
$ ./target/release/alloc-bench validate --run results/published/2026-09-02-distros-x86_64
0 error(s), 81 warning(s) over 18 result(s).      # exit 0
```

### What it answers

 **musl's allocator is the thing being beaten.** The control's own median
`literal` time, the only like-for-like cross-distribution comparison:

| profile | alpine (musl) | archlinux (glibc) | debian (glibc) | musl ÷ fastest glibc |
| --- | --- | --- | --- | --- |
| `static-pie` | **0.0730 s** | 0.0411 s | 0.0429 s | **1.78×** |
| `dynamic` | **0.0713 s** | 0.0486 s | 0.0449 s | **1.59×** |

 **And the two glibc distributions disagree with each other, significantly.**
`static-pie`, mimalloc against the control in its own image: **1.178× on Arch**
(17.8% slower, outside its spread) and **0.878× on Debian** (12.2% faster,
outside its spread). The validator names the *control* the winner on Arch and
mimalloc the winner on Debian.

 **Which is exactly the caveat this entry inherited from
[`T-008`](#t-008-run-the-toolchain-control-suite), and it is load-bearing
rather than decorative**: rustc linked through gcc 15.2.0, **16.2.1** and
**14.2.0** in the three images. A difference here is a difference between three
compilers, three libcs and three sets of build defaults at once.  The
`distros` table is not a statement about libc.

 **What is worth noticing anyway:** the control's absolute time differs by
4.4% between Arch and Debian while mimalloc's differs by **28.5%**. Whatever
causes it acts on the alternative allocator and barely touches the
distribution's own.

 **Peak RSS transfers across distributions and this is new.** mimalloc costs
**3.0–3.5×** the control's peak RSS and jemalloc **1.40–1.57×** in every
distribution and both profiles - twelve cells.  That does not contradict "peak
RSS does not transfer": it transfers across *distributions on one machine* and
emphatically not across *machines* (1.58× → 8.99× for jemalloc between two
hosts). Two different questions, and the project now has a measurement for each.

 **Three of the six groups support no ordering at all.** Every `dynamic` group
is noisier than its `static-pie` sibling and the Alpine dynamic control is the
noisiest cell in the dataset at a **13.0%** relative MAD.

 **ASLR: 18 of 18**, including nine cells of the `dynamic` profile, which had
never been built before this run.

---

## T-008: Run the `toolchain-control` suite

**Source:** `docs/AGENTS.md` §13, "Written but NOT yet executed".
**Category:** measurement
**Priority:** P2
**Effort:** M
**Status:** done

### Problem

`toolchain-control` is the control for [`T-007`](#t-007-run-the-distros-suite-on-x86_64):
it rebuilds the same cells with one pinned `zig cc`, identical everywhere, so the
compiler stops being a hidden variable. It has never been run, and **zig has
never been used for a build at all** - it installs in every image and is then
unused.

### Premise

 **Read, not measured, and that is the risk.** The images record
`zig_available=yes` during the build, and `toolchains/pins.env` pins the version,
but no cell has ever selected `TOOLCHAIN=zig`. Whether `zig cc` can produce this
project's static-PIE musl link at all is **unestablished**. The recipe contract
passes `CC`/`CXX` through, so it should - "should" is the word this entry exists
to remove.

### Approach

```sh
alloc-bench run --suite toolchain-control --arch x86_64
```

 A zig cell that cannot build must come out `unsupported` with the reason, never
silently fall back to gcc. The image already records `zig_available`; check that
the recipe honours it rather than assuming.

 **What it must not do:** conclude anything about distributions from this suite
alone. It is a control, and its only job is to say whether a `distros` difference
survives holding the compiler still.

### Prove

```sh
alloc-bench validate --run results/published/<date>-toolchain-control-x86_64
python3 -c "
import json;d=json.load(open('results/published/<date>-toolchain-control-x86_64/run.json'))
print(d['tool_versions'])" | grep -i zig
```

Exit 0 with 0 errors, and the run's recorded tool versions naming the pinned zig
- proving the cells actually used it rather than gcc.

### Done, 2026-09-02

`results/published/2026-09-02-toolchain-control-x86_64/` - 6 cells, **6 `ok`, 0
`build_failed`, 0 validator errors**, 13 `noisy` warnings, 10 samples, at
`970bcbd` on a clean tree.

 **The first numbers this project has that are not Alpine/musl.**

####  The `Prove` step above asked the wrong file, and that is a finding

`run.json`'s `tool_versions` records the **host's** tools - git, curl, docker -
and never named zig, so the command as written would have failed on a run that
was entirely correct. What actually proves the cells used zig is per-cell and
stronger:

```
$ python3 -c "import json;d=json.load(open('.../../../results/alpine-x86_64-mimalloc-rust-global-static-pie-zig.json'));print(d['image_env']['zig'], '|', d['build']['alloc_cc'])"
0.16.0 | clang version 21.1.0
$ python3 -c "…same for the baseline cell…"
0.16.0 | (none: this cell builds no allocator)
```

 The first says zig was **available**; the second says it was **used**, and in
which cells. Availability was never the question.

####  Three defects, and none of them was "can zig do the link"

1. **`build.json`'s `cc` named a compiler that had compiled nothing.** A
   `TOOLCHAIN=zig` **baseline** cell recorded `cc: clang version 21.1.0` while
   zig had built nothing in it - a baseline has no allocator, so `$CC` was
   exported and never invoked. Split into `cc` (what rustc linked through) and
   `alloc_cc` (what the toolchain selected).
2.  **The Debian image could never have built.** `debian:latest` has no
   `/etc/ssl` at all before `ca-certificates` is installed, so the extra-CA step
   died with `cannot create /etc/ssl/certs/ca-certificates.crt: Directory
   nonexistent`. Identical block in three Dockerfiles; Alpine and Arch both ship
   the directory. Probed, not guessed. Fixed in all three.
3.  **`run.json` named a commit that had not produced it.** The first complete
   six-cell run was measured from a tree carrying fix 2 uncommitted, and
   `git rev-parse HEAD` is blind to the working tree. That dataset was
   **discarded rather than published**; `git_dirty` was added, `alloc-bench run`
   warns, `check-snapshots.py` refuses an undocumented dirty snapshot (28 planted
   defects, up from 23), and the cells were re-measured from a committed tree.

####  And the suite does not control what its own `why` said it did

| | alpine | archlinux | debian |
| --- | --- | --- | --- |
| `alloc_cc` - the **allocator's** compiler | `clang 21.1.0` | `clang 21.1.0` | `clang 21.1.0` |
| `cc` - what **rustc linked through** | gcc 15.2.0 | **gcc 16.2.1** | **gcc 14.2.0** |

`TOOLCHAIN` reaches the allocator recipe and nothing else; rustc links through
its target default.  **So the control is partial**, `benchmarks/matrix.toml`'s
`why` is corrected to say so, and
[`T-007`](#t-007-run-the-distros-suite-on-x86_64) inherits the caveat.

### Prove - run, with the output

```
$ ./target/release/alloc-bench run --suite toolchain-control --arch x86_64 --strict
[  1/6] alpine-x86_64-mimalloc-rust-global-static-pie-zig          ok
…
[  6/6] debian-x86_64-system-baseline-static-pie-zig               ok
alloc-bench: validation -> 0 error(s), 13 warning(s)
$ ./target/release/alloc-bench validate --run results/published/2026-09-02-toolchain-control-x86_64
0 error(s), 13 warning(s) over 6 result(s).       # exit 0
```

### What it answers

 **mimalloc's musl win does not survive the move to glibc**, and on glibc this
run names no winner in either direction:

| distribution | libc | control | mimalloc | `rel` | its MADs | §9 verdict |
| --- | --- | --- | --- | --- | --- | --- |
| alpine | musl | 0.0728 s | 0.0472 s | **0.649×** | 7.8% / 17.2% |  mimalloc, by 35.2% |
| archlinux | glibc | 0.0403 s | 0.0413 s | 1.027× | 3.4% / 5.2% |  **no result** |
| debian | glibc | 0.0424 s | 0.0412 s | 0.973× | 4.4% / 3.3% |  **no result** |

 **The absolute times say why.** The control's time spans **1.807×** across the
three distributions; mimalloc's spans **1.145×**. The gap an alternative closes
on Alpine is mostly musl's allocator being slow.

 **Peak RSS is what transfers**: mimalloc costs **3.36–3.47×** the control's
peak RSS in every distribution, and **+1.11–1.12 MiB** of binary, equally
consistently.

 **One run, and the Alpine control is its noisiest cell** (17.2% MAD). The 35%
figure is the least reliable number in it - and the one four earlier datasets
already establish. The **new** half is glibc, and that half is tight.

 **`zig cc` silently ignores `-static-pie`** - probed, 6 928 bytes and an
interpreter, byte-identical to no flags at all; `-static -pie` works. No cell is
affected because rustc does the link, and `docs/static-linking.md` records it
before someone wires zig as the Rust linker.

---

## T-017: "musl" meant Alpine and "glibc" meant Debian

**Source:** raised by the operator on 2026-09-03: summarise the best allocator
on musl and on glibc, over **at least three distributions each**.
**Category:** measurement
**Priority:** P1
**Effort:** L
**Status:** done

### Problem

 **Every per-libc claim this project has made rests on one distribution per
libc.** The `distros` suite runs `alpine`, `debian` and `archlinux` - one musl
and two glibc - so a musl-versus-glibc difference could have been the libc, the
compiler, the packaging, or one distribution's patch set, and nothing here could
separate them.

 The `distros` suite had already shown why that matters: on its first run
mimalloc was **1.178×** the control on Arch and **0.878×** on Debian, two glibc
distributions disagreeing by 30 percentage points. A second machine then
inverted the Debian half. Two distributions of a libc can disagree with each
other more than the two libcs do.

### Approach

Three distributions per libc, and one new suite that varies only the
distribution:

| libc | distributions | package manager / compiler |
| --- | --- | --- |
| musl | `alpine`, `wolfi`, `void` | apk / gcc 15, apk / gcc 16, xbps / gcc 14 |
| glibc | `debian`, `ubuntu`, `archlinux` | apt / gcc 14, apt, pacman / gcc 16 |

`libc-contrast`: six distributions × six allocators, one profile
(`static-pie`), one mechanism (`rust-global`), so no cell is unsupported for a
reason unrelated to the distribution.

And a **generated** per-libc summary in the report, rather than prose:
`rank::by_libc` folds the per-group rows into one table per libc, counting how
many **distributions** each candidate beat its own control in.  Under §9's
rule: a lead no larger than that cell's own MAD is a tie and is counted as a
tie.

### Prove

```sh
./target/release/alloc-bench plan --suite libc-contrast --arch x86_64
./target/release/alloc-bench run  --suite libc-contrast --arch x86_64
grep -A 20 'Which allocator, by libc' results/local/<run>/report.md
```

Three distributions listed under each libc, and a verdict per libc that is
either a named allocator that won in **all three** or an explicit refusal.

### Done, 2026-09-03

The dataset, its numbers and the per-libc verdicts are in
[`../../../results/published/2026-09-03-libc-contrast-x86_64/`](../../../results/published/2026-09-03-libc-contrast-x86_64/).

 **Three things had to be fixed before three distributions could even build**,
and each is a defect two distributions could not have found:

1. **`libc_for` falls back to `glibc`.** A musl distribution added to the matrix
   and not named there plans as glibc - its `libc-surgery` cells marked
   unsupported for a reason that does not apply, its identity gate looking for
   the wrong negative control, and the run green throughout. Every musl
   distribution is now named explicitly with that reason written above it.
2. **Wolfi's `apk` has no `tar` package** - busybox provides it - so an install
   list copied from Alpine fails the whole image build.
3.  **Wolfi's gcc defines `_FORTIFY_SOURCE` by default and the other five do
   not.** Its allocator objects then reference `__memset_chk` and
   `__memcpy_chk`, and rustc links musl binaries against its **own** bundled
   `self-contained` musl, which does not provide them. Four of six wolfi cells
   died with `undefined reference to __memset_chk` while the baseline built -
   because a baseline contains no allocator objects, so the failure *looked*
   like an allocator problem and was a toolchain default.
   `allocators/lib.sh` now has `fortify_cflags()` and every recipe uses it, so
   the dimension is constant across the comparison.  Turning fortification
   **on** everywhere was rejected: it changes what every existing number
   measured, to match one distribution's default rather than the other five's.

 **What it cost, for the next session's planning:** the image layer that copies
`allocators/` sits above the cargo build, so **editing any recipe rebuilds all
six images** - about 25 minutes and a disk peak that needs watching. Two of this
session's re-runs were spent that way.

---

## T-025: which property of the machine decides the ordering

**Source:** spun out of [`T-001`](#t-001-decide-what-the-project-claims-now-that-the-ranking-does-not-transfer)
on 2026-09-03, which named it "option (3)" and called it follow-up work rather
than part of itself.
**Category:** measurement
**Priority:** P2
**Effort:** L
**Status:** done

### Problem

 **This project's central finding is that a ranking is a property of the
machine, and it does not know which property.** `core` has produced three
orderings on three CPUs; `profiles` one ordering on a second machine where the
first gave three; `preload` five rank changes and three control-crossings
between two machines on **byte-identical binaries**. Every one of those is a
statement that the answer moved, and none is a statement about *what moved it*.

 Until that is answered, the honest output is the rolling window's refusal -
which is correct, and is also the project telling a reader "it depends" without
being able to say on what.

### Premise

 **Measured, and the candidate list is short because the binaries are
controlled.** Across the disagreeing runs the *build* is constant: five of six
ripgrep binaries are byte-identical between two `core` images, twelve of sixteen
between two `profiles` runs, and **every** row of a `preload` comparison is the
same binary by construction. So the moving part is the host.

What is recorded for every run already, in `run.json`:

| recorded | example values seen to differ |
| --- | --- |
| `cpu_model` | Xeon @ 2.80GHz, Xeon @ 2.10GHz, EPYC 7763, Xeon Platinum 8573C, Neoverse-N2 |
| `cpu_count` | 4 (sandbox) vs 2c/4t (EPYC runner) |
| `kernel` | `6.18.44-fc-v22`, `-v24`, the runners' own |
| `container_runtime` | docker 29.3.1, the runners' |

 **The obvious first hypothesis is untested**: the GitHub runner is 2 physical
cores with SMT against the sandbox's 4, and an allocator's per-thread cache
behaviour is exactly the kind of thing that would care.  It is a hypothesis,
and this entry exists because nobody has run the experiment.

 **What is NOT recorded and would have to be**: page size, transparent huge
pages (`/sys/kernel/mm/transparent_hugepage/enabled`), the CPU's cache sizes,
NUMA topology, and whether the vCPU is pinned. None of these is in `run.json`
today, so no existing dataset can be re-interrogated for them - the sweep has to
start by widening what a run records.

### Approach

Not yet chosen, and  the entry is deliberately not pre-committed to one. Three
shapes, in increasing cost:

1. **Widen `envinfo.rs` and wait.** Record the missing properties, let the
   twice-weekly window accumulate, and look for a property that co-varies with
   the rank changes.  Cheapest, and it costs nothing but time;  it is
   observational - GitHub's fleet is a sample, not a design, and a property that
   happens to correlate with CPU model cannot be separated from it.
2. **Vary one property on one machine.** `taskset` the core count, toggle THP,
   and re-run `core` with everything else held constant.  This is an
   *experiment* rather than a survey, and the sandbox can do it today.
    It answers "does this property matter here", not "is it the one that
   explains the runs already published".
3. **Re-run the disagreeing configurations on a machine class chosen on
   purpose.** Needs runners this project does not have.

 **(2) first is the obvious start** - it is the only one that is an experiment,
it needs no new hardware, and its negative result is publishable: "core count
does not explain it here" would remove the standing first hypothesis.

 **What it must not do:** conclude from a correlation across GitHub's fleet
that one property is the cause. The window is a sample of machines, and
`results/rolling/README.md` already says what that is worth.

### Prove

```sh
sh experiments/160-does-core-count-explain-it.sh
```

 **That script does not exist yet - this entry is `open` and the command is the
acceptance, not a record of a run.** It must vary **one** property on one host,
with everything else held constant, print its conditions on the way out, and
report whether the `core` ordering moves.  A negative result is committed: *"core
count does not explain it here"* closes the standing first hypothesis as usefully
as confirming it would, and leaving it unwritten is how a hypothesis becomes
folklore.


### Partial, 2026-09-03: option (2) is done, and its CONTROL fired

[`../../../experiments/160-does-core-count-explain-it.sh`](../../../experiments/160-does-core-count-explain-it.sh),
output committed. It runs `core` on `alpine` three times - **A** whole host,
**B** pinned to half the cores, **C** whole host again - differing in nothing but
`ALLOC_BENCH_CPUSET`.  The builds are cached on a key that does not include the
cpuset, so **the binaries are identical across all three** and only the CPUs
available at measurement time differ.

 **THE ANSWER TO "does core count decide the ordering" IS: THIS HOST CANNOT BE
ASKED.** A and C - identical conditions, minutes apart - **disagree**:

```
A  whole host : rpmalloc < jemalloc < mimalloc < snmalloc < hardened < system
C  whole host : snmalloc < mimalloc < rpmalloc < jemalloc < hardened < system
```

Three pairs swapped with nothing changed. The control fired, which is what a
control is for, and B therefore says nothing about core count.  That is a second
instance of `docs/AGENTS.md` §12 item 11 - the same host wandering - under a
design built to detect it.

 **What the magnitudes do show:** every candidate moved **toward the control**
when pinned, in the same direction, in **both** executions of the experiment -
10 of 10 allocator-observations. Direction, not magnitude, which is this
project's standing rule.

 **AND THE MAGNITUDE CLAIM WAS WITHDRAWN BEFORE IT WAS PUBLISHED.** A first
execution gave a wander of 1.5–6.9% against an effect of 11.1–31.6% - cleanly
separated, and it would have supported *"core count has a measured effect on the
size of each allocator's advantage"*.  The script was then taught to compute
that comparison itself and re-run. The second execution's wander reaches
**15.3%** and its effect dips to **6.4%**: they overlap, and the script's own
guard printed

```
 The effect is NOT cleanly outside the wander, so this run separates
  neither, and no claim is made about magnitude either.
```

 **The committed transcript is the second execution.** The first one's
transcript was overwritten by the re-run and is therefore **not citable as
data** - which is why no table from it appears here. What it contributes is the
methodological point: a separation that looked clean did not survive one repeat,
forty minutes later, on the same host.

### What is still open

- **option (1)**, widen `envinfo.rs` and let the twice-weekly window accumulate.
   Page size, THP, cache sizes and NUMA topology are **still not recorded**, so
  no existing dataset can be re-interrogated for them.
- **option (3)**, a machine class chosen on purpose. Needs runners this project
  does not have.
-  **And a harder question this experiment raised:** if this host cannot
  reproduce its own ordering across two consecutive runs, then *no* single-host
  experiment can settle an ordering question here, and option (2) is exhausted
  rather than merely incomplete. A future attempt needs either many repeats per
  condition - enough to estimate the wander rather than sample it once - or a
  quieter host.

### Done, 2026-09-03: the ordering question was partly malformed, and the machine effect is real somewhere else

[`../../../experiments/170-how-much-does-one-host-wander.sh`](../../../experiments/170-how-much-does-one-host-wander.sh),
output committed, exit 0. Ten runs of `core` on `alpine`, nothing varied, and
 **the machine is asserted from the datasets rather than assumed**: every run's
`run.json` is read back and all ten record one CPU model, one kernel, one cache
geometry and no cpuset. The probe refuses to analyse runs that do not.

#### 1.  One machine does not have one ordering - but not because it wanders

**Three distinct orderings in ten runs.** The most frequent occurs 7 of 10 times.

 **And the cause is not run-to-run noise.** Measured like for like - the MAD of
the ten per-run medians against the median of each run's own MAD:

| allocator | median | range over 10 | between-run MAD | within-run MAD | ratio |
| --- | --- | --- | --- | --- | --- |
| snmalloc | 0.591 | 6.4% | 1.3% | 3.9% | **0.34×** |
| rpmalloc | 0.606 | 6.5% | 0.8% | 4.1% | **0.20×** |
| jemalloc | 0.631 | 6.6% | 1.2% | 4.0% | **0.31×** |
| mimalloc | 0.642 | 6.1% | 2.0% | 4.8% | **0.42×** |
| hardened_malloc | 0.945 | 6.1% | 2.1% | 4.0% | **0.52×** |

 **The between-run spread is SMALLER than the within-run spread, for every
candidate.** The orderings move because the **gaps are small**: ordered by
median the four fast allocators are `snmalloc(0.591) < rpmalloc(0.606) <
jemalloc(0.631) < mimalloc(0.642)`, so the three gaps between them are **2.7%,
4.0% and 1.7%** - each at or below the within-run MAD of 3.9–4.8%. The fifth,
mimalloc to hardened_malloc, is **47.2%** and is decided in all ten runs. It is
not that the host is unstable; it is that four of the five are within a few
percent of one another.

#### 2.  The two questions have different answers on the same data

| comparison | verdict over 10 runs |
| --- | --- |
| each candidate against the **control** | **5 of 5 decided** - every whole range below 1.000 |
| candidate against **candidate** | **5 separated, 3 consistent, 2 unsettled** of 10 pairs |

So a window that refuses an ordering while publishing a control claim is drawing
exactly the right line, and that is now measured rather than argued.

#### 3.  Most of the window's "rank changes" are not evidence about the machine

Cross-referencing this host's pairwise verdicts against the three machines in
[`../../../results/rolling/core-x86_64/`](../../../results/rolling/core-x86_64/aggregate.md):

| pairs that changed direction across the three machines | 6 |
| --- | --- |
| …that this host **decides** cleanly over its own repeats | **1** (mimalloc vs snmalloc) |
| …that this host does **not** decide | **5** |

 A rank change for a pair one machine cannot resolve is what an unresolved
comparison looks like when it is sampled once per machine. It is not a
measurement of the machine.

#### 4.  But the machine effect IS real, and it is in the ratio to the control

| allocator | this host, 10 runs | window values outside it, by more than that cell's own MAD | widest margin |
| --- | --- | --- | --- |
| snmalloc | 0.568–0.606 | 1 of 3 | **87.7%** |
| mimalloc | 0.625–0.664 | 2 of 3 | 51.3% |
| rpmalloc | 0.601–0.640 | 2 of 3 | 37.3% |
| jemalloc | 0.602–0.644 | 2 of 3 | 36.3% |
| hardened_malloc | 0.917–0.975 | 2 of 3 | 25.7% |

 **Every candidate has a value on another machine that this one never produced
in ten repeats, by 26–88%.** That is where the machine effect lives.

#### The answer, and why the entry closes

 **"Which property of the machine decides the ordering" is the wrong question
for the ordering among candidates**: mostly those comparisons are *unresolved*,
not machine-determined, and this host resolves only one of the six the window
reports.

 **For the ratio to the control the effect is real, large, and NOT localisable
from here.** Doing so needs many repeats **on a second machine** - one sample per
machine is exactly what this experiment shows you cannot reason from - and that
needs runners this project does not have.  Option (1), widening `envinfo.rs`,
is **done** and every future dataset carries page size, THP, caches, NUMA, SMT
width and governor, so the correlation becomes askable as the window fills; but
a correlation across GitHub's fleet still cannot separate a property from the CPU
model it travels with, which is what the entry's own **Approach** warned about.

**So the honest conclusion is: this needs hardware this project does not have,
and it now needs it for a smaller and better-specified question** - repeats on
one second machine, on the control comparison, for five allocators. That is a
result, and the entry closes on it rather than staying a `partial` nobody can
close.

####  Its own first execution is not citable, and that is the second time

This probe was run twice. The first execution reported **9 orderings in 10 runs**
and a between-run spread of **5.2×–19.5×** the within-run MAD - dramatic, and
withdrawn before publication for two independent reasons:

-  **It compared a RANGE over ten runs against a MAD.** A range grows with N
  even for a stationary process; a MAD does not. Under the like-for-like
  comparison the ratio is **0.20×–0.52×**, the opposite conclusion.
-  **Its conditions were never established.** The probe printed one conditions
  block from the machine running the *analysis*, which is resumable - so on a
  re-run it described the host hours after the measurements. This sandbox
  re-hosts without warning (§11.1), and it did so during this session: the CPU
  string was `2.80GHz` at 13:21 and `2.10GHz` at 16:20, with different cache
  sizes. Whether all ten of those runs shared a machine **cannot be recovered**.

 Both defects are fixed in the committed probe: it reads each run's machine
back from `run.json` and refuses to analyse runs that disagree, and it reports
MAD against MAD. [`../../../README.md`](../../../README.md) carries the
withdrawn wording.
