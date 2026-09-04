# mechanisms

The four ways to use an allocator, and the recipes that build them.

[`INDEX.md`](INDEX.md) is the list. [`PROGRESS.md`](PROGRESS.md) is the work
order. Entries close **in place**, with the acceptance command actually run and
its output pasted underneath.

---

## T-004: Fix rpmalloc's override-mode build

**Source:** `docs/AGENTS.md` §5.1, from `mechanisms` run C
(`results/published/2026-09-01-mechanisms-x86_64-run-c/`).
**Category:** mechanisms
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

`allocators/allocators.toml` declares rpmalloc as supporting `libc-surgery` and
`link-override`. Both fail, and they fail **earlier than every other allocator's
failure**: rpmalloc's own build breaks in override mode, so no archive is
produced at all. A declared integration does not build.

### Premise

 **Measured, not read.** Run C, 16 cells, `alpine`/`x86_64`/`static-pie`:
`alpine-x86_64-rpmalloc-libc-surgery-static-pie-distro` and
`…-link-override-…` are both `build_failed`, and the recipe's error is

```
'_ZdaPv' aliased to undefined symbol 'rpfree'
```

`_ZdaPv` is the mangled name of the array form of `operator delete`. The recipe
compiles `rpmalloc/malloc.c`
with `-DENABLE_OVERRIDE=1`, which defines the C++ operator aliases, but the
prefixed build does not provide `rpfree` under that name for the alias to bind
to.

 **This is the one replacement failure in the table that looks like a recipe
