# `preload` - the mechanism's first run ever, and the first cells where the binary is identical across the whole table

`benchmarks/matrix.toml` has declared a `preload` suite since the matrix was
written, `allocators.toml` has declared `preload` support for six allocators,
and **no recipe implemented `MODE=preload`**, so every one of those cells would
have failed. [`T-003`](../../../docs/history/todo/mechanisms.md).

12 cells, 10 samples. **8 `ok`, 4 `unsupported` with reasons, 0
`build_failed`, 0 validator errors, 30 `noisy` warnings.**

 **Every candidate in a group runs the byte-identical binary.** `preload` does
not rebuild the application - it interposes at load time - so the `size` column
is 7.87 MiB for all four Alpine rows and 7.94 MiB for all four Debian rows.
Every other mechanism this project measures changes the binary; this is the only
table where the *only* difference between rows is which allocator served the
allocations.

## Conditions

| | |
| --- | --- |
| run id | `20260902-130704`, started 2026-09-02T13:07:04Z |
| `git_commit` | `230f48282a19…` |
| `git_dirty` / `git_untracked` | **false** / **0** |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
| corpus | `standard`, seed 20260901 |

 **Quiescence:** no container build, `cargo` invocation or other benchmark
overlapped the measured cells. The session was editing documents alongside;
nothing heavier than that ran.

##  The identity gate this mechanism needs, and why the ELF cannot give it

A preload cell's allocator is **not in its binary**. The binary is an ordinary
system build; the allocator arrives at load time. So the ELF oracle that
identifies every other mechanism has nothing to read - and the failure it exists
to catch is silent: under `LD_PRELOAD` a missing, unreadable, ABI-wrong or
declined library does not error. The loader shrugs, the process runs the libc
allocator at libc speed, and the numbers are filed under the other allocator's
name. That is `docs/AGENTS.md` §2.2 arriving through a different door.

`alloc-runner preload-check` takes the evidence from **outside the process,
while it runs** - and it is three things, all of which must hold:

| # | what | how |
| --- | --- | --- |
| 1 | the library is the allocator it claims to be | the ordinary symbol oracle, applied to the `.so` |
| 2 | the loader mapped it into the subject | fork the real `rg` with `LD_PRELOAD`, read `/proc/<pid>/maps` from the parent |
| 3 |  it is **absent** without `LD_PRELOAD` | the same probe, the same path, no variable |

**Every `ok` cell in this dataset, from its own `preload.json`:**

| cell | with `LD_PRELOAD` | without (control) |
| --- | --- | --- |
| `alpine-…-jemalloc-preload-…` | **4 of 4** sampled | **0 of 4** |
| `alpine-…-mimalloc-preload-…` | **4 of 4** | **0 of 4** |
| `alpine-…-snmalloc-preload-…` | **4 of 4** | **0 of 4** |
| `debian-…-jemalloc-preload-…` | **4 of 4** | **0 of 4** |
| `debian-…-mimalloc-preload-…` | **4 of 4** | **0 of 4** |
| `debian-…-snmalloc-preload-…` | **4 of 4** | **0 of 4** |

each with the `/proc/<pid>/maps` line kept verbatim.  **(3) is what makes (2)
mean anything**, and it was not decorative:
[`../../../experiments/90-preload-residency.sh`](../../../experiments/90-preload-residency.sh)
found **three** defects in this check before a single cell ran - a control that
never searched and so could not fail, a reader that could not match a path
through a symlinked directory, and a poll that stopped as soon as the subject's
own text was mapped, which is *before* `ld.so` maps anything and reported glibc
itself as absent from every process on the host.

## What it measures

`literal`, each allocator against the control **in the same image**, on the
`dynamic` profile - the only profile `preload` can use, because a static binary
has no loader to interpose.

| allocator | alpine (musl) | debian (glibc) |
| --- | --- | --- |
| snmalloc | **0.648×** | 1.082× |
| jemalloc | 0.750× | 1.154× |
| mimalloc | 0.768× | 1.188× |
| system *(control)* | 1.000× | 1.000× |
| *MADs* | *3.8–8.5%* | *5.6–11.6%* |

 **On musl all three beat the control**, and snmalloc leads by **15.8%**,
