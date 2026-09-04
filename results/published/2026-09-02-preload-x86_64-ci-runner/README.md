# `preload` on a second machine - the ordering inverts again, and tcmalloc's wall moves

The same 12 cells as [`../2026-09-02-preload-x86_64/`](../2026-09-02-preload-x86_64/),
on a GitHub runner. **8 `ok`, 4 `unsupported` with reasons, 0 validator errors,
6 `noisy` warnings.**

 **It was dispatched to test one hypothesis** - that tcmalloc's Debian failure
on the dev sandbox was the sandbox's TLS-inspecting proxy rather than anything
about tcmalloc.  **The hypothesis held and the answer is still not "tcmalloc
works":** see the last section, which is the most useful thing in this dataset.

## Conditions

| | |
| --- | --- |
| run id | `20260902-133258`, started 2026-09-02T13:32:58Z |
| `git_commit` | `c60ae40b1c6c…`, `git_dirty` **false**, `git_untracked` 2 |
| host | **`AMD EPYC 7763 64-Core Processor`**, 4 cores, kernel `Linux 6.17.0-1022-azure` |
| where | `ubuntu-24.04`, GitHub-hosted, native x86_64 |
| runtime | docker 28.0.4 |
| dispatch | `bench` run [`33636229346`](https://github.com/Azathothas/alloc-bench/actions/runs/33636229346), `suite=preload`, `arches=x86_64`, conclusion **`success`** |

 Its `roll` job created `results/rolling/preload-x86_64/` - the **second**
window CI has ever committed, both of them since the `T-014` fix earlier the
same day.

##  The ordering inverts between the two machines, again

`literal`, each allocator against the control **in the same image**:

| allocator | alpine, Xeon | **alpine, EPYC** | debian, Xeon | **debian, EPYC** |
| --- | --- | --- | --- | --- |
| jemalloc | 0.750× | **0.862×** | 1.154× | **1.017×** |
| mimalloc | 0.768× | **1.037×** | 1.188× | **1.247×** |
| snmalloc | **0.648×** | **1.206×** | 1.082× | **1.338×** |
| *MADs* | *3.8–8.5%* | *1.1–2.5%* | *5.6–11.6%* | *0.8–5.1%* |

 **snmalloc goes from the fastest row on musl (0.648×) to the slowest
(1.206×)**, and mimalloc crosses the control. On this machine **only jemalloc
beats musl's allocator**, by 16.0%, outside the run's 1.3% spread.

 **This is `docs/AGENTS.md` §11.1 for the fourth suite.** `core`, `profiles`,
and now `preload` each produce a confident, self-consistent ordering that the
other machine contradicts - and, as in every previous case, **the run that
disagrees reports the tighter MADs** (1.1–2.5% here against 3.8–8.5% on the
Xeon).  A within-run spread says nothing about whether a result transfers.

 **What survives both machines and both distributions:** jemalloc is the only
allocator that beats musl's allocator under `preload` on every machine measured,
and **on glibc nothing beats the control anywhere** - every candidate is slower
on Debian in both runs.

 **Peak RSS does not transfer either**, and the swing is large: jemalloc is
1.34× the control on the Xeon and **6.84×** here, on the byte-identical binary.
mimalloc 3.29× → 3.87×, snmalloc 1.53× → 3.45×. Same finding as
[`../2026-09-02-profiles-x86_64-ci-runner/`](../2026-09-02-profiles-x86_64-ci-runner/),
where jemalloc went 1.58× → 8.99×.

##  tcmalloc: the TLS wall was real, and it was hiding a second one

On the dev sandbox this cell died with
`TLS error: (certificate_unknown) PKIX path building failed` fetching
`bcr.bazel.build`, in bazelisk's own downloaded JDK. **Here it did not.** Bazel
resolved its module graph and built; the recipe reached its post-build search
and reported instead:

```
the bazel build produced no shared object usable for LD_PRELOAD under bazel-bin
```

 **So the TLS diagnosis was right** - that failure is a property of the dev
host's network and not of tcmalloc, and a runner without an intercepting proxy
gets past it.

 **And the new message is not a measurement either.** `bazel-bin` in a Bazel
workspace is a **symlink** into the output base, and `find` with its default
`-P` does not follow a symlink even when the symlink is the starting point.
Reproduced on the host rather than reasoned about:

```
ln -s real bazel-bin; touch real/libtcmalloc.so
find    bazel-bin -type f -name '*.so'   ->  0
find -L bazel-bin -type f -name '*.so'   ->  1
```

So the search could not look, whatever Bazel had produced, and the refusal
blamed the build.  **This cell is therefore evidence that Bazel built, and
evidence of nothing else.** Fixed to `find -L`, and the diagnostic now lists
`.a` files too - because `//tcmalloc:tcmalloc_deprecated_perthread` and
`//tcmalloc` are `cc_library` targets, and a `cc_library` yields an archive. If
that is all Bazel leaves, the question is which target to build, not whether
tcmalloc can be preloaded.  **The next dispatch answers it; this one does
not.** [`T-003`](../../../docs/history/todo/mechanisms.md).

 **Mesh fails identically to the dev host**, on both distributions: the build
succeeds and leaves no library. That one is not a network story and did not
change here.

## Files

`report.md`, `rankings.json`, `plan.json`, `run.json`, `results/*.json` (the
`ok` ones carrying the residency evidence - **4 of 4 resident with
`LD_PRELOAD`, 0 of 4 without**, every cell), `validation.txt` - **0 errors, 6
warnings, 12 results** - and `evidence/` for the tcmalloc finding.  No
`cells/` or `logs/`, per `docs/AGENTS.md` §11.2.
