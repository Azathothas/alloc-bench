# `preload`, x86_64, 2026-09-03 -  Google tcmalloc's first number, ever

**This is the run in which the last allocator in the registry stopped being a
gap.** All eight now have a measurement.

| | |
| --- | --- |
| suite | `preload` |
| cells | 16 - **15 `ok`, 1 `unsupported` with its reason** |
| validation | **0 errors**, 6 warnings (startup-time MADs above 5%, the usual small-corpus noise) |
| commit | `c13689af1894bea6aeacec96fdfc7b1e78559afc`, and `git_dirty: false` |
| machine | **AMD EPYC 9V74 80-Core Processor**, 4 cores visible |
| dispatch | bench [`33729832142`](https://github.com/Azathothas/alloc-bench/actions/runs/33729832142), job `x86_64` |
| corpus seed | 20260901 |

 **A third CPU model for this suite**, after a Xeon @ 2.80GHz and an EPYC 7763.

##  tcmalloc

```
debian / x86_64 / dynamic / distro
   tcmalloc   1.266×   lead −26.6%   MAD 2.5%
```

**Slower than glibc's allocator, by well outside its own spread** - which is what
every other candidate does on glibc in every run this project has taken, so it is
the expected shape rather than a surprise.

 **`alpine` is `unsupported`, with the reason printed rather than dropped:**
*"upstream does not support musl; the Bazel build requires glibc-specific
interfaces."* That refusal is real and is upstream's, and it is the only one of
tcmalloc's four recorded refusals that ever was.

### How it took four runs to get here

Each earlier refusal was a different wall, and **three of the four were this
project's own instrument rather than the allocator**:

| # | what it said | what it was |
| --- | --- | --- |
| 1 | musl unsupported |  real, and upstream's |
| 2 | "the bazel build failed" |  **the dev host's TLS interception**, `PKIX path building failed` in bazelisk's own JDK - reported as a build failure |
| 3 | "no shared object under `bazel-bin`" |  **`find`'s default `-P` will not follow a symlink**, and `bazel-bin` is one |
| 4 | "does not EXPORT malloc free realloc calloc" + an **empty list** |  **a mute diagnostic**: every check was `nm … 2>/dev/null \| grep -q …`, so the status read was grep's and an unreadable file looked identical to an empty one. [`T-024`](../../../docs/history/todo/instrument.md) |

 **This run is the one after that fix**, and the answer it gives is neither of
the two the mute diagnostic could not distinguish: the generated
`cc_binary(linkshared = 1)` target produces a shared object that **does** export
the four symbols, the loader maps it, and the cell measures. The recipe was right
from the run before; only the report of it was not.

## Reading it

`report.md` carries the tables and the conditions.  Its `## Rankings` section
opens by naming this machine, because every ordering in it is a statement about
this machine and nothing else - `docs/AGENTS.md` §11.1.

 **`cells/` and `logs/` are not committed**, as with every snapshot here: a
whole dataset is tens of megabytes. The full artefact is attached to the bench
run linked above for 90 days.