bug rather than a musl fact.** Every other allocator fails on the musl-internal
`__libc_*` aliases ([`T-005`](#t-005-make-libc-surgery-work-beyond-mimalloc));
rpmalloc never gets far enough to hit them. That makes it the cheapest way to get
a **second** allocator through `libc-surgery`, which is what would turn that
technique from a mimalloc-specific accident into a finding.

 **The link between the two is read, not measured.** Fixing the build proves the
archive exists; whether the resulting archive then also supplies `__libc_malloc`
and friends is a separate question this entry does **not** claim to answer.

### Approach

Seam: `allocators/rpmalloc/build.sh`, the override-mode compile.

`rpmalloc/malloc.c` guards its C++ operator aliases; upstream expects the plain
`rpmalloc`/`rpfree` symbols to exist unprefixed in override mode. The recipe
already localises the plain aliases with `objcopy` for the *prefixed* build -
check that the same step is not running for `MODE=override` and stripping the
symbol the alias needs.

 **What it must not do:** pass `--allow-multiple-definition`, or delete the
C++ operators without recording that the archive no longer provides them. Both
turn a build failure into a silent behaviour change.

 **Delete the cache before re-testing**, or the stale archive is reused and the
fix appears to do nothing:

```sh
rm -rf .cache/alpine-x86_64/alloc
```

### Prove

```sh
docker run --rm -e SRC=/work/rpmalloc -e OUT=/out -e MODE=override -e PIC=1 \
  -e LIBC=musl -e TARGET_ARCH=x86_64 -e CC=cc -e CXX=c++ \
  alloc-bench/alpine-x86_64:local sh /opt/alloc-bench/allocators/rpmalloc/build.sh
./target/release/alloc-runner archive-check --archive /out/lib/liballocbench.a \
  --symbol malloc --expect-providers 1
```

Exit 0 from both: the archive builds, and it defines `malloc` exactly once. Then
the cell itself:

```sh
alloc-bench run --suite mechanisms --arch x86_64 --allocator rpmalloc
```

 `build_failed` on either replacement cell means this entry is not closed.

### Done, 2026-09-02

 **This entry's Premise was wrong, and it was wrong because it read a tail.**

The `detail` field it quoted - `'_ZdaPv' aliased to undefined symbol 'rpfree'` -
is the **last** error of 74, not the first. Reproduced with the recipe's own
flags, gcc 13.3.0, `rpmalloc` at the pinned `beef233c`:

| what was compiled | result |
| --- | --- |
| `malloc.c` alone, `-DENABLE_OVERRIDE=1` - what the recipe did | **74 errors**, the first being `malloc.c:71: unknown type name 'size_t'` |
| `rpmalloc.c` alone, `-DENABLE_OVERRIDE=1` | **exit 0**; defines `malloc`, `free`, `calloc`, `realloc`, `_ZdlPv`, `_ZdaPv` |
| `rpmalloc.c` alone, `-DENABLE_OVERRIDE=0` | **exit 0**; defines **no** plain names, 24 `rp*` symbols |

 **`rpmalloc/malloc.c` is not a translation unit.** It includes no headers at
all - not even `<stddef.h>` - because `rpmalloc.c` ends with
`#include "malloc.c"` (line 3421). Compiling it as a second object cannot work
in any mode. The C++ operator aliases fail *afterwards*, as a cascade.

 **And `ENABLE_OVERRIDE` defaults to 1** (`rpmalloc.c:169`), so the recipe's
prefixed build was compiling the override layer too - which is why it found
plain `malloc` in a prefixed archive and reached for `objcopy --localize-symbol`
to hide it. The define removes the symbols; the workaround is kept only as a
guard for a future revision.

**The fix**: one compile, `-DENABLE_OVERRIDE=$ov` in both modes, no second
object. `allocators/rpmalloc/build.sh`.

### Prove - run, with the output

`.cache/alpine-x86_64/alloc/rpmalloc-*` deleted first, per the warning above.
Run `20260902-014403`, `alloc-bench validate` **0 errors, 0 warnings**:

```
[cell …-rpmalloc-libc-surgery-…] building rpmalloc (mode=override pic=1 toolchain=distro)
built /cache/alloc/rpmalloc-…-override-pic1-musl-x86_64-distro-default/lib/liballocbench.a (39458 bytes)
[cell …] splicing rpmalloc into every libc.a in the image
surgery: /usr/lib/libc.a
surgery:   displacing 13 member(s): aligned_alloc.lo calloc.lo donate.lo free.lo libc_calloc.lo
           lite_malloc.lo malloc.lo malloc_usable_size.lo memalign.lo posix_memalign.lo
           realloc.lo reallocarray.lo valloc.lo
{"archive":"…/libc.a","symbol":"malloc","expect_providers":1,"found_providers":1,"members":["rpmalloc.o"],"ok":true}
{"archive":"…/libc.a","symbol":"free","expect_providers":1,"found_providers":1,"members":["rpmalloc.o"],"ok":true}
surgery: patched 2 libc.a copy/copies and verified each
```

 **The archive builds, and the surgery accepts it**: the same 13 musl members
displaced from each of two `libc.a` copies that mimalloc displaces, with
`malloc` and `free` each provided exactly once, by `rpmalloc.o`. The recipe bug
is fixed.

###  And it answers the question it was the cheapest route to: NO

The entry existed because it was *"the cheapest way to get a second allocator
through `libc-surgery`"*. Measured: it is not.

| cell | before | after |
| --- | --- | --- |
| `rpmalloc` `rust-global` | ok | ok |
| `rpmalloc` `libc-surgery` |  allocator build failed |  **ripgrep link fails**: `undefined reference to __libc_malloc` ×4, `__libc_free` ×2 |
| `rpmalloc` `link-override` |  allocator build failed |  **5** `multiple definition`: `aligned_alloc`, `calloc`, `free`, `posix_memalign`, `realloc` |

 **The failure moved to exactly where jemalloc, snmalloc and hardened_malloc
fail**, and the cause is in the source, not a recipe: rpmalloc's `__libc_*`
aliases sit at `rpmalloc/malloc.c:376` behind
`#if defined(__GLIBC__) && defined(__linux__)`. **On musl they are never
emitted.**

 **One property explains all four columns.** mimalloc collides on **nine**
symbols under `link-override` and links under `libc-surgery`; rpmalloc collides
on **five** and does not link. The difference is precisely `__libc_malloc`,
`__libc_free`, `__libc_realloc` (plus `strdup`) - the aliases mimalloc defines
and rpmalloc does not. The same fact makes one collide harder and the other fail
to link.

 So [`T-005`](#t-005-make-libc-surgery-work-beyond-mimalloc) is **fully
needed**, and its scope is now precise rather than speculative.

---

## T-003: Implement `MODE=preload` in the allocator recipes

**Source:** `docs/AGENTS.md` §5 and §14 item 4.
**Category:** mechanisms
**Priority:** P1
**Effort:** L
**Status:** done

### Problem

`benchmarks/matrix.toml` declares a whole `preload` suite and
`allocators.toml` declares `preload` support for six allocators. **No recipe
implements `MODE=preload`**, so every one of those cells would fail today.

 **The consequence is larger than one mechanism: Mesh and Google tcmalloc
support no other mechanism, so two of the eight registered allocators have never
been measured at all.** They appear in every plan as `unsupported` rows for
`rust-global` and as cells that cannot run for `preload`.

### Premise

 **Measured, not read.** `alloc-bench plan --suite preload` expands to real
cells; no recipe branches on `MODE=preload`:

```sh
grep -l 'preload' allocators/*/build.sh    # no matches
```

 The orchestrator side is **read, not measured**: `INTEGRATION=preload` is
plumbed through `plan.rs` and `run-cell.sh`, and the report keeps preload results
in a separate table, but that path has never executed end to end.

### Approach

Each recipe gains a shared-object output beside the archive:
`$OUT/lib/liballocbench.so`, built in override mode with `-fPIC`, and
`write_meta` records it. `scripts/build/run-cell.sh` then runs the **dynamic**
ripgrep with `LD_PRELOAD` pointing at it.

Two things the identity oracle needs, and they are the reason this is L not M:

-  **A preload cell's identity cannot be established by reading the
  executable** - the allocator is not in it. `alloc-runner identify` must learn a
  preload mode that reads the *loaded map* (`/proc/<pid>/maps`) or the `.so`
  itself, and a cell whose preload silently failed to load must fail the gate
  rather than being measured as the system allocator. That is precisely the
  upstream defect this project was built against.
- **Mesh and tcmalloc need their build recipes written at all**, not just a mode
  added: neither currently produces any artefact.

 **Preload results are never compared with static ones.** A dynamic binary
going through the PLT is a different binary; keep the separate table.

### Prove

```sh
alloc-bench run --suite preload --arch x86_64
alloc-bench validate --run results/local/<id>
```

Exit 0 with 0 errors, at least one `ok` cell for **mesh** and one for
**tcmalloc**, and each `ok` cell's `identity.json` recording positive evidence
that the preloaded library was actually resident.  A green run in which the
system allocator was measured under another name is the failure this entry must
not produce; the negative control is what proves it did not.

### Partial, 2026-09-02: the mechanism works and is measured; the two allocators it was for still have no numbers

 **This is `partial` and it counts for 0.5 of its 1.0**, per
[`INDEX.md`](INDEX.md)'s rule that a partial counts only for what it closed. The
entry's Approach had two halves and one is done:

| half | state |
| --- | --- |
| the shared-object build, the run-cell wiring, **and the identity oracle a preload cell needs** - "the reason this is L not M" |  done and measured |
| "Mesh and tcmalloc need their build recipes written at all" |  **not done**; both still refuse, with sharper reasons |

**The run:**
[`../../../results/published/2026-09-02-preload-x86_64/`](../../../results/published/2026-09-02-preload-x86_64/)
- 12 cells, **8 `ok`, 4 `unsupported` with reasons, 0 `build_failed`, 0
validator errors**, at `230f482` on a clean tree.

```
$ ./target/release/alloc-bench run --suite preload --arch x86_64
[  1/12] alpine-x86_64-jemalloc-preload-dynamic-distro              ok
[  2/12] alpine-x86_64-mesh-preload-dynamic-distro                  unsupported: …
…
[ 12/12] debian-x86_64-tcmalloc-preload-dynamic-distro              unsupported: …
alloc-bench: validation -> 0 error(s), 30 warning(s)
$ ./target/release/alloc-bench validate --run results/published/2026-09-02-preload-x86_64
0 error(s), 30 warning(s) over 12 result(s).      # exit 0
```

 **jemalloc, mimalloc and snmalloc preload on BOTH musl and glibc.** On musl
all three beat the control and snmalloc leads by 15.8%, outside the spread; on
glibc all three are **slower** than the control by 8–19%.  That is the
`distros` finding reached independently through a different mechanism.

 **And it is the project's only table where every row is the byte-identical
binary** - 7.87 MiB on Alpine, 7.94 on Debian, for the control and all three
candidates. Preload does not rebuild the application.

#### The acceptance's identity clause, and where the evidence actually lives

 The entry asked for it in `identity.json`. It is in **`preload.json`**, and
that is deliberate rather than a slip: `identity.json` is the ELF read, which
for a preload cell can only say the binary is the plain system build it claims
to be. The residency evidence is a different measurement - a live process - and
putting it in the same file would blur what each establishes. Every `ok` cell:
**4 of 4 sampled runs resident with `LD_PRELOAD`, 0 of 4 without**, with the
`/proc/<pid>/maps` line kept verbatim.

####  Three defects in that check, all found before a cell ran

[`../../../experiments/90-preload-residency.sh`](../../../experiments/90-preload-residency.sh),
output committed:

1. **the negative control could not fail.** `probe` took `Option<&str>` and
   skipped the maps search when it was `None`, so the control reported
   `library_resident: 0` **by construction**. A control that cannot fail is a
   sentence in a report.
2. **the reader could not match a canonical path.** `/proc/<pid>/maps` reports
   resolved paths; on a host where `/lib` is a symlink, an exact match against
   the caller's string finds nothing - including glibc itself.
3. **the poll stopped too early.** It broke as soon as the subject's own text
   was mapped.  The *kernel* maps the executable and the interpreter at
   `execve`; every shared library, `LD_PRELOAD` included, is mapped afterwards
   by `ld.so`. So the first read in which the subject exists is systematically
   before the loader has done anything, and the check reported **every** library
   absent, including one mapped into every process on the host.

 **A comment in the code claimed the opposite of what the code did** - it said
the library was looked for "in the SAME read" while two reads were issued. The
probe found it; reading the comment would not have.

#### Why mesh and tcmalloc still have no numbers, more precisely than before

 **Mesh: the build succeeds and produces no library**, on both distributions.
The recipe now lists what it left - every object of the `mesh` target, a whole
googletest build, the unit-test objects - and **no `.so` or `.a` anywhere under
the build tree**.  Previously it said "produced neither a static archive nor a
shared object", a claim about a directory that does not say what is in it.
 **What would open it:** establishing whether upstream's `mesh` target is an
object library, or whether its shared-library link sits behind a CMake option
this recipe does not set. Nobody has looked at its `CMakeLists.txt`.

 **tcmalloc: a TLS trust failure in the JVM, on this network.** Bazel resolves
its module graph from `bcr.bazel.build` and gets
`TLS error: (certificate_unknown) PKIX path building failed`. bazelisk
downloads its **own** JDK, whose `cacerts` is not
`/etc/ssl/certs/ca-certificates.crt` - so the proxy CA the image trusts, which
`curl` and `apt` honour, is invisible to Java. **Probed, not guessed:** the
image contains no `java`, no `keytool` and no `cacerts` at all.

 **What was tried and rejected:** adding a JDK plus `ca-certificates-java` to
the Debian image so the CA could be imported at build time. Rejected for now -
it is ~300 MB on an image used by every Debian cell, on a host where
[`PROGRESS.md`](PROGRESS.md) records disk as the binding constraint, to work
around a proxy that is not part of the experiment.

####  The cheap next step was taken, and it moved the wall rather than removing it

`bench.yml` was dispatched with `suite=preload, arches=x86_64` onto a GitHub
runner, which has no TLS-inspecting proxy - run
[`33636229346`](https://github.com/Azathothas/alloc-bench/actions/runs/33636229346),
conclusion `success`, published as
[`../../../results/published/2026-09-02-preload-x86_64-ci-runner/`](../../../results/published/2026-09-02-preload-x86_64-ci-runner/).

 **The TLS diagnosis held.** There is no `PKIX` error in that run: Bazel
resolved its module graph and built. The failure on the dev host is the dev
host's network.

 **And the recipe's next message is not a measurement either.** It said *"the
bazel build produced no shared object usable for LD_PRELOAD under bazel-bin"* -
but `bazel-bin` is a **symlink** into Bazel's output base, and `find` with its
default `-P` does not follow a symlink even as the starting point. Reproduced on
the host rather than reasoned about:

```
ln -s real bazel-bin; touch real/libtcmalloc.so
find    bazel-bin -type f -name '*.so'   ->  0
find -L bazel-bin -type f -name '*.so'   ->  1
```

 **So that cell establishes that Bazel built, and nothing else.** The search
could not look. Fixed to `find -L`, and the diagnostic now lists `.a` files
too, because `//tcmalloc:tcmalloc_deprecated_perthread` and `//tcmalloc` are
`cc_library` targets and a `cc_library` yields an archive.

 **What would open it now**, in cost order: another dispatch, which will print
what Bazel actually leaves under `bazel-bin`; then, if that is archives only,
choosing a Bazel target that produces a shared object.  Neither is a claim
that tcmalloc can be preloaded - that remains unmeasured, and two of this
entry's three refusals so far have been the instrument rather than the
allocator.

 **The recipe now says which failure it was.** It used to report "bazel build
failed", which reads as an upstream limitation; it is not one, and the
distinction is the same one `docs/AGENTS.md` §6.1 draws when `apk` reports "no
such package" for a trust problem.

### 2026-09-03: the dispatch answered, and mesh's wall was the search AGAIN

 **The dispatch named above ran.** `bench.yml`
[`33638469352`](https://github.com/Azathothas/alloc-bench/actions/runs/33638469352),
`suite=preload, arches=x86_64`, conclusion **`success`**, 12 cells, 0 validator
errors. Its Debian tcmalloc cell reports:

```
[ 12/12] debian-x86_64-tcmalloc-preload-dynamic-distro   unsupported:
  no libtcmalloc*.so under bazel-bin after a successful bazel build.
```

So the `find -L` fix worked, the search could look, and **there is no
`libtcmalloc*.so`**. That settles the branch the previous section left open: it
is not archives-versus-shared-object confusion, and the next step is not a
different target.

 **UPSTREAM DECLARES NO SHARED-LIBRARY TARGET AT ALL.** Read off the pinned
commit `897c9eaf`, every BUILD file and both `.bzl` macro files in the
repository:

| file | `cc_shared_library` | `linkshared` |
| --- | --- | --- |
| `BUILD` (root, license header only) | 0 | 0 |
| `tcmalloc/BUILD` | 0 | 0 |
| `tcmalloc/internal/BUILD` | 0 | 0 |
| `tcmalloc/testing/BUILD` | 0 | 0 |
| `tcmalloc/copts.bzl`, `tcmalloc/variants.bzl` | 0 | 0 |

and `//tcmalloc:tcmalloc` is `cc_library(linkstatic = 1, alwayslink = 1)`.  So
the previous refusal's remedy - *"this recipe is asking Bazel for the wrong
target"* - was **wrong**: there is no other target to ask for. Every
`//tcmalloc:*` allocator target is a `cc_library`, and a `cc_library` yields an
archive.

 **So the recipe now DECLARES one.** It writes a one-target package into the
workspace - `cc_binary(name = "libtcmalloc_allocbench.so", linkshared = 1,
deps = ["//tcmalloc"])` - and builds that.  **This is this project supplying
the target and it is recorded as such**, not presented as an upstream artefact;
what it links is upstream's own allocator at the pinned commit, and `finish_so`
asserts the result EXPORTS `malloc` rather than merely existing.

 **UNVERIFIED at the time of writing, and that is stated rather than implied.**
Bazel cannot run on this host at all (the TLS wall above), so the recipe change
has been syntax-checked and reasoned about and **not executed**. Only a dispatch
onto a runner without the proxy can say whether it builds.

####  Mesh: the build was never the problem, and neither was the CMake option

 **Mesh writes its library INTO THE SOURCE TREE, and the recipe searched only
the build directory.** `CMakeLists.txt` at the pinned commit `2987f883`:

```cmake
11: set(CMAKE_OUTPUT_DIRECTORY         ${CMAKE_SOURCE_DIR}/build)
13: set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_OUTPUT_DIRECTORY}/lib)
```

and `src/CMakeLists.txt:30` is `add_library(mesh SHARED ${mesh_src})`. The
recipe ran `cmake -S "$SRC" -B "$B"` and then searched `$B` alone.

 **Measured, not read**:
[`../../../experiments/100-mesh-artefacts.sh`](../../../experiments/100-mesh-artefacts.sh),
output committed. It clones the pinned commit, builds it, and asserts three
things:

| assertion | result |
| --- | --- |
| shared objects under `-B` (the recipe's search) | **0** |
| `$SRC/build/lib/libmesh.so` exists |  **313 424 bytes**, ELF shared object |
| it exports `malloc` in `nm -D` |  and `free`, `realloc`, `calloc`, `posix_memalign`, `aligned_alloc` |

 **Both open questions this entry carried are answered and neither answer was
one of the two offered.** The `mesh` target is *not* an object library, and the
shared-library link is *not* behind an unset CMake option. It is a
`SHARED` library that has been built correctly every single time, into a
directory nothing looked in.

 **That is the THIRD refusal in this entry that turned out to be the
instrument** - after tcmalloc's `find` not following the `bazel-bin` symlink and
its TLS failure being reported as "bazel build failed".  The pattern is worth
naming because it will recur: **a refusal is a measurement, and a search that
cannot look reports the strongest possible claim** - "there is no such thing" -
from the weakest possible evidence.

 **And the fix carries a hazard the old code did not have.** `$SRC` is the
*cached* source tree, shared by every cell of a distribution and architecture,
so a `libmesh.so` left there by one cell would be picked up by the next and
measured under the wrong flags. The recipe clears `$SRC/build` before every
configure.  It must never widen that to `rm -rf "$SRC"`: `fetch-source.sh`
treats a tree already at the pinned commit as a cache hit, and deleting the
checkout costs every later cell a re-clone.

#### rpmalloc and hardened_malloc: the two recipes that declared preload and refused it

Both now implement it.  **hardened_malloc's preload object is the archive's own
objects**, linked with upstream's own rule (`Makefile:113-114`), so its `preload`
and `libc-surgery` cells run the same compiled allocator and differ only in how
it is attached.  **rpmalloc's cannot be**: `ENABLE_PRELOAD=1` is required for a
library the loader maps into a process that knows nothing about it - rpmalloc
needs explicit process and per-thread initialisation - so its preload object is
compiled differently from its archive and no claim may treat the two as one.

Both were built and exercised on the host before any container ran:

```
$ MODE=preload PIC=1 sh allocators/rpmalloc/build.sh
built …/liballocbench.so (46600 bytes, mode=preload pic=1 libc=glibc arch=x86_64)
$ MODE=preload PIC=1 sh allocators/hardened_malloc/build.sh
built …/liballocbench.so (44904 bytes, mode=preload pic=1 libc=glibc arch=x86_64)
$ LD_PRELOAD=<each> ./t          # 512 mallocs, 512 reallocs, 512 frees, a calloc
alloc-ok                          # rc=0 for both, and for the control
```

 **That is a build check and a crash check, not a residency check.** `finish_so`
asserts the dynamic export; only `alloc-runner preload-check` against a live
process establishes that the loader took the library, and only a suite run
establishes that ripgrep still finds the right number of needles afterwards.

 **The suite had to change too, and that is the more interesting half.** Both
allocators declared `preload` in `allocators.toml` from the beginning, and the
`preload` suite listed six of eight allocators - so no cell paired either with
the mechanism and **nothing had ever taken the path**. `plan --suite preload
--arch x86_64` went from 12 cells to **16**.

---


###  DONE, 2026-09-03 - Google tcmalloc has a number, and it was the last one

**All eight allocators in the registry now have a measurement.** This entry has
been `partial` since 2026-09-02 for one reason: tcmalloc had never produced one.

```
debian / x86_64 / dynamic / distro
   tcmalloc   1.266×   lead −26.6%   MAD 2.5%
```

Dataset:
[`../../../results/published/2026-09-03-preload-x86_64-tcmalloc/`](../../../results/published/2026-09-03-preload-x86_64-tcmalloc/)
- 16 cells, **15 `ok`, 1 `unsupported` with its reason, 0 validator errors**, at
commit `c13689af` on a **clean tree**, on an AMD EPYC 9V74. Dispatch: bench
[`33729832142`](https://github.com/Azathothas/alloc-bench/actions/runs/33729832142).

 **Slower than glibc's allocator, well outside its own spread** - which is what
every candidate does on glibc in every run this project has taken, so the number
is the expected shape rather than a surprise. It is a *measurement*, which is
what was missing.

 **`alpine` remains `unsupported`, and that refusal is real:** *"upstream does
not support musl; the Bazel build requires glibc-specific interfaces."*

 **Three of tcmalloc's four recorded refusals were this project's instrument,
not the allocator**, and the last of them was fixed hours before this run:

| # | what it said | what it was |
| --- | --- | --- |
| 1 | musl unsupported |  real, upstream's |
| 2 | "the bazel build failed" |  the dev host's TLS interception, reported as a build failure |
| 3 | "no shared object under `bazel-bin`" |  `find`'s default `-P` will not follow a symlink, and `bazel-bin` is one |
| 4 | "does not EXPORT malloc…" over an **empty list** |  a mute diagnostic - [`T-024`](instrument.md) |

 **And the answer is neither of the two things the mute diagnostic could not
tell apart.** The generated `cc_binary(linkshared = 1)` target produces a shared
object that **does** export the four symbols, the loader maps it, and the cell
measures.  **The recipe was already correct in the run before**; only the report
of it was not. That is the fourth time on this one allocator that the instrument,
not the subject, was the thing at fault - and it is why
[`INDEX.md`](INDEX.md)'s ordering argument puts a defect in the instrument above
the thing the instrument was pointed at.

## T-005: Make `libc-surgery` work beyond mimalloc

**Source:** `docs/AGENTS.md` §5.1, from `mechanisms` run C.
**Category:** mechanisms
**Priority:** P2
**Effort:** L
**Status:** done

### Problem

`libc-surgery` is the mechanism that answers the project's practical question -
"can I ship a container image whose allocator is different". Run across five
allocators for the first time, **it works for exactly one**. jemalloc, snmalloc
and hardened_malloc all fail to link.

### Premise

 **Measured, not read**, from run C's committed build logs
(`results/published/2026-09-01-mechanisms-x86_64-run-c/evidence/libc-surgery-*.txt`).

Deleting musl's malloc members from `libc.a` leaves musl's **own** remaining
objects still referencing the musl-internal aliases `__libc_malloc`,
`__libc_free` and `__libc_calloc`. The replacement archive has to supply them.
The referencing objects, read off the logs:

| musl object | alias it needs |
| --- | --- |
| `src/ldso/dlerror.c` | `__libc_malloc`, `__libc_free` |
| `src/exit/atexit.c` | `__libc_calloc` |
| `src/thread/pthread_atfork.c` | `__libc_malloc` |
| `src/process/posix_spawn_file_actions_destroy.c` | `__libc_free` |
| `src/process/posix_spawn_file_actions_addchdir.c` | `__libc_malloc` |

 **That list is what the committed 60-line log tails show, not a proof of
completeness.** The full build logs are not published - see
[`T-011`](instrument.md#t-011-publish-the-build-log-with-the-failure-it-documents).

 **mimalloc happens to define those aliases; the others do not.** This is the
same alias that broke the identity oracle (`docs/AGENTS.md` §12 item 12), where
mimalloc defining `__libc_malloc` made a correctly-displaced musl binary look
like it still contained glibc's allocator. **The quirk that broke the negative
control is the quirk that makes the surgery link.**

 So `libc-surgery` is **not** a general technique that happened to be tested on
mimalloc first. As implemented it rests on a mimalloc-specific accident, and the
prior art it came from (`https://github.com/haskell-wasm/rust-alpine-mimalloc`) is a
mimalloc project - quite possibly for this reason.

### Approach

Seam: `scripts/build/libc-surgery.sh`, after the delete and before the `SAVE`.

Supply the aliases in the surgery step rather than relying on the allocator to
define them: assemble a tiny object defining `__libc_malloc`, `__libc_free`,
`__libc_calloc` and `__libc_realloc` as weak aliases forwarding to the
replacement archive's `malloc`/`free`/`calloc`/`realloc`, and `ADDLIB` it.

 **Weigh this carefully, and it is the reason the entry is P2 rather than P1.**
It means the project *synthesises* symbols that musl's own objects call. That
must not become a way to make a broken configuration look like it works. Two
guards are part of this entry, not follow-up:

- the existing assertion stays: exactly one member may define `malloc` and one
  `free` after the splice;
- the synthesised aliases must be **verified to resolve to the replacement**, not
  merely to exist - `alloc-runner identify`'s negative control must still fail a
  binary that kept musl's allocator.

 [`T-004`](#t-004-fix-rpmallocs-override-mode-build) is the cheaper first step
and should land before this one: it may add a second allocator to the working
column without synthesising anything, which would tell you how much of this
entry is actually needed.

### Prove

```sh
alloc-bench run --suite mechanisms --arch x86_64
alloc-bench validate --run results/local/<id>
```

Exit 0 with 0 errors and **at least two allocators** with an `ok`
`libc-surgery` cell. Plus the negative control still biting:

```sh
./target/release/alloc-runner identify --bin ./rg-surgery-jemalloc \
  --expect-allocator jemalloc --expect-kind static-pie
```

Exit 0, with `identity.json` recording the displaced musl allocator as **absent**.

### Done, 2026-09-02 - one of five became four of five

**`mechanisms` run E**, `alpine`/`x86_64`/`static-pie`, all five allocators plus
the control, 16 cells:
`results/published/2026-09-02-mechanisms-x86_64-run-e/`.

| allocator | `rust-global` | `libc-surgery` | `link-override` |
| --- | --- | --- | --- |
| mimalloc |  |  |  9 `multiple definition` |
| jemalloc |  |  **was ** |  |
| rpmalloc |  |  **was ** |  5 `multiple definition` |
| hardened_malloc |  |  **was ** |  5 `multiple definition` |
| snmalloc |  |  **a NEW reason** - [`T-013`](#t-013-libc-surgery-cannot-carry-a-c-allocator-into-libca) |  5 `multiple definition` |

 **The acceptance asked for two and got four.** Every one passes the identity
gate with `libc_allocator_detected: []` - the negative control confirming musl's
allocator is gone - and the correctness gate's exact needle counts.

#### What it took, and why it is not a relaxed check

`alloc-runner ar-unresolved --archive … --symbols …` asks the spliced archive
which candidate names it **references and never defines**;
`scripts/build/libc-surgery.sh` compiles a forwarding object for exactly those
and `ADDLIB`s it. On every non-mimalloc allocator it derives the same three:

```
surgery:   __libc_calloc __libc_free __libc_malloc -- referenced by musl, defined by nothing; synthesising
```

 **mimalloc synthesises nothing** - it defines them itself - so its archive and
its numbers are unchanged, which is what makes runs A–D still comparable.

 **Forwarding functions, not `__attribute__((alias))`.** An alias target must
live in the same translation unit; that is exactly the trap rpmalloc's own build
falls into ([`T-004`](#t-004-fix-rpmallocs-override-mode-build)).

The four guards the entry demanded, all present:

1. only names on an explicit map are synthesised - anything else is a **refusal
   naming the symbol**, not a skip;
2. each forwards to the plain name, which after the splice can only be the
   replacement's: musl's is no longer in the archive;
3. the malloc-once / free-once assertions are **unchanged** and still run;
4.  nothing may remain unresolved afterwards, and `ar-unresolved` is asked
   again to prove it.

####  And the oracle had to learn override mode, which is a separate thing

hardened_malloc's cell first came back `identity_failed`:
`no symbol evidence of hardened_malloc in the binary`.  The project's rule is
*"if the oracle rejects a cell, the cell is wrong"* - so the binary was read
before anything was touched:

```
$ nm --defined-only <cell>/rg | grep -E 'get_metadata_key|memory_protect_rw_metadata'
get_metadata_key
memory_protect_rw_metadata
$ jq -r '.libc_allocator_detected' identity.json
[]
```

The allocator **was** there and musl's **was not**. The gap was the signature:
`h_malloc`, `h_free`, `h_malloc_object_size`, `h_realloc` exist only under
`-DH_MALLOC_PREFIX`, which override mode deliberately does not set. Same for
snmalloc, whose `SNMALLOC_STATIC_LIBRARY_PREFIX` is empty in override mode.

 **Adding evidence is not relaxing a check**, and three guards were run to
prove it: the musl control is still refused as hardened_malloc *and* its
negative control fires; a mimalloc binary is still refused as hardened_malloc;
and the control still identifies as `system`.

 **The obvious candidate was refused.** hardened_malloc vendors ChaCha and
exports `chacha_ivsetup` / `chacha_keysetup` / `chacha_keystream_bytes` - but a
mimalloc binary defines `chacha_block`, from ripgrep's own Rust dependency. Had
the family been used it would have repeated `docs/AGENTS.md` §12 item 12 exactly.
The three names chosen were each checked absent from a mimalloc binary, an
rpmalloc binary and the control.

 For snmalloc, C++, the evidence is the **Itanium-mangled namespace**
`_ZN8snmalloc` through a new `any_prefix` field. Length-prefixed mangling makes
that as specific as an exact name;  a bare word is not, which is the whole
lesson of `chacha_`.

####  What this does NOT establish

- **snmalloc still fails**, for a reason nothing to do with this entry: the C++
  runtime. [`T-013`](#t-013-libc-surgery-cannot-carry-a-c-allocator-into-libca).
   Which is itself a finding - `libc-surgery` looks like a **C-allocator**
  technique, and the one C++ allocator in the registry is the one that fails.
- **`link-override` still fails for every allocator**, unchanged, and now with a
  complete account of why: mimalloc collides on **nine** symbols, everyone else
  on **five**, and the four extra are exactly the `__libc_*` aliases (plus
  `strdup`) mimalloc alone defines.  One property explains both mechanism
  columns for all five allocators.

---

## T-013: `libc-surgery` cannot carry a C++ allocator into `libc.a`

**Source:** `mechanisms` run E, 2026-09-02 - the run that closed
[`T-005`](#t-005-make-libc-surgery-work-beyond-mimalloc) for four allocators and
left this one.
**Category:** mechanisms
**Priority:** P2
**Effort:** M
**Status:** done

### Problem

With the stranded `__libc_*` aliases supplied ([`T-005`](#t-005-make-libc-surgery-work-beyond-mimalloc)),
snmalloc's `libc-surgery` cell gets past the alias failure that stopped every
non-mimalloc allocator - and fails on the **C++ runtime** instead.

 **This is a different problem, and it is a property of the mechanism rather
than of the recipe.** Splicing a C++ allocator into `libc.a` makes *every* link
in that image need libstdc++, including links this project does not control.

### Premise

 **Measured, not read.** Run E, cell
`alpine-x86_64-snmalloc-libc-surgery-static-pie-distro`:

```
$ grep -c 'multiple definition' build.log
0
$ grep -o "undefined reference to \`[^']*'" build.log | sort | uniq -c | sort -rn
     10 undefined reference to `__cxa_thread_atexit'
      2 undefined reference to `__gxx_personality_v0'
      2 undefined reference to `__cxa_call_terminate'
$ grep -c 'build script' build.log
2
```

 **The alias problem is solved for snmalloc too** - zero `multiple definition`,
and the surgery's own assertions passed with `malloc` and `free` provided
exactly once by `malloc.cc.o`. The synthesis fired and named the same three
aliases it names for every other allocator.

 **What fails is `libc` and `serde_core`'s BUILD SCRIPTS.** Those are compiled
by cargo, not by this project, and they link against the patched `libc.a` with
no `-lstdc++` anywhere. `allocators/snmalloc/build.sh` already solves this for
`rust-global` - it locates `libstdc++.a` with `$CXX -print-file-name` and records
`static=stdc++` in the cell's meta, which reaches the **ripgrep** link line. A
cargo build script's link line is not ours to touch.

### Approach

Three routes, and none is obviously right, which is why this is an entry rather
than a fix:

1. **Splice the needed C++ runtime objects into `libc.a` as well.**  Weigh this
   very carefully: `allocators/snmalloc/build.sh` already refuses a smaller
   version of it - it deletes `new.cc.o` because *"putting an operator new inside
   libc.a would change the behaviour of every C++ program built in the image,
   which is a much larger claim than this project is making"*. Adding
   `__cxa_thread_atexit` and the unwinder is the same class of claim.
2. **Add the C++ runtime to the image's default link configuration** (a `specs`
   file or a `CARGO_TARGET_*_RUSTFLAGS` covering build scripts).  Then the
   mechanism's headline claim - *"every static binary built in that image gets it
   with no build flags"* - is no longer true for this allocator, and the report
   must say so per allocator rather than per mechanism.
3. **Publish it as unsupported with this reason**, the §5 convention: a C++
   allocator cannot be spliced into a C library without dragging its runtime
   along, and that is a finding about the technique.

 **What it must not do:** pass `--allow-multiple-definition`, or report the
cell as anything other than what happened.

### Decision, 2026-09-02: route 3, and here is what routes 1 and 2 cost

 **`allocators.toml` drops `libc-surgery` from snmalloc's `integrations` and
records the reason under `unsupported_notes`.** The planner then emits the cell
as `unsupported` with that reason and the report prints it - the §15 convention,
and the acceptance below allows exactly this outcome. The note is a paragraph,
not a shrug: it names the three symbols, names *whose* link fails (cargo's build
scripts for `libc` and `serde_core`, which this project does not write a link
line for), and says what would change the answer.

 **Route 1 - splice the C++ runtime objects into `libc.a` too - was rejected
because this repository already refuses a smaller version of it.**
`allocators/snmalloc/build.sh` deletes `new.cc.o` on the grounds that *"putting
an operator new inside libc.a would change the behaviour of every C++ program
built in the image, which is a much larger claim than this project is making"*.
`__cxa_thread_atexit` and the unwinder are the same class of claim, and taking
route 1 would mean overturning a decision this project made deliberately in
order to keep a different one.

 **Route 2 - put the C++ runtime in the image's default link configuration -
was rejected because it falsifies the mechanism's headline claim.**
`libc-surgery` exists to answer *"I ship a container image"*: every static
binary built in that image gets the allocator **with no build flags**. A `specs`
file or a blanket `RUSTFLAGS` is a build flag, so the claim would have to be
qualified per allocator rather than per mechanism - and the qualification would
be invisible in every table that says `libc-surgery`.

 **What route 3 must NOT be read as.** It is not "snmalloc cannot be
replaced": snmalloc's `rust-global` cell works and is measured in four datasets,
and its `preload` cell is a different mechanism entirely. It is not "C++
allocators are slow" - no number changed. It is one sentence about one
mechanism: **`libc-surgery` is a C-allocator technique**, and the registry now
says so where a reader will meet it.

 **Note which way this cuts.** It is evidence that `libc-surgery` is a
**C-allocator technique**. mimalloc, jemalloc, rpmalloc and hardened_malloc are C;
snmalloc is the only C++ one in the registry and it is the only one that fails.

### Prove

```sh
alloc-bench run --suite mechanisms --arch x86_64 --distro alpine --allocator snmalloc,system
alloc-bench validate --run results/local/<id>
```

Exit 0 with 0 errors, and the `libc-surgery` cell either `ok` with an identity
that names snmalloc and no musl allocator, or `unsupported` carrying this
reason.  `build_failed` means this entry is not closed.

### Done, 2026-09-02

```
$ ./target/release/alloc-bench run --suite mechanisms --arch x86_64 \
      --distro alpine --allocator snmalloc,system
[  1/4] alpine-x86_64-snmalloc-libc-surgery-static-pie-distro      unsupported: A C++ allocator
        cannot be spliced into libc.a without dragging its runtime into every link in the image…
[  2/4] alpine-x86_64-snmalloc-link-override-static-pie-distro     build_failed: multiple definition
        of `posix_memalign'…
[  3/4] alpine-x86_64-snmalloc-rust-global-static-pie-distro       ok
[  4/4] alpine-x86_64-system-baseline-static-pie-distro            ok
alloc-bench: validation -> 0 error(s), 8 warning(s)

$ ./target/release/alloc-bench validate --run results/local/20260902-133110
0 error(s), 8 warning(s) over 4 result(s).        # exit 0
```

 **The cell is `unsupported`, not `build_failed`**, which is the criterion
above, and its `detail` carries the whole paragraph - including *what would
change it*. The report prints it.

 **Cell 2 is `build_failed` and that is NOT this entry.** `link-override`
fails for snmalloc as it does for all five allocators, on `multiple definition
of posix_memalign` and four siblings - the collision `docs/AGENTS.md` §5.1
documents, unchanged and unrelated.  A reader skimming the run for a red line
would find that one; it is a different mechanism and a different cause.

 **Cell 3 is the point of not overreaching.** snmalloc's `rust-global` cell is
still `ok` in the same run. Withdrawing `libc-surgery` says nothing about
snmalloc as an allocator, and the run shows it: the allocator works, one
mechanism cannot carry it.

 **This run is not published as a dataset.** It is a four-cell slice taken to
answer one question, on the same host as
[`../../../results/published/2026-09-02-mechanisms-x86_64-run-e/`](../../../results/published/2026-09-02-mechanisms-x86_64-run-e/),
which is the full sixteen-cell dataset the finding comes from. Publishing a
slice beside it would add a table nobody should compare with anything.

 **And the entry's own premise was measured on run E, not here.** This run
confirms the *classification* - that the configuration is now published as
unsupported with its reason - and re-measures nothing about the C++ runtime.
The `__cxa_thread_atexit` counts remain run E's.

---

## T-009: Exercise hardened_malloc's `light` variant

**Source:** `docs/AGENTS.md` §13, "Written but NOT yet executed".
**Category:** mechanisms
**Priority:** P3
**Effort:** S
**Status:** done

### Problem

`HM_VARIANT` is plumbed through the recipe and the cache key, but no suite sets
it, so only hardened_malloc's default configuration has ever been built. The
project reports hardened_malloc as the slowest row in three of its four `core`
datasets - run A 1.075×, the CI runner 1.225×, aarch64 1.106×, but run B 0.890×
where the control is slowest - without ever having measured the variant upstream
offers for exactly that trade-off.

### Premise

 **Read, not measured.** `HM_VARIANT` appears in
`allocators/hardened_malloc/build.sh` and in the allocator cache key; no entry in
`benchmarks/matrix.toml` sets it. Whether the `light` variant builds under this
project's flags is unestablished.

### Approach

Add a suite that varies only `HM_VARIANT` - default against `light` - holding
distribution, architecture, profile, mechanism and toolchain constant. The
`why` string must state the question: *what does hardened_malloc's own reduced
configuration buy back, and does it change its position against the control?*

 **What it must not do:** present the result as a security claim. This project
measures performance and makes **no claim** about whether any mitigation works.
Report what `light` turns off by citing upstream's own description, and say that
the security consequence is not measured here.

### Prove

```sh
alloc-bench plan --suite hardening-variants | grep hardened_malloc
alloc-bench run  --suite hardening-variants --arch x86_64
alloc-bench validate --run results/local/<id>
```

Exit 0 with 0 errors, and two `ok` hardened_malloc cells whose `build.json`
records different `HM_VARIANT` values - proving the variant actually reached the
compiler rather than being accepted and ignored.

### Done, 2026-09-02

`results/published/2026-09-02-hardening-variants-x86_64/` and
[`…-run-b/`](../../../results/published/2026-09-02-hardening-variants-x86_64-run-b/) -
3 cells each, **3 `ok`, 0 validator errors** both times, 10 samples,  **run
twice from the same commit** (`3ce29e9`, `git_dirty: false`).

#### Prove - run, with the output

```
$ ./target/release/alloc-bench run --suite hardening-variants --arch x86_64 --strict
[  1/3] alpine-x86_64-hardened_malloc-rust-global-static-pie-distro        ok
[  2/3] alpine-x86_64-hardened_malloc-rust-global-static-pie-distro-light  ok
[  3/3] alpine-x86_64-system-baseline-static-pie-distro                    ok
alloc-bench: validation -> 0 error(s), 4 warning(s)
```

 **The acceptance criterion, from the two cells' own `build_flags`:**

```
…-distro-light   make VARIANT=light   CONFIG_NATIVE=false …
…-distro         make VARIANT=default CONFIG_NATIVE=false …
```

#### What the suite needed first

 **`HM_VARIANT` was plumbed and unreachable.** It reached the recipe and the
allocator cache key; `variants` sat on the allocator spec being parsed and never
read. **No suite could set either**, so only the default had ever been built.
Suites gained a `variants` key and the planner expands it per allocator.

 **The cell id gains a variant segment only when the variant is NOT the
default**, so all 146 existing cells keep byte-identical ids and no published
dataset, rolling-window run or `baseline_id` lookup is orphaned. `plan --suite
all` goes 146 → **147**, +1 planned, unsupported unchanged at 44.

 **And the row label needed it too.** Both variants land in the **same**
comparison group, so the first real `rankings.json` printed `hardened_malloc`
twice, identically labelled, with different numbers. Found by reading it.

### What it answers

 **`light` is 48.7% and 50.9% faster than the default configuration** in the
two runs, far outside every MAD in both (1.2–4.8%). And it **changes
hardened_malloc's position against the control**, which is what the entry asked:
0.729× and 0.665×, outside the MADs both times.

 **Memory is the reliable axis and the large one.** Peak RSS came out at
**1.178×** (`light`) and **2.875×** (default) of the control in *both* runs, to
three decimal places - a **2.44×** reduction. Nothing else in this dataset is
that stable.

 **What the second run REMOVED:** run A put the default at 1.084× - 8.4%
slower than musl against 1.2%/4.1% MADs, a result - and run B put it at
**1.003×**, level with the control and inside its own noise.  So *"hardened
malloc's default is slower than musl"* is **not established**, and `core` does
not settle it either (1.075×, 0.890×, 1.225× on three machines).

 **Upstream's `light` is five settings**, diffed from `config/*.mk` at the
pinned commit: `WRITE_AFTER_FREE_CHECK` and `SLOT_RANDOMIZE` off, both slab
quarantines to 0, `GUARD_SLABS_INTERVAL` 1 → 8.  **No security claim is made
here**, per the entry - what those settings are worth is upstream's question.

 Binary size is **24 bytes** apart between the variants. They are `-D` values,
not code paths.

---

## T-016: a worked path from "this benchmark says X" to "here is how I do it"

**Source:** raised by the operator on 2026-09-03, alongside
[`T-015`](instrument.md), and from outside a backlog that had no open entries.
**Category:** mechanisms
**Priority:** P1
**Effort:** L
**Status:** done

### Problem

 **Every mechanism in this project is implemented, measured and documented as
this project's own build pipeline, which is not a form anybody else can use.**
`docs/AGENTS.md` §4 names four mechanisms and cites `run-cell.sh`,
`libc-surgery.sh` and `alloc-runner` for each. A reader who wants the *result*
of that work - an image whose binaries use a different allocator - has to
reverse-engineer it out of an orchestrator.

 **And the harder half is not "how", it is "how do I know it worked".** The
project's central premise (§2.2) is that a wrongly-installed allocator is
**silent**: the program runs, the tests pass, the system allocator serves every
allocation, and the numbers are published under the other allocator's name.
Nothing in this repository told an outside reader how to check that on their own
binary without building `alloc-runner`.

 **Coverage was also narrower than the claims.** Every measurement is Alpine,
Debian or Arch. "musl" appears throughout as though it were established across
musl distributions; it had only ever been exercised on Alpine.

### Approach

Four runnable examples, each in the distribution it is about, each using only
that distribution's own package manager, compiler and binutils - no part of this
repository is required inside the container. Each writes a committed transcript.

| # | distribution | mechanism |
| --- | --- | --- |
| 10 | `debian:latest` | `LD_PRELOAD`, distro package, plus `/etc/ld.so.preload` |
| 20 | `ubuntu:latest` | `LD_PRELOAD`, mimalloc built from a pinned commit |
| 30 | `alpine:latest` |  `libc.a` surgery, then `cc -static-pie` with no flags |
| 40 | Void Linux musl | the same surgery, on a second musl |

Plus a shared verification vocabulary (`examples/verify.sh`) and a subject
(`examples/allocprobe.c`) that is **able to fail**: it writes a pointer-derived
pattern into every allocation and reads it back, asserts `calloc` zeroes and
`posix_memalign` aligns, runs from several threads, and carries a known-answer
search whose expected count is arithmetic rather than a golden file.

### Prove

```sh
sh examples/run.sh
python3 scripts/check-docs.py
```

Exit 0, with every example's transcript under `examples/out/` naming the
distribution version, libc version and compiler that produced it.

### Done, 2026-09-03

```
=== 10-debian-preload  (debian:latest) ===              9 passed, 0 FAILED
=== 20-ubuntu-preload  (ubuntu:latest) ===             11 passed, 0 FAILED
=== 30-alpine-static-pie  (alpine:latest) ===          16 passed, 0 FAILED
=== 40-void-musl-static  (void-musl-busybox:latest) === 12 passed, 0 FAILED
run.sh: 4 example(s) ran, 0 failed.
```

 **The Alpine example does the thing this repository is about, end to end**:
mimalloc built as a PIC static archive, seven musl members derived and deleted
from `libc.a` under a guard that refuses any member defining `fork`,
`pthread_create`, `printf`, `open`, `close`, `memcpy`, `read`, `write`,
`execve` or `mmap`, exactly one `malloc` and one `free` asserted to survive, and
then `cc -static-pie -O2 -pthread` with **nothing allocator-shaped on the
command line** producing a binary that contains `mi_malloc`, does **not** contain
musl's mallocng internals `nontrivial_free`/`get_meta` - **which the same build
before the surgery does contain**, so the control fires - has no `NEEDED`
entries, survives 8 threads × 30 000
mixed allocations, returns the exact needle count, and shows **6 distinct load
addresses in 6 runs**.

 **Void confirms it is a musl technique rather than an Alpine one.** The same
`musl-libc-surgery.sh`, unchanged, on a distribution sharing no packaging, no
toolchain configuration and no patch set with Alpine.

>  **Corrected by [T-018](#t-018-the-surgery-is-not-a-musl-technique-and-one-of-its-guards-could-not-fail), 2026-09-03.** Two musl distributions, not
> three. Chimera's musl ships mimalloc inside `libc.a`, in a member that also
> defines `__malloc_tls_default` - referenced by `pthread_create.lo`. The
> technique needs a libc whose allocator members are referenced only by
> allocation code, which is narrower than "musl". The script now refuses there,
> with the symbols named.

###  Three claims the transcripts DISPROVED, all of them mine

This is the half worth reading.

1.  **"The naive link fails with `multiple definition`."** It does not. `cc
   -static-pie prog.c libmimalloc.a` **links**, and the binary contains mimalloc
   and none of musl's allocator. The nine-symbol collision `docs/AGENTS.md` §5.1
   measures is a **Rust** link, whose std drags in objects referencing musl's
   internal `__libc_malloc`.  The honest objection to the naive approach is
   worse than "it fails": *whether it works is a property of your program's link
   closure*, and it changes when someone adds a library call. Corrected in the
   example, in `docs/replacing-the-allocator.md` §5.2, and stated with both
   halves.
2.  **"`cc -static` gives you a non-PIE binary."** Alpine's gcc is
   `--enable-default-pie`, so `-static` yields a **static-PIE** and the ASLR
   contrast was comparing a static-PIE with itself. `-static -no-pie` is
   required.  Same shape as the `-fno-PIC` without `-fno-PIE` trap already
   recorded in `allocators/lib.sh`: the flag that names the property is not the
   flag that turns it off.
3.  **"Appending the CA bundle to the trust store is enough."** It is enough
   for `apk`, `apt` and `curl`. It is **not** enough for an OpenSSL **hashed
   directory**, which is looked up by subject hash and reads only the FIRST
   certificate in a file - so a 152-certificate bundle dropped in as one file
   trusts one certificate and silently ignores 151. Void's `xbps` refused until
   the bundle was split into 152 single-certificate files, each hash-linked.
    The same shape as `docs/AGENTS.md` §6.1's "the 2-certificate file was not
   enough": *which certificate a client can see depends on how it looks*.

 **And a guard that fired wrongly cost a whole run.** `trust_extra_ca` first
asked whether the bundle's FIRST certificate was already in the store - and it
was, because the bundle leads with a public root every distribution ships. So it
reported "already present", appended nothing, and Alpine's `apk` then failed
with *"no such package"*.  This session's own rule says a guard that cannot
fail is not a guard; this is its mirror image, **a guard that fires wrongly
disables what it guards, silently**. Replaced with a marker file.

 **What this does NOT establish.** No example times anything, and none of them
says replacing the allocator is a good idea: on glibc every preloaded allocator
this project has measured is **slower than or level with** glibc's own, and not
one has beaten it. The
examples establish that the mechanisms work outside this repository's images and
that a reader can check their own binary - nothing more.

---

## T-018: the surgery is not a musl technique, and one of its guards could not fail

**Source:** `examples/60-chimera-musl.sh` failed on its first run, 2026-09-03,
with an `ar` error; the investigation found three further defects, two of them
in claims T-016 had written the same day.
**Category:** mechanisms
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

`examples/60-chimera-musl.sh` - the third musl distribution, added so that "this
is a musl technique" would rest on three distributions rather than two - failed
with `ar: error: script line 1: unknown command: OPEN`. The obvious reading was
a portability bug in one line of `musl-libc-surgery.sh`.

 **The obvious reading was the smallest of four findings, and the example's
own header comment was wrong about two more.** T-016 shipped that file
asserting four Chimera properties from reading rather than from measurement, and
its first transcript contradicted two of them on screen, three lines under the
comment claiming them.

### What the probe established

| question | answer |
| --- | --- |
| does llvm-ar accept MRI `OPEN`? |  **no** - it implements a subset. GNU ar accepts it, which is exactly why the defect was invisible on Alpine and Void |
| does `CREATE` + `ADDLIB` work in both? |  yes, and on Alpine the spliced archive installs, links and **runs** - so the fix is one code path, not a branch on which `ar` is present |
| is `/usr/lib/libc.a` really absent on Chimera? |  absent until `base-devel-static`, then present. `/lib` is a **symlink** to `usr/lib`; both paths are the same file |
| does llvm-nm print `libc.a(member):` headers? |  **not on this version** - bare `aio.lo:`, same as GNU nm |
|  what allocator is in Chimera's `libc.a`? |  **mimalloc.** A `mimalloc.o` member defining `__libc_malloc_impl`, `_mi_heap_main` and 83 more. mallocng's `nontrivial_free` and `get_meta`: **0** |
|  can `__bin_chunk` fail as a negative control? | **no.** Count in Alpine's `libc.a`: **0**. In Chimera's: **0**. musl dropped oldmalloc in 1.2.1 |

### Approach

Ask the image rather than the comment. `experiments/110-chimera-ar-mri.sh` puts
each of the four claims to `chimeralinux/chimera:latest` and puts the proposed
`ar` fix to both Chimera and Alpine, so the fix has a positive control on a libc
that is not entangled.

### The finding that matters

Chimera's `mimalloc.o` also defines **`__malloc_tls_default`**, a data symbol
that `pthread_create.lo` and `__init_tls.lo` reference. The threading code is
wired into the allocator object. So:

- the existing guard - *refuse a member that also defines something unrelated* -
  passes it cleanly, because the member defines nothing unrelated;
- the splice then succeeds, producing an archive with exactly one `malloc`;
- and the **link** fails, several steps later, with `undefined hidden symbol:
  __malloc_tls_default`, which says nothing about surgery.

 **The mechanism needs a libc whose allocator members are referenced only by
allocation code.** That is narrower than "musl", and T-016's claim that three
musl distributions take the same unedited script is withdrawn: two do.

### What changed

1. `musl-libc-surgery.sh` emits `CREATE`/`ADDLIB` instead of `OPEN`.
2. It gained a **second guard**, looking at references rather than definitions:
   if deleting the candidate members would strand a symbol the surviving members
   still reference (`U`, not weak) and the replacement does not define, it
   refuses with **exit 3** and names the symbols. On Chimera it names three.
3. `examples/60` was rewritten around the refusal, and then **forces the
   deletion anyway** so the transcript carries the linker error the guard
   prevents.  A guard nobody has seen fire is a comment.
4. `want_no_symbol __bin_chunk` is gone. `examples/verify.sh` gained
   `want_displaced`, which takes the pre-surgery binary as well and reports
   "absent from both" as **no evidence** rather than as a pass. Examples 30 and
   40 now build an untouched binary first; both transcripts show the mallocng
   count going 2 → 0.
5. `verify-selftest.sh` covers the new check with three planted cases - survived,
   absent-from-both, and the passing direction - 19 in total.

### Prove - run, with the output

```
$ sh experiments/110-chimera-ar-mri.sh ; echo "rc=$?"
...
  PASS  OPEN is rejected -- this is the observed failure, reproduced
  PASS  the CREATE form parses
  PASS  all 6 members are gone from the spliced archive
  PASS  it does not link, and the undefined symbol is Chimera's allocator TLS
  PASS  GNU ar accepts the same CREATE script -- one code path serves both
  PASS   it links -- CREATE produces a working archive
  PASS  and the binary runs and returns 0
rc=0
```

```
$ sh examples/run.sh 30 40 60
  16 passed, 0 FAILED   -> PASS  30-alpine-static-pie
  12 passed, 0 FAILED   -> PASS  40-void-musl-static
  11 passed, 0 FAILED   -> PASS  60-chimera-musl
```

 In example 60's transcript the new guard refuses with **exit 3**, naming
`__malloc_init`, `__malloc_tls_default` and `__malloc_tls_teardown`; section 7
then forces the deletion and the link fails on `undefined hidden symbol:
__malloc_tls_default` - the symbol the guard predicted. In 30 and 40 the same
guard passes, and `want_displaced` reports the mallocng markers going from
present to absent.

 **Example 60 has 11 checks and not 13, and the two it lost are the point.**
The first version of the rewrite asserted `want_no_symbol … nontrivial_free
get_meta` on the Chimera binary - mallocng markers, on a distribution whose
`libc.a` section 3 had already counted them in at **zero**. Two more assertions
that could not fail, in the file whose whole subject is assertions that cannot
fail. They are gone, and the transcript now says in words that no negative
control is possible there, because the allocator the surgery would install is
the one already present.

```
$ docker run --rm -v "$PWD/examples:/examples:ro" debian:latest \
      sh /examples/verify-selftest.sh
19 case(s), 0 failures
```

### Done, 2026-09-03

All five changes above are in, all six examples pass, and the probe exits 0.

###  What it does not establish

- **Anything about Chimera's performance.** The distribution is not in the
  matrix, and this work never timed anything on it.
- **That no other distribution does the same thing.** Three musl distributions
  were examined and one was entangled. The guard now finds the next one; nothing
  here predicts how many there are.
- **That the project's own measurements were affected.** They were not:
  `crates/alloc-runner/src/ident.rs` has always keyed on `__libc_malloc_impl`,
  `__malloc_donate`, `alloc_meta`, `get_meta` and `nontrivial_free`. The vacuous
  control was in the examples layer, written this session, and never gated a
  published number.  Its comment did claim `__libc_malloc_impl` was
  "oldmalloc"; the symbol list was right and the sentence was not.

---

## T-019: the production surgery asked about four names it had written down

**Source:** [T-018](#t-018-the-surgery-is-not-a-musl-technique-and-one-of-its-guards-could-not-fail)
found the examples layer keying on a symbol that no longer exists. Re-reading
`scripts/build/libc-surgery.sh` for the same shape of defect found one.
**Category:** mechanisms
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

 **The file that criticises the prior art for a standing list uses one.**
`scripts/build/libc-surgery.sh`'s header says the prior art deletes a fixed
list of musl object names and that deriving from the archive "cannot go stale".
Its own post-splice check then asks:

```sh
ALIAS_CANDIDATES='__libc_malloc,__libc_free,__libc_calloc,__libc_realloc'
missing=$("$RUNNER" ar-unresolved --archive "$tmp/libc.a" --symbols "$ALIAS_CANDIDATES")
```

Four names, derived once, from the distributions this project had looked at.
Chimera strands `__malloc_tls_default`, which is on nobody's list: the delete
succeeds, the malloc/free assertions pass, and the failure arrives as a link
error in somebody's program naming threading code.

 **No published number was wrong because of this.** The failure it misses is
*loud* - an unresolved symbol fails the link, the cell is recorded
`build_failed`, and nothing enters a ranking. What it costs is a diagnosis:
`undefined hidden symbol: __malloc_tls_default` says nothing about surgery.

 **A second, smaller one in the same file:** the alias-add step still emitted
MRI `OPEN`, which llvm-ar rejects. The splice above it already used `CREATE`, so
a musl distribution with LLVM binutils would have failed at the *second* `ar`
call having passed the first.

### Approach

`ar::stranded(spliced, baseline)` - the names `spliced` references and no longer
defines, **which `baseline` did define**.

 **The baseline is what makes it safe to ask without a list.** A static
`libc.a` legitimately references plenty it never defines - compiler builtins,
`__stack_chk_fail`, symbols the crt supplies. Requiring that the original
defined it removes every one of them by construction: they were undefined before
the splice too, so they cannot be something the splice broke. That is the whole
reason `unresolved` needed a candidate list and this does not.

Exposed as `ar-unresolved --archive PATH --baseline PATH`, and wired into
`libc-surgery.sh` as a **refusal** after the synthesis step.

### Prove - run, with the output

 **Measured before it was allowed to refuse.** A check that refuses working
archives is worse than the gap it closes, so the question was asked against real
`libc.a`s first (`experiments/120-stranded-on-a-real-libc.sh`):

| distribution | replacement supplies | reported |
| --- | --- | --- |
| alpine | the plain entry points only | `__libc_free __libc_malloc` |
| alpine |  **also the four aliases** (what synthesis achieves) |  **nothing** |
| chimera | the plain entry points only | `__libc_calloc __libc_free __libc_malloc __malloc_tls_default` |
| chimera |  **also the four aliases** |  **`__malloc_tls_default`** |

So on the distribution every one of this project's `libc-surgery` numbers came
from, the new check is silent; on Chimera it catches what no list had.

Then the production script itself, end to end, on real images
(`experiments/130-libc-surgery-after-the-guard.sh`):

```
alpine:  surgery:   displacing 13 member(s): aligned_alloc.lo calloc.lo donate.lo …
         surgery:   __libc_calloc __libc_free __libc_malloc -- …; synthesising
         surgery:   nothing stranded -- every symbol the deleted members defined
         surgery:   is either supplied or no longer referenced
         surgery: patched 1 libc.a copy/copies and verified each
         exit status: 0
         -- link and RUN something against the spliced archive
            it links / and it runs, exit 0
            standin_marker in the binary: 1
            mallocng internals left:      0
```

 **The Alpine half links a program against the spliced archive and RUNS it**,
with the stand-in's own symbol present and zero mallocng internals left. A
passing assertion about an archive is not a working libc.

Instrument: `alloc-runner selftest` gained three cases, including the one that
matters -  **a symbol undefined in the spliced archive AND in the baseline
must NOT be reported**, or the check refuses every working `libc.a` there is.

### Done, 2026-09-03

`ar::stranded`, the `--baseline` flag, three selftest cases, the refusal in
`libc-surgery.sh`, and `OPEN` → `CREATE` in the alias-add path.

###  What it does not establish

- **That no other distribution strands something after synthesis.** Two libcs
  were asked.  The point of deriving rather than listing is that the third one
  does not need this entry re-opened - it needs the check to fire.
- **That the refusal is right to be fatal.** A distribution that strands a
  symbol which nothing in a given program's link closure reaches would now be
  refused where it might have linked.  That is deliberate, and it is the same
  argument as `link-override`: an image whose allocator replacement works for one
  binary and silently does not for the next is worse than one that refuses.