outside the run's 4.1% spread - a named winner.

 **On glibc all three are SLOWER than the control**, by 8–19%.  The top gap
is 8.2% against a 10.5% MAD, so no ordering is named *among them*; what the run
does say is that none of them beat glibc's allocator here.

 **That is the `distros` finding arriving independently through a different
mechanism.** [`../2026-09-02-distros-x86_64/`](../2026-09-02-distros-x86_64/)
found the same shape with `rust-global`: large wins on musl, nothing or worse on
glibc. Two mechanisms, one conclusion - *what the alternatives mostly buy you is
an escape from musl's allocator*.

 **These numbers are not comparable with the static tables**, and the report
keeps them apart for that reason: a dynamic binary going through the PLT is a
different binary.  The separation is enforced by the *profile* being part of the
ranking group key, not by any rule naming `preload` - `plan.rs::judge` confines
preload to `dynamic`, and that is what keeps the tables apart.

### Peak RSS

| allocator | alpine | debian |
| --- | --- | --- |
| mimalloc | 3.289× | 3.110× |
| snmalloc | 1.528× | 1.369× |
| jemalloc | 1.339× | 1.261× |

 Consistent with `distros` on the same host (mimalloc 3.0–3.5×, jemalloc
1.40–1.57×) -  though jemalloc's preload figure (1.26–1.34×) is below its
`rust-global` figure, which is a difference this run records and does not
explain.

##  Mesh and Google tcmalloc still have no numbers

They support no other mechanism, so this was the entry's headline goal and it is
**not met**. Both refuse with a reason, which is a published result, and both
reasons are sharper than they were:

**Mesh - the build succeeds and produces no library.**
`evidence/mesh-no-artefact.txt` lists what it left, on both distributions: every
object of the `mesh` target (`libmesh.cc.o`, `runtime.cc.o`, `meshable_arena.cc.o`,
`d_assert.cc.o`), a complete googletest build, the unit-test objects - and **not
one `.so` or `.a` anywhere under the build tree**.  Previously the recipe said
"produced neither a static archive nor a shared object", which is a claim about
a directory that does not say what is in it; it now prints the artefacts.  What
is *not* established is why the link step yields nothing - whether upstream's
`mesh` target is an object library, or its shared-library link is behind a CMake
option this recipe does not set. Nobody has looked.

**tcmalloc - a TLS trust failure in the JVM, on this network.**
`evidence/tcmalloc-bazel-tls.txt`. Bazel resolves its module graph from
`bcr.bazel.build`, and:

```
ERROR: Error computing the main repository mapping: Error accessing registry
https://bcr.bazel.build/: … TLS error: (certificate_unknown) PKIX path building
failed: sun.security.provider.certpath.SunCertPathBuilderException
```

 **That is a property of this host, not of tcmalloc or of Bazel 8.6.0.**
bazelisk downloads its **own** JDK at run time, and that JDK's `cacerts` is not
`/etc/ssl/certs/ca-certificates.crt` - so the proxy CA the image trusts, which
`curl` and `apt` honour, is invisible to Java. Probed: the image contains no
`java`, no `keytool` and no `cacerts` at all, so it cannot be fixed at image
build time without adding a JDK.  The recipe now says this in its refusal
rather than reporting "bazel build failed", which read as an upstream
limitation and is not one. On Alpine the refusal is earlier and genuinely
upstream's: musl is not a supported platform.

## Files

`report.md`, `rankings.json`, `plan.json`, `run.json`, `results/*.json` (one per
cell, the `ok` ones carrying `preload.json`'s residency evidence inline), and
`validation.txt` - **0 errors, 30 warnings, 12 results**. `evidence/` is
hand-cut from the cells' `steps.log`: an `UNSUPPORTED` from an allocator recipe
never reaches a ripgrep `build.log`, so `scripts/report/extract-evidence.py` has
nothing to select from and says so.  No `cells/` or `logs/`, per
`docs/AGENTS.md` §11.2.
