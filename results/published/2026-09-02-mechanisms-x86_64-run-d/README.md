# `mechanisms` on alpine/x86_64 - run D, taken to settle a question about evidence

 **This run exists to answer one question**, not to add a number:
[`T-011`](../../../docs/history/todo/instrument.md#t-011-publish-the-build-log-with-the-failure-it-documents)
asked whether run C reproduced the nine-symbol `link-override` collision that
runs A and B recorded, because **run C's committed evidence contains no
`multiple definition` line at all** and the full log was never published. The
entry recommended re-running the cell rather than leaving a caveat in the
handoff forever. This is that re-run.

4 cells, `alpine` / `x86_64` / `static-pie`, mimalloc and the control, 10
samples. **3 `ok`, 1 `build_failed`, 0 validator errors.**

## Conditions

| | |
| --- | --- |
| run id | `20260902-013141`, started 2026-09-02T01:31:41Z |
| `git_commit` | `08ac3e5d755f8015ada526b0c4dc22ec0e53ff58` - reachable from `main` |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
| image | `alloc-bench/alpine-x86_64`, built this session |

 **The CPU model string matches run A's and not runs B or C's.** That is what
`run.json` records and is all it establishes; the sandbox VM has been re-hosted
before (`docs/AGENTS.md` §11.1) and a model string is not a machine identity.

##  The answer: the nine are the same nine

Measured on this run's own `build.log`, unpiped:

```
$ wc -c cells/alpine-x86_64-mimalloc-link-override-static-pie-distro/build.log
68719
$ grep -c 'multiple definition' …/build.log
9
```

`__libc_free`, `__libc_malloc`, `__libc_realloc`, `aligned_alloc`, `calloc`,
`free`, `posix_memalign`, `realloc`, `strdup` - exactly the nine in
[`../2026-09-01-mechanisms-x86_64/evidence/link-override-failure.txt`](../2026-09-01-mechanisms-x86_64/evidence/link-override-failure.txt),
and no others.

 **So run C reproduced the collision and its EVIDENCE FILE lost it.** The loss
is mechanical, and this log demonstrates it:

| what you keep of this 414-line log | `multiple definition` | `undefined reference` |
| --- | --- | --- |
| all of it | **9** | 210 |
| `tail -n 80` - the run-C method | **0** | 47 |
| `extract-evidence.py` - this snapshot's `evidence/` | **9**, ranked first | 25 distinct of 47, after them |

 A positional tail of this file keeps **none** of the finding and 47 lines of
`__stack_chk_fail` / `pthread_mutex_lock` noise. That is not a fact about run C;
it is what `tail -n 80` does to this log.

## The mechanism comparison, now four runs deep

| | run A | run B | run C | **run D** |
| --- | --- | --- | --- | --- |
| `libc-surgery` | **0.4435×** | **0.4603×** | **0.5230×** | **0.6439×** |
| its own MAD | 2.7% | 2.9% | 3.3% | **6.4%** |
| `rust-global` | 0.5014× | 0.6056× | 0.5966× | 0.6749× |
| its own MAD | 2.4% | 1.6% | 4.3% | 3.1% |
| shim ÷ surgery − 1 | **13.05%** | **31.56%** | **14.08%** | **4.82%** |

 **The direction held a fourth time**: the surgery was faster than the shim in
every run this project has taken.

 **But run D does not establish it on its own, and this is the honest
headline.** A 4.82% lead sits *inside* the surgery cell's own 6.4% relative MAD,
and this project's own rule is that a lead smaller than the run's MAD is
reported as no result. Run D is **consistent with** the direction and cannot
distinguish it from noise.

 **The magnitude is now known across a factor of six: 4.8%, 13%, 14%, 32%.**
Publish the direction. Nothing here supports a number.

 **Peak RSS remains the flat part.** `libc-surgery` 3.4658× the control,
`rust-global` 3.4688× - a 0.09% difference across two mechanisms running the
same allocator, which is what you would expect if they differ only in how much
of the program reaches it.

## `link-override` still fails, and that is the result

 Pulling mimalloc's archive in ahead of libc brings its compatibility aliases,
which collide with musl's own. **This is why the surgery deletes the displaced
members rather than merely linking ahead of libc.** `docs/AGENTS.md` §5.1.

## Reading `evidence/`

One file per failing cell, written by
[`../../../scripts/report/extract-evidence.py`](../../../scripts/report/extract-evidence.py).
Each carries a header naming the full log's byte count, how many diagnostic
lines matched, how many were elided, and - per class - what did not fit the
40-line budget.  **Nothing here was chosen by its position in the file.**

```sh
python3 scripts/report/extract-evidence.py --check \
  results/published/2026-09-02-mechanisms-x86_64-run-d/evidence \
  --expect 'multiple definition of .__libc_malloc'
```

 The full `build.log` is still not committed - 68 KiB for one cell, and a whole
dataset is tens of megabytes. What changed is that the extract is chosen by what
the failure *is*.
