# `mechanisms` on alpine/x86_64 - run C, the first across all allocators

Runs A and B are in [`../2026-09-01-mechanisms-x86_64/`](../2026-09-01-mechanisms-x86_64/)
and covered **mimalloc only**. This run covers **every allocator in the suite**:
16 cells, `alpine` / `x86_64` / `static-pie`, 8 samples, host
`Intel(R) Xeon(R) Processor @ 2.10GHz`.

##  Which tree produced these numbers, and how to get it

 **This section previously read "image built at `194ed63`". That was wrong**,
and `run.json` - the machine-recorded half - says so. Corrected 2026-09-02;
`../../../docs/history/README.md` carries the withdrawal.

| | |
| --- | --- |
| `run.json` `git_commit` | `e24709ba1f9bba9a40de5d38e55b186df17d83e7` |
| image digest, all 16 cells | `sha256:a0631865…` |
| run B's image digest, for contrast | `sha256:6989b3c4…` |

 **So it is not run B's image either.** `194ed63` is the commit run B recorded
23 minutes earlier, and the two runs used **different images** - run C built its
own. Nothing in the tree supports attributing run C to `194ed63`.

 **`e24709b` is not reachable from `main`.** It is the head of the branch
squash-merged as [`efc84ab`](https://github.com/Azathothas/alloc-bench/commit/efc84ab)
(PR #1), so in an ordinary clone `git cat-file -t e24709b` answers *"could not
get object info"* - the same wound that once broke `docs/AGENTS.md`'s own
vintage line. The object is still on the remote, behind the pull request's ref:

```sh
git fetch origin 'refs/pull/1/head:refs/remotes/origin/pr-1-head'
git cat-file -t e24709ba1f9bba9a40de5d38e55b186df17d83e7   # commit
```

 **Do not substitute `efc84ab` for it.** They are not the same tree:
`git diff --stat e24709ba efc84ab` reports **64 files changed, 25164
insertions(+), 150 deletions(-)** - the squash carried this very snapshot, which
was committed *after* the run.

 `scripts/check-snapshots.py` now asserts this: a snapshot naming a commit HEAD
cannot reach must document the route to it, or the check fails.

**Outcome: 7 `ok`, 9 `build_failed`, 0 errors from the validator.**
 The nine failures are the result, not a broken run.

## Which mechanisms actually work

| allocator | `rust-global` | `libc-surgery` | `link-override` |
| --- | --- | --- | --- |
| mimalloc |  0.597× |  **0.523×** |  multiple definition |
| jemalloc |  0.591× |  undefined `__libc_malloc/free/calloc` |  |
| snmalloc |  0.608× |  undefined `__libc_malloc/free` |  multiple definition |
| rpmalloc |  0.613× |  allocator build fails |  allocator build fails |
| hardened_malloc |  0.951× |  undefined `__libc_malloc/free` |  |
| system |  1.000× (control) | - | - |

##  The headline: `libc-surgery` works for mimalloc and no one else

The `mechanisms` suite existed to test "replace the distribution's allocator" as
a general technique. Run across five allocators for the first time, it replaces
exactly one.

The reason is specific and it is in `evidence/`. Deleting musl's malloc members
from `libc.a` leaves musl's **own** remaining objects still referencing the
musl-internal aliases `__libc_malloc`, `__libc_free` and `__libc_calloc`. The
replacement archive has to supply them.

 **Five musl objects reference them, not one.** Read off the logs in
`evidence/`: `src/ldso/dlerror.c`, `src/exit/atexit.c`,
`src/thread/pthread_atfork.c`, `src/process/posix_spawn_file_actions_destroy.c`
and `src/process/posix_spawn_file_actions_addchdir.c`. For snmalloc and
hardened_malloc, `dlerror.c` does not appear in the extract at all.  These are
60-line tails, so the list is what they show and **not** a proof of completeness;
the full logs are not published.

| allocator | undefined after the surgery |
| --- | --- |
| mimalloc | *none - links* |
| jemalloc | `__libc_calloc`, `__libc_free`, `__libc_malloc` |
| snmalloc | `__libc_free`, `__libc_malloc` |
| hardened_malloc | `__libc_free`, `__libc_malloc` |

 **mimalloc happens to define those aliases; the others do not.** This is the
same alias recorded in `docs/AGENTS.md` §12 item 12, where mimalloc defining
`__libc_malloc` made a correctly-displaced musl binary look like it still
contained glibc's allocator and failed the identity gate. **The quirk that broke
the negative control is the quirk that makes the surgery link.**

 So `libc-surgery` is not a general technique that was merely tested on
mimalloc first. As implemented it depends on a mimalloc-specific accident, and
the prior art it came from
(`https://github.com/haskell-wasm/rust-alpine-mimalloc`) is a mimalloc project - quite
possibly for this reason.

 **rpmalloc fails earlier and differently**, and is the one entry here that
looks fixable: its own build breaks in override mode with
`'_ZdaPv' aliased to undefined symbol 'rpfree'`, a C++ operator-delete alias, so
no archive is produced at all. That is a recipe bug, not a musl one.

## The mechanism comparison, now three runs deep

mimalloc, the only allocator that can be compared across mechanisms:

| mechanism | run A | run B | run C | rel peak RSS (C) |
| --- | --- | --- | --- | --- |
| `libc-surgery` | **0.444×** | **0.460×** | **0.523×** | 3.465× |
| `rust-global` | 0.501× | 0.606× | 0.597× | 3.470× |

 **The surgery beat the shim in all three runs** - by **13%, 32% and 14%**,
each figure being the shim's ratio divided by the surgery's, minus one. This is
the only comparison in this project that has survived repetition, and it did so
across a change of CPU (see `docs/AGENTS.md` §11.1). Peak RSS is identical
between the two mechanisms, as expected when both run the same allocator and
differ only in how much of the program reaches it.

 **This was published as "13%, 32% and 12%" and the 12% was wrong.** It was
`(shim − surgery) / shim`, a different statistic from the other two figures.
`0.5966 / 0.5230 − 1 = 14.1%`. `docs/history/README.md` carries the withdrawal.

 **The magnitude is still not established** - 13%, 32%, 14%, against internal
MADs of 1.6–4.3%. Publish the direction.

## Reading the evidence files

`evidence/libc-surgery-<allocator>.txt` is the tail of each cell's real
`build.log`.  Use those, not `logs/<cell>.log` from a run directory: the latter
is an 11-line tail whose last line is an incidental
`undefined reference to __stack_chk_fail`, which is not the cause and will
mislead you if you take it for one.
