# instrument

The tooling, the published evidence, and the checks that keep both honest.

[`INDEX.md`](INDEX.md) is the list. [`PROGRESS.md`](PROGRESS.md) is the work
order. Entries close **in place**, with the acceptance command actually run and
its output pasted underneath.

---

## T-014: `bench.yml`'s rolling-window commit has never once run

**Source:** found 2026-09-02 while looking for the `profiles` window the
previous session's work order says to publish, and finding no such directory.
**Category:** instrument
**Priority:** P1
**Effort:** S
**Status:** done

### Problem

`docs/AGENTS.md` §10 says `bench.yml`'s **`roll`** job "folds the dataset into
[`results/rolling/`](../../../results/rolling/) and commits the regenerated aggregate
to `main`".  **It has never committed anything.** Every dispatch to date
reports the job `success` and the "Commit the window" step `success`, and the
window it just built is thrown away.

### Premise

 **Measured, not read**, and in three independent places.

**1. The history is empty.**

```
$ git log --oneline --all --grep='Rolling aggregate'
$ git log --oneline --diff-filter=A -- results/rolling/core-aarch64 results/rolling/core-x86_64
54214e1 aarch64, measured for the first time - and the MAD rule the run demanded
fe324a8 Rolling window of the last 3 runs, with an aggregate that refuses to average them
```

Both windows in the tree were committed **by hand, in a session**. The job's own
commit message string has never appeared.

**2. Two runs folded a window and then said nothing.** Read from the job logs
through `api.gh.pkgforge.dev`:

| run | job | what the fold step printed | what "Commit the window" printed | its duration |
| --- | --- | --- | --- | --- |
| [`33582107102`](https://github.com/Azathothas/alloc-bench/actions/runs/33582107102) | `100100497388` | `aggregate: added 20260902-020947-ci33582107102` / `results/rolling/core-aarch64: 1 run(s)` | *(nothing)* | **4 ms** |
| [`33603002893`](https://github.com/Azathothas/alloc-bench/actions/runs/33603002893) | `100167382509` | `aggregate: added 20260902-072054-ci33603002893` / `results/rolling/profiles-x86_64: 1 run(s)` | *(nothing)* | **12 ms** |

Both then passed "The windows are coherent" **on the very window they were about
to discard**. `results/rolling/core-aarch64` exists because a session committed
it 40 minutes later; `results/rolling/profiles-x86_64` was never committed by
anyone and is **absent from the tree**.

**3. The mechanism, isolated.** [`../../../experiments/80-rolling-window-commit-guard.sh`](../../../experiments/80-rolling-window-commit-guard.sh),
output committed:

```
case 1: a window that does not exist yet
  mutation landed: ?? results/rolling/profiles-x86_64/
  old guard  git diff --quiet        -> SKIP
  new guard  git status --porcelain  -> COMMIT
```

 `git diff` compares **tracked** paths. A window the fold step has just created
is untracked in every one of its files, so
`git diff --quiet -- results/rolling` reports "unchanged", the step exits 0
having printed nothing, and the folded window is discarded under a green tick.

 **It is the mirror image of the `git_dirty` defect fixed the same day** in
`crates/alloc-bench/src/envinfo.rs` (commit `a3eb76e`), where
`git status --porcelain` counted untracked files it should have ignored. Here
the untracked files **are** the change. Both directions of one confusion, hours
apart, and neither was found by reading the other.

 **The blast radius is exactly "a suite's first window", not "every window".**
Folding a *second* run into an existing window rewrites the tracked
`aggregate.md` and `aggregate.json`, so the old guard fires and `git add
results/rolling` then sweeps the untracked `runs/<id>/` in with it. Case 2 of the
probe is that case and both guards agree on it.  But no window can ever be
*created* by CI, so the weekly job cannot start a window for any suite it has
not already been hand-seeded for - which is every suite except `core`.

### Approach

One line in `.github/workflows/bench.yml`: guard on
`git status --porcelain -- results/rolling` being empty rather than on
`git diff --quiet`.

 **What it must not do:** drop the guard. A job that commits unconditionally
would pass case 1 and be worse than the bug - every dispatch that changed
nothing would push an empty-in-substance commit to `main`. Case 3 of the probe
exists for that direction and the replacement has to satisfy both.

 **A local probe cannot close this.** It establishes what the guard reads, and
nothing about whether the fixed job pushes - that is a property of the runner's
token, which `docs/AGENTS.md` §13 records as **refused 403 for tags and ref
deletes** while branch update works. Only a dispatch answers it.

### Prove

```sh
sh experiments/80-rolling-window-commit-guard.sh    # exit 0
```

and then a real dispatch of `bench.yml` whose `roll` job leaves a commit:

```sh
git log --oneline --grep='Rolling aggregate' origin/main   # non-empty
ls results/rolling/profiles-x86_64/                        # exists
```

Passing means the window `results/rolling/profiles-x86_64/` arrives on `main` in
a commit authored by `github-actions[bot]`, not by a session.

### Done, 2026-09-02

```
$ sh experiments/80-rolling-window-commit-guard.sh
case 1: a window that does not exist yet
  mutation landed: ?? results/rolling/profiles-x86_64/
  old guard  git diff --quiet        -> SKIP
  new guard  git status --porcelain  -> COMMIT
  wanted                             -> COMMIT
case 2: an existing window gains a run          -> both COMMIT
case 3: nothing changed                         -> both SKIP
                                                   # exit 0
```

 **And the real acceptance, from a dispatch rather than a probe.** `bench` run
[`33628116410`](https://github.com/Azathothas/alloc-bench/actions/runs/33628116410)
(`suite=profiles, arches=x86_64`, on the fixed head `7ba360c`), job
`100248377318`:

```
aggregate: added 20260902-120754-ci33628116410
aggregate: results/rolling/profiles-x86_64: 1 run(s), 1 CPU model(s), 0 rank change(s).
aggregate: results/rolling/profiles-x86_64 is coherent: 1 run(s).
[main 3226ee4] Rolling aggregate: fold in bench run 33628116410
 4 files changed, 1185 insertions(+)
 create mode 100644 results/rolling/profiles-x86_64/aggregate.json
 create mode 100644 results/rolling/profiles-x86_64/aggregate.md
 create mode 100644 results/rolling/profiles-x86_64/runs/20260902-120754-ci33628116410/rankings.json
 create mode 100644 results/rolling/profiles-x86_64/runs/20260902-120754-ci33628116410/run.json
To https://github.com/Azathothas/alloc-bench
   78df0fe..3226ee4  HEAD -> main
```

 **That is the first commit this job has ever made.** Before it,
`git log --all --grep='Rolling aggregate'` was empty across every dispatch since
the job was written.

 **What the fix did NOT do, and it is worth saying because it is the tempting
overreach.** The guard now sees untracked files; it does not commit when nothing
changed. Case 3 of the probe is that direction, and a guard that always
committed would have passed case 1 while pushing an empty-in-substance commit on
every dispatch.

 **One window it cannot recover.** `results/rolling/core-aarch64` was folded by
run [`33582107102`](https://github.com/Azathothas/alloc-bench/actions/runs/33582107102)
and thrown away; a session committed the same content by hand 40 minutes later,
so the tree is correct and the history says a person did what the job should
have. Nothing needs repairing - but a reader comparing `git log` against this
entry should know why.

---

## T-012: A published snapshot must carry its own conditions

**Source:** `docs/AGENTS.md` §12 item 11, and confirmed by inspection of every
committed snapshot on 2026-09-01.
**Category:** instrument
**Priority:** P2
**Effort:** S
**Status:** done

### Problem

A published dataset is kept so a later session can answer questions about it. One
already could not: `mechanisms` run A was committed with its `rankings.json` and
**without its `run.json`**, so its CPU is unrecorded, and whether runs A and B
were the same host - which decides whether a 20% disagreement is run-to-run
wander or a property of the machine - cannot be established from the tree.

 **A snapshot that keeps the numbers and drops the conditions cannot answer the
question it was kept for.** Nothing currently prevents the next one doing the
same.

### Premise

 **Measured, not read.**

```
$ ls results/published/2026-09-01-mechanisms-x86_64/run-a-11member-splice/
rankings.json
```

One file. The four sibling snapshots each carry `run.json`, `plan.json`,
`rankings.json`, `report.md` and `results/`. So the convention is followed by
hand four times out of five, which is exactly the failure rate a convention has
when nothing checks it.

### Approach

Seam: a new check in `scripts/check-snapshots.py`, wired into
`.github/workflows/ci.yml`'s `configuration` job beside the existing lock-file
and matrix assertions.

For every directory under `results/published/` that contains a `rankings.json`,
assert the presence of `run.json`, and that its `host`, `tool_versions`,
`corpus_seed` and `git_commit` are non-empty.

 **Run A cannot be repaired** - the conditions were never recorded and
fabricating them is forbidden. The honest close is: the checker exempts that one
directory **by name, with the reason inline**, so the exemption is visible rather
than a silent pass. A dash where the value is unknown.

 **What it must not do:** delete run A to make the check pass. Its numbers are
cited by `docs/AGENTS.md` §11.2 and are the evidence for a finding about method.

### Prove

```sh
python3 scripts/check-snapshots.py
```

Exit 0 today. Then plant the defect the check exists to catch and read the exit
code unpiped:

```sh
mkdir -p /tmp/snap/results/published/fake && echo '{"groups":[]}' > /tmp/snap/results/published/fake/rankings.json
python3 scripts/check-snapshots.py --root /tmp/snap; echo "exit=$?"
```

Exit **1**, naming `fake` and the missing `run.json`.  A check that has never
been seen to refuse is a check nobody knows works.

### Done, 2026-09-02

`scripts/check-snapshots.py`, wired into `scripts/gate.sh` and into
`.github/workflows/ci.yml`'s `configuration` job (which already checks out at
`fetch-depth: 0`, which this needs).

 **It found a second defect on its first run, and it is worse than the one the
entry was written for.**

```
$ python3 scripts/check-snapshots.py; echo "exit=$?"
check-snapshots: EXEMPT 2026-09-01-core-x86_64: git_commit 'unknown' -- …
check-snapshots: EXEMPT 2026-09-01-mechanisms-x86_64/run-a-11member-splice: no run.json -- …
check-snapshots: 2026-09-01-mechanisms-x86_64-run-c: run.json names commit e24709ba, which is
  not reachable from HEAD, and the snapshot documents no way to obtain it -- add a README
  naming the commit and the `git fetch` that recovers it
exit=1
```

 **`mechanisms` run C's own README and `docs/AGENTS.md` §11.2 both said it was
measured at `194ed63`. Its `run.json` says `e24709ba…`.** Measured, three ways:

| question | command | answer |
| --- | --- | --- |
| what does the snapshot record? | `jq -r .git_commit …/run-c/run.json` | `e24709ba1f9bba9a40de5d38e55b186df17d83e7` |
| can a clone resolve it? | `git cat-file -t e24709ba…` | rc **128**, *"could not get object info"* |
| was it at least run B's image? | `image_digest` over all 16 cells | `sha256:a0631865…`; run B's is `sha256:6989b3c4…` - **a different image** |

 **This is the vintage-line wound (`e24709b`, the squash-merged branch head)
found in a DATASET**, which `check-docs.py` can never see because it only reads
markdown. The object is still on the remote behind the PR's ref, so the honest
repair was a route rather than a guess:

```sh
git fetch origin 'refs/pull/1/head:refs/remotes/origin/pr-1-head'
git cat-file -t e24709ba1f9bba9a40de5d38e55b186df17d83e7   # commit
```

 **And `efc84ab` is not a substitute for it** - `git diff --stat e24709ba efc84ab`
is **64 files changed, 25164 insertions(+), 150 deletions(-)**, because the squash
carried this very snapshot, committed after the run. Fixed in the snapshot's
README, `docs/AGENTS.md` §11.2 and `docs/history/README.md`.

**Two exemptions, by name with the reason inline**, because the alternative is
inventing a CPU model: run A's splice (no `run.json` at all) and `core` run A
(`git_commit: "unknown"`).  An exemption that stops firing is itself a failure,
so the list cannot rot - proved by `an-exemption-that-did-not-fire-is-itself-a-failure`.

 **`alloc-bench run` now warns at the moment it cannot record the commit**, so
the next "unknown" is seen by the operator rather than a session later.

### Prove - run, with the output

```
$ python3 scripts/check-snapshots.py; echo "exit=$?"      # after the repair
check-snapshots: 6 snapshot(s), every one carries its conditions. 2 exemption(s), 0 skipped.
exit=0

$ python3 scripts/check-snapshots.py --selftest; echo "exit=$?"
  … 21 checks, all ok …
check-snapshots --selftest: 21 check(s), 0 failure(s).
exit=0

$ mkdir -p /tmp/snap/results/published/fake && echo '{"groups":[]}' > /tmp/snap/results/published/fake/rankings.json
$ python3 scripts/check-snapshots.py --root /tmp/snap; echo "exit=$?"
check-snapshots: SKIP the recovery check: '/tmp/snap' is not a git repository, …
check-snapshots: fake: carries rankings.json but no run.json, so its numbers have lost their
  conditions -- the machine, the toolchain and the tree that produced them are unrecorded
check-snapshots: 2026-09-01-core-x86_64: exempt for git_commit but the exemption did not fire. …
check-snapshots: 2026-09-01-mechanisms-x86_64/run-a-11member-splice: exempt for run.json but …
check-snapshots: 3 snapshot condition problem(s) across 1 snapshot(s).
exit=1
```

 **The entry's literal `--root /tmp/snap` command reports three problems, not
one**, and that is correct: the exemption list is keyed to *this* repository's
snapshots, so under a foreign root neither fires and the rot check says so. The
planted defect is refused either way.  **The stronger form is `--selftest`**,
which builds its fixtures inside a real throwaway git repository - the recovery
rule is answered by `git merge-base --is-ancestor`, and a rule that could not run
is not a rule that passed.

** The selftest was itself mutated three ways and refused each**, because a
selftest that cannot fail measures nothing:

| mutation | selftest |
| --- | --- |
| `is_placeholder` always returns `False` | **6 FAIL** - every empty/placeholder condition case |
| the recovery route needs `sha` **or** `git fetch`, not both | **2 FAIL** |
| the walk stops at the top level (nested snapshots invisible) | **3 FAIL**, including `finds-a-NESTED-snapshot` |

---

## T-011: Publish the build log with the failure it documents

**Source:** review of `docs/AGENTS.md` against the committed snapshots,
2026-09-01.
**Category:** instrument
**Priority:** P2
**Effort:** S
**Status:** done

### Problem

The project publishes build failures as results - that is its stated convention -
but publishes only a **60-line tail** of each failing build log, and no
`cells/` or `logs/` directory at all. Three consequences, all measured:

1. `docs/AGENTS.md` §11.2 told readers to *"read `cells/<cell>/build.log`, not
   `logs/<cell>.log`"*. **No published snapshot contains either directory**, so a
   cold session following that instruction finds nothing. (The pointer has since
   been corrected to name the `evidence/` files; the underlying gap is this
   entry.)
2. The `link-override` symbol list is verifiable only from the runs A/B extract
   `evidence/link-override-failure.txt`. Run C's own `evidence/link-override-mimalloc.txt`
   is an 80-line tail containing **no `multiple definition` line at all** - its
   visible errors are undefined references to `clock`, `fputs`, `getrusage`,
   `sleep`, `pthread_mutex_lock/unlock`, `__stack_chk_fail` and `__popcountdi2`.
   Whether run C reproduced the same nine-symbol collision is **not established
   by anything in the tree.**
3. The musl-object list in [`T-005`](mechanisms.md#t-005-make-libc-surgery-work-beyond-mimalloc)
   is what a tail happens to show, not a complete enumeration.

### Premise

 **Measured, not read.**

```
$ for d in results/published/*/; do printf '%s cells=%s logs=%s\n' "$d" \
    "$([ -d "$d/cells" ] && echo yes || echo NO)" "$([ -d "$d/logs" ] && echo yes || echo NO)"; done
results/published/2026-09-01-core-x86_64-ci-runner/   cells=NO logs=NO
results/published/2026-09-01-core-x86_64-run-b/       cells=NO logs=NO
results/published/2026-09-01-core-x86_64/             cells=NO logs=NO
results/published/2026-09-01-mechanisms-x86_64-run-c/ cells=NO logs=NO
results/published/2026-09-01-mechanisms-x86_64/       cells=NO logs=NO
$ grep -c 'multiple definition' results/published/2026-09-01-mechanisms-x86_64-run-c/evidence/link-override-mimalloc.txt
0
```

 **The tails were a deliberate size trade-off, not an oversight**, and the trade
is defensible - a full dataset is tens of megabytes. What is not defensible is a
tail chosen by `tail -n` rather than by relevance, which is how a
`multiple definition` block gets cut while `__stack_chk_fail` noise survives.

### Approach

Seam: the snapshot procedure, and a new helper `scripts/report/extract-evidence.py`.

For every `build_failed` cell, extract the **diagnostic lines** rather than a
positional tail: every line matching `multiple definition|undefined reference|
UNSUPPORTED|error:`, de-duplicated, with a count of how many were elided and the
full log's byte length recorded beside it.

 **Give it an `--expect` flag**, per `docs/methodology/experiments.md`: a
committed extract that no longer contains the failure it was kept for is a
regression the check should catch, not something a reader discovers.

 **What it must not do:** commit whole build logs for every cell. The point is
that the extract is chosen by what the failure *is*, not by where it sits in the
file.

### Decision

 **Whether run C's `link-override` failure is re-measured is part of this
entry.** The nine-symbol claim currently rests on runs A/B alone. Either re-run
that one cell and extract properly, or state in `docs/AGENTS.md` that the list is
from A/B and unconfirmed for C. **Recommendation: re-run the cell** - it is one
`docker run`, and the alternative leaves a caveat in the handoff forever.

### Prove

```sh
python3 scripts/report/extract-evidence.py --run results/local/<id> --out /tmp/ev
grep -c 'multiple definition' /tmp/ev/link-override-mimalloc.txt
```

Non-zero count for a `link-override` cell that failed that way, and exit 0. Then
the guard mutation:

```sh
python3 scripts/report/extract-evidence.py --check results/published/2026-09-01-mechanisms-x86_64/evidence \
  --expect 'multiple definition'; echo "exit=$?"
```

Exit 0 on the A/B extract, and exit **1** when pointed at an extract that has
lost the pattern.

### Done, 2026-09-02 - both halves, including the re-run

`scripts/report/extract-evidence.py`, wired into `scripts/gate.sh` and
`.github/workflows/ci.yml`. The entry's Decision was *"Recommendation: re-run the
cell"*; it was re-run.

####  The re-run settles it: the nine are the same nine

`results/published/2026-09-02-mechanisms-x86_64-run-d/` - 4 cells, 3 `ok`,
1 `build_failed`, **0 validator errors**, host `Intel(R) Xeon(R) Processor @
2.80GHz`, commit `08ac3e5`.

```
$ wc -c results/local/20260902-013141/cells/alpine-x86_64-mimalloc-link-override-static-pie-distro/build.log
68719
$ grep -c 'multiple definition' …/build.log
9
```

`__libc_free`, `__libc_malloc`, `__libc_realloc`, `aligned_alloc`, `calloc`,
`free`, `posix_memalign`, `realloc`, `strdup` - exactly runs A/B's nine.

 **So run C reproduced the collision; run C's extract lost it, mechanically.**
Measured on run D's log, which is the same failure:

| what you keep of the 414-line, 68 719-byte log | `multiple definition` | `undefined reference` |
| --- | --- | --- |
| all of it | **9** | 210 |
| `tail -n 80` - run C's method | **0** | 47 |
| `extract-evidence.py --budget 40` | **9**, ranked first | 25 distinct of 47 |

 **A positional tail of this file keeps none of the finding and 47 lines of
`__stack_chk_fail` noise.** That is not a fact about run C. `docs/AGENTS.md`
§5.1 and §11.2's caveat are retired and replaced with this.

#### What the extractor does

Diagnostic lines by class - `multiple definition`, `undefined reference`,
`undefined symbol`, `UNSUPPORTED`, `error:`, `cannot find`, `collect2/ld` -
de-duplicated on a normalised form that collapses **link-map offsets**
(`bitmap.c:(.text+0x175)` and `(.text+0x1d4)` are one finding, not two; without
this the de-duplication does nothing at all on real `ld` output), each class
guaranteed a floor of three lines, and a header recording the full log's byte
count, how many lines matched, how many were elided, and per class what did not
fit.

 **The per-class floor was added because the first version was wrong**: at
`--budget 40` on the real log it published 31 `undefined reference` lines and
dropped **all three** `error:` lines - a class the reader needs, lost to a class
they already had.

### Prove - run, with the output

```
$ python3 scripts/report/extract-evidence.py --check \
    results/published/2026-09-01-mechanisms-x86_64/evidence --expect 'multiple definition'
extract-evidence: 'multiple definition' present in link-override-failure.txt
extract-evidence: 3 extract(s), every expectation met.
exit=0

$ python3 scripts/report/extract-evidence.py --check \
    results/published/2026-09-01-mechanisms-x86_64-run-c/evidence --expect 'multiple definition'
extract-evidence: no extract under …-run-c/evidence contains 'multiple definition' -- the
  evidence has lost the failure it was kept for
exit=1

$ python3 scripts/report/extract-evidence.py --selftest
  … 18 checks, all ok …
exit=0
```

 **Run C's own extract is left as it is, and still fails `--check`.** It is the
evidence of the defect; repairing it would need run C's log, which was never
kept.  That is why the gate's `--expect` points at the A/B extract and run D's,
which do carry the finding.

** The extractor was mutated four ways and the selftest refused each**:

| mutation | selftest |
| --- | --- |
| classes ordered noise-first (a tail by another name) | **2 FAIL** |
| de-duplication removed | **1 FAIL**, 111 near-duplicate lines |
| `--check` counts no problem when the pattern is absent | **2 FAIL** |
| the header drops the elision count | **1 FAIL** |

 **One of this entry's own checks was found weak by that exercise.**
`collision-outranks-the-noise` was written as `body.index(...)` and passed under
the reordering mutation, because the `# classes:` accounting header names both
classes above everything. It now tests the payload. **A check satisfied by its
own header measures nothing**, and only a mutation showed it.

---

## T-010: Write `experiments/40-` and `60-`

**Source:** `experiments/README.md`, which names both as planned.
**Category:** instrument
**Priority:** P3
**Effort:** S
**Status:** done

### Problem

`experiments/README.md` reserves `40-allocator-build-matrix.sh` and
`60-static-pie-aslr.sh` and describes what each would answer. Neither is written.
The numbering is reserved so a later citation stays meaningful, so the cost of
leaving them is small - but each would turn a property currently established only
as a side effect of a full run into a standalone assertion.

### Premise

 **Measured, not read.** `ls experiments/` shows `10-`, `20-`, `30-`, `50-`
and their committed output under `out/`; `40-` and `60-` are absent, and nothing
in the repository cites a result from either.

 **Both are genuinely redundant today**, which is why they are P3 and not
higher: a normal `alloc-bench run` already produces the build matrix, and
`alloc-runner aslr-probe --expect randomised` already asserts ASLR per cell in
every published run.

### Approach

Each follows the contract in `experiments/README.md`: a header stating the
**question** rather than the action, every input pinned, conditions printed on
the way out, exit 0/1/2 with 2 never a pass, and paths resolved from the script's
own location.

- `40-allocator-build-matrix.sh` - for each allocator × mode × PIC, run the
  recipe and record built / unsupported-with-reason / failed.  Its value is
  being runnable **without a container orchestration run**, so a recipe
  regression is caught in minutes.
- `60-static-pie-aslr.sh` - build one binary per profile and assert the ELF type
  and the observed load-address behaviour agree with what
  `docs/static-linking.md` claims for that profile.  Its value is asserting the
  *table in the document*, which nothing currently does.

 **Neither reuses a number.** `40-` and `60-` are the reserved ids; if either
is later replaced, the replacement takes the next free number and the old script
stays.

### Prove

```sh
sh experiments/40-allocator-build-matrix.sh; echo "exit=$?"
sh experiments/60-static-pie-aslr.sh;        echo "exit=$?"
```

Each writes `experiments/out/<name>.txt` with a conditions block at the top, and
exits 0, 1 or 2 - never anything else. Both output files committed, per
`experiments/README.md`: the evidence is the point.

### Done, 2026-09-02

Both written, both run, both outputs committed under `experiments/out/`.

```
$ sh experiments/40-allocator-build-matrix.sh; echo "exit=$?"
built 10, unsupported-with-reason 4, failed 0          exit=0
$ sh experiments/60-static-pie-aslr.sh;        echo "exit=$?"
all five profiles agree with the document              exit=0
```

####  `60-` is not the redundant one the entry expected

The entry called both "genuinely redundant today". That was right about `40-`
and **wrong about `60-`**, and the difference is what it asserts: `60-` parses
the profile table **out of `docs/static-linking.md`** and checks the document
against a measurement.  Nothing else in this repository checks a document
against anything. It fails in both directions - a wrong document with a right
build fails too.

Proved by mutation, not by passing: three edits to the document's table, each
caught, each with the right message.

| planted in the document | what `60-` said |
| --- | --- |
| `static` claims **yes** to ASLR | ` ASLR: document says yes`, exit 1 |
| `static-pie` claims `ET_EXEC` | ` link kind: document says static`, exit 1 |
| `dynamic` claims no `PT_INTERP` | ` link kind: document says static-pie`, exit 1 |

 The subject is a 6-line Rust program, not ripgrep - the question is about the
link, and this makes the whole sweep 15 seconds.

#### `40-` - fast, and redundant as predicted

Ten allocator × mode combinations built, four refused **with reasons**, none
failed, in about **four minutes** against roughly an hour for a full run.

 **It found nothing wrong**, so the value is the runtime and the isolation,
exactly as the entry predicted. What it *did* catch was a planted defect: a
recipe made to exit 0 without producing `lib/liballocbench.a` was reported
` NO ARCHIVE`, exit 1.  That case matters because the contract in
`docs/allocator-integration.md` is the **path**, not the exit code, and a
silent empty success would be blamed on the link that failed downstream of it.

 **The first run failed for a defect in the script itself** - the per-recipe
log is redirected by the *host* shell before the container starts, and
`$TMP/out` was only created inside the container, so all 14 cells reported
`rc=2`.  It reported a failure rather than passing silently, which is the
behaviour wanted; the fix is one `mkdir` and a comment saying why.

 A mutation test that "passed" on the first attempt was **my test being
broken**, not the script working: `mimalloc/build.sh` has no `set -` line to
insert after, and the mutation script printed `mutated` unconditionally. The
second attempt asserts the mutation landed before running anything.

---

## T-015: every human-facing number must say which direction is good

**Source:** raised by the operator on 2026-09-03, from outside the backlog -
which had **no open entries at all** at the time.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

 **Nothing this project publishes says whether a number is a win.** A reader
meets `1.138×` in a ranking table, or a bar in a chart, and has to *infer* the
direction. That inference is not always available and it is not always the same
one:

| where | what it said before |
| --- | --- |
| the ranking table in every `report.md` | **nothing** |
| the relative-time chart | `lower is faster`, in the subtitle |
| the relative-RSS chart | `lower is less memory`, in the subtitle |
| the **binary-size chart** |  **nothing at all** |
| `results/rolling/*/aggregate.md` | only `rank`'s "fastest = 1" |
| the `combine.py` job summary | nothing |
| the report's **ASLR** table | nothing -  **and here HIGHER is better** |
| the report's **preload residency** table | nothing -  **and its two columns want OPPOSITE directions** |

 **The last two are why this is P1 rather than cosmetic.** `1 of 6 distinct
load addresses` is the worst possible result in the ASLR table and reads like a
good ratio. `0 of 4` in the residency control column is the *passing* value. A
reader carrying a "lower is better" habit from the tables above gets both
backwards.

 **And the charts had a second, sharper defect**: they had no axis. No ticks,
no scale, no legend for three bar colours, and no indication anywhere of a
cell's own spread - so a 4.8% lead sitting inside a 6.4% MAD was drawn exactly
like a real one, which is the claim `docs/AGENTS.md` §9 forbids in prose.

### Premise

 **Measured, not read**: regenerating a real report from
`results/published/2026-09-02-preload-x86_64/` and reading it. The `debian`
group's snmalloc row is `1.082×` against a `10.5%` MAD - a tie by §9's rule,
which the *verdict line* correctly refused to call and which the *table* and the
*chart* both presented as an ordinary slower row.

### Approach

One rule, one implementation, used by both the picture and the prose:

- `svg::Better` is a two-valued enum with no `Unknown`, and `Chart` carries it
  as a required field. Every chart draws it as a labelled pill.
- `svg::direction_note` gives the same words to a Markdown table, so the two
  cannot drift.
- `svg::rel_phrase` turns `0.648` into `35.2% faster`, and `report::rel_cell`
  and `combine.py::rel_cell` both use that same rule so the report and the CI
  job summary say the same thing about the same number.
-  A row whose distance from the control is inside its own MAD prints
  ` ≈ control` rather than a percentage, is drawn in a distinct tie colour, and
  its chart label says ` inside its own noise`.
- Charts gain ticks, a gridded axis, a labelled control line, a colour legend
  and **MAD whiskers**.

### Prove

```sh
cargo build --release -p alloc-bench
cp -r results/published/2026-09-02-preload-x86_64 /tmp/rpt
./target/release/alloc-bench report --run /tmp/rpt
grep -c '↓' /tmp/rpt/report.md            # the direction is stated per column
grep 'inside its own noise' /tmp/rpt/*.svg
python3 scripts/report/combine.py results/published/2026-09-02-preload-x86_64
python3 scripts/report/aggregate.py --selftest
```

### Done, 2026-09-03

Regenerated from the real dataset:

```
| # | allocator | mechanism | time (s) ↓ | vs control ↓ | MAD ↓ | peak RSS (MiB) ↓ | vs control ↓ | … |
| 1 | snmalloc | `preload` | 0.039 | 0.648× (35.2% faster) | 4.1% | 7.738 | 1.528× (52.8% more) | … |
| 4 | system *(control)* | `baseline` | 0.060 | 1.000× *(control)* | 6.4% | 5.064 | 1.000× *(control)* | … |
```

and in the `debian` group, where §9's rule bites:

```
| 2 | snmalloc | `preload` | 0.045 | 1.082×  ≈ control | 10.5% | … |
```

 **The chart caught a defect the code review would not have.** The first
version drew that row in the tie colour and labelled it `8.2% slower` - the
picture and its own caption disagreeing, with the reader invited to believe the
more specific one. Found by regenerating a report and *looking at it*, which is
this session's rule that a comment describing what code should do is not
evidence that it does, arriving through a third door.

 **A styling choice worth recording rather than re-litigating.** Memory ratios
above 2× read awkwardly as percentages - mimalloc's is `3.289× (228.9% more)`.
Rejected: switching to "3.3× the control" above some threshold, which is
redundant with the ratio already printed, and inventing a second phrasing rule
for one column. The percentage is exact, and it is the same rule in every
column, which is worth more than the smoothness.

 **What this does NOT do.** It does not change a single number, a ranking, a
verdict or the composite. `rank.rs` is untouched; `tie_with_control` is a
presentation predicate applied per row, and the run-level verdict logic that
already existed is unchanged.  Nor does it help a reader who does not open the
report at all: `docs/AGENTS.md` §11's tables are hand-written prose and carry
their direction in words.

---

## T-020: `gate.sh --strict` could not see a skip one level down

**Source:** found 2026-09-03 by this session's own opening baseline run - the
gate printed `18 passed, 0 failed, 0 skipped` and exited 0 under `--strict`
while two of its checkers had each skipped a check.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

[`RULES.md`](RULES.md) §4 says `sh scripts/gate.sh --strict` is what a push must
pass, on the stated grounds that *"`--strict` turns a skip into a failure, which
is what CI passes and what a push should have to pass"*.

 **It was not what CI passes, and its `--strict` had nothing to refuse.**
`scripts/gate.sh` counted only the skips **it** decided - a missing `shellcheck`,
an unbuilt binary, no `python3`. A checker that ran, skipped one of its **own**
checks and exited 0 was recorded as `pass`, contributed nothing to `$SKIP`, and
`--strict` - whose entire job is to refuse a skip - passed over it.

### Premise

 **Measured on this session's own opening gate**, before anything was changed.
The container starts with a **depth-1 clone**, and two checks need real history:

```
$ sh scripts/gate.sh --strict
  check-docs.py  (references resolve)            pass
  check-snapshots.py  (conditions kept)          pass
gate: 18 passed, 0 failed, 0 skipped.
$ echo $?
0
```

and the same two checkers, run directly against the same tree:

```
check-docs: SKIP the vintage check: this is a shallow clone, so no commit can be
            shown reachable from HEAD (fetch-depth: 0, or `git fetch --unshallow`)
check-snapshots: SKIP the recovery check: this is a shallow clone, so a commit
            absent from it cannot be told apart from one on a dead branch
```

 **The vintage check is the one `docs/AGENTS.md` exists to be held to.** Its
own header says `scripts/check-docs.py` "now asserts that the commit named here
resolves", after that line once named `e24709b` - the head of a squash-merged
branch - and left a reader unable to establish which tree the document described.
That check retired itself, silently, on the gate this session ran first.

 **And the gate was strictly weaker than CI over the same tree.**
`.github/workflows/ci.yml` runs `check-docs.py --strict` and
`check-snapshots.py --strict`; `gate.sh` ran both **without the flag, in either
mode**. The command a session runs before pushing was a weaker check than the
one that judges the push - which is the opposite of the arrangement §4 argues
for.

 **It is not confined to those two.** `alloc-runner selftest` also collects
skips, prints `  SKIP  <name>` and exits 0 (`crates/alloc-runner/src/main.rs`).
It has nothing to skip today. The gate would not have seen it if it had.

### Approach

Two guards, deliberately independent, because they cover different holes.

1. **`--strict` is passed down** to every checker that has one, so the gate runs
   CI's own invocation. The checker is authoritative: it knows *why* it could
   not look and says so in the failure.
2. **A passing check's output is scanned for a skip marker**, counted into
   `$SKIP` and printed. This is what covers a checker with **no** such flag.
   Three tools emit one and all three agree on the token - `check-docs: SKIP …`,
   `check-snapshots: SKIP …`, and `alloc-runner`'s `  SKIP  …`.

 **`EXEMPT` is deliberately not matched.** `check-snapshots.py` prints three
exemptions on every run; an exemption is a named, argued decision recorded in
the checker, not a check that could not run. Conflating the two would make the
gate unpassable and teach the next session to weaken it.

 **Rejected: always running the checkers with `--strict`.** The plain gate is
*allowed* to skip - that is its documented difference from `--strict` - and a
developer on a shallow clone genuinely cannot answer the vintage question. That
change would have made the plain gate fail for a reason the developer cannot fix
locally, which is how a gate gets routed around.

 **Rejected: giving the checkers a third exit code for "passed with skips".**
`docs/AGENTS.md` §7 fixes 0/1/2 project-wide and 2 means "could not run at all",
which is not true of a checker that ran 98 of its 99 checks.

### Prove

```sh
sh experiments/140-gate-sees-a-skip-below.sh   # exit 0
sh scripts/gate.sh --strict                    # exit 0 on a full clone
```

### Done, 2026-09-03

[`../../../experiments/140-gate-sees-a-skip-below.sh`](../../../experiments/140-gate-sees-a-skip-below.sh),
output committed, **exit 0**. It runs the real `scripts/gate.sh`, not a
reimplementation of it - a probe that re-implements its subject is the defect
[`T-019`](mechanisms.md) was filed for, one level up.

**B - each checker, plain and `--strict`, in a shallow clone and a full one:**

```
  checker                clone    plain          --strict
  check-docs.py          shallow  rc=0 n=1        rc=1
  check-docs.py          full     rc=0 n=0        rc=0
  check-snapshots.py     shallow  rc=0 n=1        rc=1
  check-snapshots.py     full     rc=0 n=0        rc=0
```

 **The full-clone row is the negative control**, and it is the half that makes
the shallow row mean anything: `--strict` is harmless where nothing skipped, so
the refusal is caused by the missing history and not by the flag.

**A - the production script, unmodified, in the shallow clone:**

```
  check-docs.py  (references resolve)            FAIL
      | check-docs: SKIP the vintage check: this is a shallow clone…
      | check-docs: --strict, and 1 check(s) could not run
  check-snapshots.py  (conditions kept)          FAIL
      | check-snapshots: SKIP the recovery check: this is a shallow clone…
gate: 16 passed, 2 failed, 0 skipped.
gate: failed: check-docs.py  (references resolve) check-snapshots.py  (conditions kept)
  gate exit code: 1
```

 **Exit 1 alone would prove nothing** - an unbuilt binary or a missing tool
produces it too - so the probe asserts the refusal **names both checkers**.

**And the second guard, which the first hides:** with `--strict` the checkers
fail, so the marker scan never fires. Run plainly in the same shallow clone:

```
  check-docs.py  (references resolve)            pass, 1 SKIPPED INSIDE
      | check-docs: SKIP the vintage check: …
  check-snapshots.py  (conditions kept)          pass, 1 SKIPPED INSIDE
      | check-snapshots: SKIP the recovery check: …
gate: 18 passed, 0 failed, 2 skipped.
```

 `0 skipped` → `2 skipped` **on the same tree, from the same command**, and the
three `EXEMPT` lines in the same output were correctly not counted.

 **What this does not do.** It does not audit every checker for internal skips;
it makes one appear in the summary if it happens. And it changes nothing about
CI, which was already passing `--strict` - the defect was the gate drifting
below it, in the direction nobody looks.

---

## T-021: a published dataset that reaches no rolling window

**Source:** work order item 5, carried by [`PROGRESS.md`](PROGRESS.md) from
2026-09-03 - *"a check nobody has written: does every published snapshot reach a
rolling window?"* - raised after the 2026-09-02 `distros` dataset was published,
never folded, and had to be folded by hand before two machines could be compared.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

[`results/rolling/`](../../../results/rolling/) is the only thing in this repository
that **refuses an ordering**. It is where "what held across machines" is decided.

 **A published dataset that never reaches a window takes no part in that
judgement, and nothing said so.** From the tree it is indistinguishable from one
that does: same directory shape, same `rankings.json`, same `run.json`, sitting
under `results/published/` looking like evidence in use.

### Premise

 **Measured before anything was written**, by asking each published snapshot's
`run_id` whether any window held it:

```
9 of 18 published snapshots reach no rolling window:
    2026-09-01-mechanisms-x86_64            mechanisms
    2026-09-01-mechanisms-x86_64-run-c      mechanisms
    2026-09-02-mechanisms-x86_64-run-d      mechanisms
    2026-09-02-mechanisms-x86_64-run-e      mechanisms
    2026-09-02-hardening-variants-x86_64    hardening-variants
    2026-09-02-hardening-variants-x86_64-run-b  hardening-variants
    2026-09-02-preload-x86_64               preload
    2026-09-02-preload-x86_64-ci-runner     preload
    2026-09-02-toolchain-control-x86_64     toolchain-control
```

 **Half of it.** Three suites - `mechanisms`, `hardening-variants`,
`toolchain-control` - had **no window at all**, `mechanisms` being the suite
behind `docs/AGENTS.md` §5.1 *and* §11.2.

 It is the same shape as [`T-014`](#t-014-benchymls-rolling-window-commit-has-never-once-run):
the path that publishes evidence, failing quietly. There the `roll` job built a
window and threw it away under a green tick; here a dataset never reaches the
job at all, because it was measured locally rather than by `bench.yml`.

### Approach

Rule 5 in `scripts/check-snapshots.py`, which already sweeps every directory
carrying a `rankings.json` and already has the exemption machinery.

 **"Absent" is not automatically wrong, and both legitimate reasons are
DERIVED rather than assumed:**

- **Evicted.** A window keeps `N` runs. `keep` is read from the window's **own
  `aggregate.json`**, never typed in the checker - a second copy of that number
  would be the standing-list defect [`T-019`](mechanisms.md) one level up. A
  window holding fewer than `keep` cannot have evicted anything, so absence
  there is certainly *never folded*.
- **Ruled out.** A run whose **candidate set** differs from the window's belongs
  out of it: `rank` means something different in a field of four than in a field
  of seven, and moved ranks are what the window uses to refuse an ordering. That
  is argued in the window's README, naming the run id.

 **The second route is not new policy - it is the ruling
[`results/rolling/preload-x86_64/README.md`](../../../results/rolling/preload-x86_64/README.md)
already made on 2026-09-03**, promoted from a one-off to a rule. This entry
found it by trying the other thing first.

 **Rejected: folding all nine.** Tried, and the aggregator refused it -
correctly. Two of the `preload` snapshots are the **pre-widening** 4-candidate
suite against a window holding the 7-candidate one, which is the exact case that
README removed them for. Folding them back would have overturned an argued
decision in order to satisfy a check written an hour earlier.

 **Rejected: teaching `--check` to accept a missing candidate**, for the reason
that README already gives and which has not changed: the window stores
`rankings.json` and `run.json`, and neither says whether a candidate is absent
because the suite did not include it or because its **cell failed and was
dropped** - which is the case the check exists to catch.

 **The README route matches on the RUN ID, never the directory name**, because
`2026-09-02-preload-x86_64` is a prefix of `2026-09-02-preload-x86_64-ci-runner`
and a README naming only the second would silently account for the first.  And
because prose is matched by substring either way, an id that is a **prefix of
another run's** loses the route entirely and is refused with that reason -
rather than the check quietly depending on ids being fixed-width
`YYYYMMDD-HHMMSS`, which is true today and written down nowhere.

### Prove

```sh
python3 scripts/check-snapshots.py --selftest
python3 scripts/check-snapshots.py --strict
```

### Done, 2026-09-03

**41<!--n:snapshots-selftest--> planted defects, 0 failures** (28 → 37). The six new cases cover: an
unfolded snapshot refused; an exemption letting one through; a window README
that does *not* name the run still refused; one that does, accepted; a
prefix-ambiguous run id refused; a not-full window unable to excuse an absence;
a full window excusing an *older* one but **not** a newer one.

 **It also found a defect in the selftest itself.** The
`refuses-a-run.json-that-does-not-parse` case wrote `{not json` into the `good`
fixture and never restored it, so **every case after it saw a tree that already
failed** - a planted defect that did nothing would still have read as "refused".
The fixture is restored, and a new case asserts the tree is clean again before
the next one runs.

**What changed in the tree**, after the classification above:

| suite | window | why |
| --- | --- | --- |
| `hardening-variants` | **new**, 2 runs | both comparable; folded |
| `toolchain-control` | **new**, 1 run | folded |
| `mechanisms` | **new**, 1 run | run E only - the other three have candidate sets of 3, 7 and 3 against its 10. [`README.md`](../../../results/rolling/mechanisms-x86_64/README.md) argues it and names all three run ids |
| `preload` | unchanged, 1 run | the two others are pre-widening and its README already ruled them out; **the check now reads that README instead of demanding the fold** |

```
check-snapshots: 33 snapshot(s), every one carries its conditions.
                 3 exemption(s), 5 accounted for elsewhere, 0 skipped.
```

 **And folding those datasets immediately found a P1 defect in the aggregator**
- two variants of one allocator collapsing into one row -
[`T-022`](#t-022-the-aggregator-merged-two-allocators-into-one-row). That is the
entry's real return: the check forced evidence through a tool that had never
seen it.

 **What this does not do.** It does not make a window *good*: `mechanisms`,
`toolchain-control` and `preload` each hold one run and establish nothing about
transfer, which their own " One run" banners say. What it makes impossible is a
dataset sitting beside them that nobody folded and nobody decided not to.

---

## T-022: the aggregator merged two allocators into one row

**Source:** found 2026-09-03 by [`T-021`](#t-021-a-published-dataset-that-reaches-no-rolling-window)
forcing the `hardening-variants` datasets into a window for the first time.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

`scripts/report/aggregate.py` keyed a candidate on
`(allocator, integration)`.  **The `hardening-variants` suite measures
hardened_malloc's `default` **and** `light` configurations in the same group**,
so the two collapsed into one row - and the aggregate then published, over
**two runs**, a table that is complete, plausible and wrong in five ways:

| what it printed | what is true |
| --- | --- |
| `rank 1/3/1/3` | four positions over two runs |
| `between-run spread` **48.5%** | the gap between the two **variants**; the runs reproduced to three decimals |
| *"1 allocator(s) changed rank between runs: hardened_malloc"* | nothing changed between runs |
| *"changed which side of the control they sit on: hardened_malloc"* | neither variant crossed |
| *"no allocator beat the control in every run"* | `light` beat it in both |

 `rankings.json` has carried `variant` since the field existed. Nothing in the
aggregator read it.

### Premise

 **The aggregator's own coherence check was shouting it and the message did not
fit the fact:**

```
aggregate: hardened_malloc appears in 2 of 1 runs
aggregate: hardened_malloc appears in 4 of 2 runs
```

 **A count larger than the number of runs is not the coverage problem that
message describes.** It is one run contributing two rows to one candidate.

 **This project had already ruled on the distinction** - *"a cell id gains a
variant segment only when the variant is not the default"*, `PROGRESS.md`,
2026-09-02 - so cell ids carry it and the aggregator did not.

### Approach

- The candidate key becomes `(allocator, integration, variant or "default")`.
- Each row gains `variant` and a `label`, and **`label` is what every
  human-facing sentence uses** - the table, the rank-mover list, the
  control-crosser list, the "beat the control every run" list, the RSS-mover
  list and the widest-spread sentence. `allocator` alone names two different
  things in a variant-carrying suite.
- `label` follows the cell-id rule exactly: bare name for `default`,
  `name (variant)` otherwise - so **every existing window is unchanged**.

### Prove

```sh
python3 scripts/report/aggregate.py --selftest
for w in results/rolling/*/; do python3 scripts/report/aggregate.py --window "$w" --check; done
git diff --stat -- 'results/rolling/*/aggregate.md'
```

### Done, 2026-09-03

**31<!--n:aggregate-selftest--> planted defects, 0 failures** (23 → 31). Eight new cases over two
**identical** runs, so every disagreement the old key produced is manufactured
by the key itself.

 **Mutation-tested.** With the variant dropped back out of the key, **seven of
the eight fail**, reproducing the real symptom exactly:

```
FAIL  two-variants-of-one-allocator-are-two-rows rows=['h', 'system']
FAIL  each-variant-has-one-position-per-run positions=[[1, 3, 1, 3], [2, 2]]
FAIL  identical-runs-produce-no-rank-mover movers=['h']
```

The corrected window, and  **it independently reproduces the figures
`docs/AGENTS.md` §13 computed by hand from those two runs**:

```
| hardened_malloc (light) | rust-global | 0.697 | 0.664 | 0.729 | 9.3% | 1/1 | 1.178 |
| system *(control)*      | baseline    | 1.000 | 1.000 | 1.000 | 0.0% | 2/2 | 1.000 |
| hardened_malloc         | rust-global | 1.043 | 1.003 | 1.084 | 7.8% | 3/3 | 2.875 |
```

 Every allocator held its rank; `hardened_malloc (light)` beat the control in
both runs by more than that run's own MAD.

 **No existing published claim moves.** `git diff` over every
`results/rolling/*/aggregate.md` is **empty** - only `aggregate.json` gains the
two new fields - because every other window's allocators run the default
variant and their labels are their names.

 **AND THE DOOR SWEEP FOUND TWO MORE PLACES, one of them in `rank.rs` after
all.** The first version of this entry said the defect was "in the cross-run
aggregate alone".  That was written from memory rather than from a grep, and it
was wrong in both directions:

| where | what it did | why it matters |
| --- | --- | --- |
| `scripts/report/combine.py:135` | keyed `per_arch_rows` on `(allocator, integration)` | the merge would be **across architectures**, so one arch's `light` would share a row with another's `default` and be compared with it |
| `crates/alloc-bench/src/rank.rs` - the verdict | printed `first.allocator` | produced *"**hardened_malloc** is 37.2% faster than the next row"* where the next row **is** hardened_malloc |
| `crates/alloc-bench/src/rank.rs` - the per-libc roll-up | keyed on `(allocator, integration)` |  this is the code the README's *"jemalloc on musl, nothing on glibc"* headline is computed from; two variants would share one row and their wins, losses and ties would be counted together |

 **`Row` has carried `variant` since `hardening-variants` existed, and its own
doc comment says "without this the table cannot be read".** The *table* used it.
The verdict and the roll-up did not. A partial fix that reads as a complete one
is the shape this project keeps finding.

Regenerated over the real dataset:

```
> **Fastest: hardened_malloc (light) (rust-global).** hardened_malloc (light) is
  37.2% faster than the next row, which is outside the run's spread of 4.8%
```

 The doubled parentheses in `hardened_malloc (light) (rust-global)` are ugly
and deliberate: the second pair is the mechanism, which every verdict line
carries, and inventing a second phrasing rule for one column is the trade
[`T-015`](#t-015-every-human-facing-number-must-say-which-direction-is-good)
already refused.

 **Regression check**: `alloc-bench report` re-run over
`2026-09-03-libc-contrast-x86_64` (no non-default variants) reproduces its
committed `report.md`, and `combine.py` over `2026-09-01-core-x86_64` is
unchanged.

 **What this does not do.** It does not change any ranking. `label()` is a
presentation and keying rule; every ratio, MAD and position is untouched, and
`rel_time` still decides order.

---

## T-023: nothing checks a count written in prose

**Source:** work order item 6, carried by [`PROGRESS.md`](PROGRESS.md) from
2026-09-03 - *"`check-todo.py` verifies the entry tables and cannot see '6
examples, 65 checks' in a sentence"* - raised by a review pass that found three
counts stale within an hour of being written.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

`scripts/check-todo.py` derives the counts in `INDEX.md`'s tables and
`PROGRESS.md`'s status line, and refuses a disagreement.  **That is the only
place in this repository where a count could not go stale.** Every other number
- `PROGRESS.md`'s baseline table, `docs/AGENTS.md` §13's status board,
`examples/README.md` - was typed by a session and never read again.

### Premise

 **Six went stale in two days, and both times it was the session that had just
written the rule against it.**

| when | what went stale |
| --- | --- |
| 2026-09-02 | "67 checks" (65), example 60 at "13 passed" (11), "16 planted cases" (19) |
| 2026-09-03 | `check-snapshots.py --selftest` 28 → **37** and `aggregate.py --selftest` 23 → **31**, each written in two documents |

 The 2026-09-03 three were made stale by the session writing **this entry**,
in the same hour, by closing [`T-021`](#t-021-a-published-dataset-that-reaches-no-rolling-window)
and [`T-022`](#t-022-the-aggregator-merged-two-allocators-into-one-row).

### Approach

`scripts/check-counts.py`. A claim carries a marker naming its source; the
number before the marker is compared with what the source **actually reports**;
`--write` rewrites it. It is `check-todo.py --write` generalised past the entry
tables, and the rule it enforces is the one already written down:  **never
retype a count.**

```markdown
| `alloc-runner selftest` | **28**<!--n:runner-selftest--> checks |
```

 **A source nothing claims is a failure**, the same rule the snapshot
exemptions follow - a source that stops being cited is either a claim somebody
deleted or a check that guards nothing.  And a marker naming an unknown source
is a failure, so a renamed source cannot leave a claim silently unchecked.

 **Two kinds of source, and the difference is cost.** Most are commands
`scripts/gate.sh` already runs, executed here and read from their own summary
lines. The rest - `sh examples/run.sh` builds six container images - are read
from that command's **committed transcript**, which is the evidence anyway and
which `examples/run.sh` re-validates.

 **Rejected: scanning for a count near a mention of a command**, with no
marker. It reads more naturally and it is guesswork: a line mentioning
`check-snapshots.py` and containing "found two real defects on its first run"
would need a vocabulary of nouns to know which number is the claim, and an
unrecognised noun would be an **invisible skip** - the failure
[`T-020`](#t-020-gatesh---strict-could-not-see-a-skip-one-level-down) is about,
one file over.

 **Rejected: writing a sentence so a source has something to guard.**
`experiments-count` was written, fired the "claimed by no document" rule, and was
**deleted** - no document states how many numbered experiments there are, and
prose exists to say something rather than to feed a checker.

### Prove

```sh
python3 scripts/check-counts.py --selftest
python3 scripts/check-counts.py --strict
```

### Done, 2026-09-03

**18<!--n:counts-selftest--> planted defects, 0 failures**: a stale count refused; `--write` repairing
it and preserving `**bold**` between number and marker; a marker naming no
source; a source no document claims; an unreadable source reported as a **SKIP**
rather than a pass; only the *nearest* number counting as the claim; an
untracked document not scanned; and exit **2** outside a repository.

 **Seven stale counts on its first run over the real tree**, and one had
nothing to do with this session:

```
docs/AGENTS.md:534: claims 23 for 'snapshots-selftest', which reports 37
docs/AGENTS.md:536: claims 18 for 'aggregate-selftest', which reports 31
docs/AGENTS.md:932: claims 23 for 'runner-selftest',    which reports 28
docs/AGENTS.md:957: claims 146 for 'plan-cells',        which reports 176
docs/AGENTS.md:957: claims 122 for 'plan-planned',      which reports 131
docs/AGENTS.md:957: claims  24 for 'plan-unsupported',  which reports  45
docs/AGENTS.md:966: claims  28 for 'snapshots-selftest', which reports 37
```

 **§13's status board said the matrix expands to 146 cells (122 planned, 24
unsupported). It expands to 176 / 131 / 45** - wrong by 30 cells and by 21
unsupported configurations, in the table a reader consults to find out what this
project covers.

```
check-counts: 25 claim(s) over 15 source(s) in 149 document(s), every one
              agrees. 0 skipped.
```

 **It interlocks with [`T-020`](#t-020-gatesh---strict-could-not-see-a-skip-one-level-down)
by construction.** A source that cannot be read is a `check-counts: SKIP` line,
and the gate now counts a checker's internal skips - so an unbuilt
`alloc-runner` does not quietly retire a claim.

 **And that interlock fired on its first CI run, correctly.** The
`matrix and manifest` job builds `alloc-bench` alone, so `alloc-runner` was
absent and the job went red with

```
check-counts: SKIP runner-selftest: ./target/release/alloc-runner is not built
check-counts: --strict, and 1 source(s) could not be read
```

 **The local gate could not have caught it**, and the reason is worth keeping:
`scripts/gate.sh` builds **both** binaries itself, so the checker always had them
there. The gate and CI disagreed about what exists - which is
[`T-020`](#t-020-gatesh---strict-could-not-see-a-skip-one-level-down)'s asymmetry
running in the *other* direction, found the same day by the check that entry
made possible. The job builds `-p alloc-bench -p alloc-runner` now.

 **What this does not do.** It checks a number a session chose to mark. Prose
carrying an unmarked count is exactly as unchecked as before; what changed is
that marking one is now cheaper than keeping it right by hand.

---

## T-024: a mute diagnostic reported a tool failure as an allocator defect

**Source:** found 2026-09-03 by reading bench run
[`33723373486`](https://github.com/Azathothas/alloc-bench/actions/runs/33723373486)'s
own build log rather than its summary - the dispatch work order item 1 asked for.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

Every check in `finish_so` (`allocators/lib.sh`) had the shape

```sh
if ! "$NM" -D --defined-only "$SHARED" 2>/dev/null | grep -qE '…malloc$'; then
```

 **The exit code read is `grep`'s, and `nm`'s own error goes to `/dev/null`.**
So "this library does not export `malloc`" and "`nm` could not read this file at
all" produce the identical verdict - and the verdict printed is the first one.
An allocator defect invented out of a tool defect.

 It is [`RULES.md`](RULES.md) §4's *read every exit code from the process that
produced it* and `docs/AGENTS.md` §7's *2 is never reported as a pass*, in a
file that predates both.

### Premise

 **It fired, on a real artefact, on the run this session dispatched.**
tcmalloc's generated `cc_binary(linkshared = 1)` produced a shared object for the
first time - past the TLS wall, past the `find -P` wall, past "upstream declares
no shared-library target". `finish_so` refused it and printed:

```
shared object …/liballocbench.so does not EXPORT required symbol(s): malloc free realloc calloc
--- dynamic symbols it does export (first 40) ---
```

 **followed by nothing at all.** A header over an empty list, which is
consistent with an object that exports nothing *and* with an `nm` that never
ran, and says which of those it is nowhere.

 **That is tcmalloc's fourth recorded refusal, and the claim audit below cut
what this paragraph first said about it.** The draft read *"the third that is
the instrument rather than the allocator"*.  **That is not established.** Two
of the four were certainly the instrument - the TLS interception reported as a
build failure, and `find` not following the `bazel-bin` symlink - and one is
certainly upstream: musl is unsupported. **This fourth one is undecided**, and
saying so is the whole point: the diagnostic was unreadable, which is what is
fixed here; whether the artefact itself is at fault is a different question, and
the next dispatch answers it.

### Approach

Read the table **once**, and find out whether the read worked.

- `dynsyms=$("$NM" -D --defined-only "$SHARED" 2>&1)` with its own status.
- A failed read exits **2** - "could not run" - naming the tool, quoting what it
  said, and stating in the message that this says nothing about the allocator.
- An object with **zero** defined dynamic symbols is a **named state in words**,
  not an empty list under a header, and the message points at the link line
  rather than the source: an empty `.dynsym` is what a shared object gets with
  no exported-symbols list, or with everything localised.
- Every later test reads the captured text, so `nm` runs once instead of three
  times and cannot disagree with itself between calls.

### Prove

```sh
sh experiments/150-symbol-reads-tell-their-states-apart.sh   # exit 0
```

### Done, 2026-09-03

[`../../../experiments/150-symbol-reads-tell-their-states-apart.sh`](../../../experiments/150-symbol-reads-tell-their-states-apart.sh),
output committed, **exit 0**. It builds four shared objects and runs the **real**
`finish_so`, sourced from `allocators/lib.sh` - not a reimplementation of it,
which is the defect [`T-019`](mechanisms.md) was filed for.

| object | defined dynamic symbols | verdict | exit |
| --- | --- | --- | --- |
| exports malloc, free, realloc, calloc | 4 | accepted | **0** |
| exports other symbols only | 2 | refused, and **lists them** | **1** |
|  everything localised (`--version-script`) | **0** | refused, *"and it exports NOTHING AT ALL"* | **1** |
| not an ELF file | - | *"cannot read the dynamic symbol table … llvm-nm said: The file was not recognized as a valid object file"* | **2** |

 **The first row is the negative control**: a guard that refused everything
would pass the other three and be worse than the defect.

 **The probe found a `set -e` bug in the fix itself, by being run.**
`n=$(… | grep -c '[^[:space:]]')` - and `grep -c` exits **1** when the count is
zero, which is exactly the case the line exists to detect, so under `set -e` the
script died before the "exports nothing" branch could print. The probe reported
`empty.so produced no 'exports NOTHING AT ALL' line` and refused to pass. Same
family as `docs/AGENTS.md` §12 item 10.

 **AND THE DOOR SWEEP FOUND THE BIGGER HALF.** `finish_so` is taken by the
**28** `preload` cells. `finish` - its archive counterpart, ten lines above it in
the same file - had the identical `"$NM" … 2>/dev/null | grep -q …` in **four**
places, and is the path taken by every other cell in the matrix: `rust-global`,
`libc-surgery`, `link-override` - **103** of the **131** planned, against
`preload`'s **28**.  Nothing
had tripped it, so it was found by asking *"what other door reaches this?"*
after the fix, not by the failure that prompted one. It is fixed the same way,
and the probe covers both.

 **One of those four failed OPEN, and that one is worse than a wrong
diagnosis.** Every other check refuses when `nm` breaks: a symbol reads as absent
and the build stops. The `MODE=prefixed` assertion asks the *opposite* question -
*does this archive define `malloc`?* - so `grep` finding nothing is the answer
that lets the build **through**. A broken `nm` would have passed a prefixed
archive that does define `malloc`, and `rust-global` and `libc-surgery` would
then have been **the same experiment, published as two** - which is
`docs/AGENTS.md` §2.2's failure reached from inside the build rather than from
the report. The probe asserts it: `MODE=prefixed` over a malloc-defining archive
exits **1**, and over an unreadable one exits **2, not 0**.

 **Verified end to end on a real preload build**, not only on fixtures:
`alloc-bench run --suite preload --arch x86_64 --distro alpine --allocator
mimalloc,system --strict` → **2 of 2 cells `ok`, 0 validator errors, exit 0**.

 **AND THE SWEEP REACHED `examples/verify.sh`, WHICH THIS ENTRY FIRST SAID TO
LEAVE ALONE.** The first version of this entry recorded a *decision* not to
touch the examples layer - it uses only the distribution's own tools, each image
installs `binutils`, the transcripts are committed.  **That decision was
wrong, and re-reading the code rather than the argument is what showed it:**

```sh
want_no_symbol() {
    if nm --defined-only "$_b" 2>/dev/null | grep -qE "…$_s\$"; then
        _bad "$_b STILL defines $_s …"
    else
        _ok  "$_b does not define $_s (the displaced allocator is gone)"
```

 **`want_no_symbol` failed OPEN, and it is the examples' negative control.**
"Nothing found" is its *passing* answer, so an `nm` that could not read the file
reported **the displaced allocator as gone**, with a . That is the same
direction `finish`'s prefixed check failed in, in the layer whose entire subject
is that a negative control is a claim about two states
([`T-018`](mechanisms.md)).

 **And the file's own header asserted the opposite, ten lines above it:**
*"EVERY CHECK READS AN EXIT CODE FROM THE PROCESS THAT PRODUCED IT. Nothing here
is piped into anything whose status would replace it."* A document stating a rule
its own code breaks is the harder defect to find, so the correction is kept in
place rather than the sentence quietly repaired.

 **Mutation-tested in a container**, `want_no_symbol` restored to the old pipe:

```
 want_no_symbol: a file nm cannot read          DID NOT REFUSE (pass=1 fail=0)
21 case(s), FAILURES ABOVE
```

`pass=1` - it did not merely fail to refuse, it **actively passed**. With the fix
and two new planted cases, `examples/verify-selftest.sh` is
**21<!--n:verify-selftest-cases--> cases, 0 failures**.

 **What this does NOT establish, and it matters for
[`T-003`](mechanisms.md).** Whether tcmalloc's own shared object exports nothing,
or whether `nm` failed on it, **cannot now be recovered from that run** - the old
code destroyed the distinction, which is the whole finding. The next `preload`
dispatch will say which, in words. Bazel cannot run on this host, so the probe's
third case is a library *shaped like* the one that run produced, not that
library.

---

## T-026: the README is written for this project, not for a reader

**Source:** the operator, 2026-09-03, on landing on the repository page: *"a human
landing on the GitHub page sees the readme, immediately understands the project
and sees the report/published benchmarks, understands what he needs, sees the
examples, understands how to incorporate in his project."*
**Category:** instrument
**Priority:** P1
**Effort:** L
**Status:** done

### Problem

 **The README is a record of what this project learned, not a document that
serves a reader.** It is **306 lines**, of which **26** carry a // marker -
markers that mean something inside this repository's conventions and nothing to
someone arriving from a search result.

 **Measured against the four things the operator says a reader must get:**

| the reader wants | where it currently is |
| --- | --- |
| what this is |  lines 1–13, and this part works |
| the published benchmarks |  five result sections, `### 1` … `### 5`, before any of them says which to read first |
| what *they* need |  nowhere directly. §2 answers it - *"jemalloc on musl, nothing on glibc"* - buried under two tables and a caveat |
| the examples |  one line at 21–24, above the fold but before the reader knows why they would want it |
| how to incorporate it |  a link only. `docs/replacing-the-allocator.md` is the how-to and the README never says what it contains |

 **The results sections are also a history of how the project found things**
rather than an ordering by usefulness: §1 is the *caveat* (the ranking does not
transfer), and the actionable answer is §2.

### Approach

Not prescribed in detail - that is the entry's work - but the shape is fixed by
the operator's sentence, in that order: **what it is → what you should do →
the evidence → how to do it → what it does not tell you.**

 **What it must NOT do:**
- **Drop the caveat.** *"The ranking is a property of the machine"* is this
  project's central finding and the reason its recommendations are direction-only.
  It moves; it does not go.
- **Lose a citation.** Every number in the README traces to a committed dataset
  today, and `scripts/check-counts.py` guards the ones that are marked. A shorter
  README with an uncited number is worse than a long one.
- **Become a marketing page.** Technical, concise, consistent.

### Prove

```sh
python3 scripts/check-docs.py --strict
python3 scripts/check-counts.py --strict
sh scripts/gate.sh --strict
```

 Those establish that nothing broke, not that the README is good - which is a
reading job.  **The acceptance is a reader's path**, and the entry closes when
someone landing on the repository page can, without scrolling back: name what the
project measures, find the recommendation for their libc, open a published
dataset, and find the how-to. Write down which section serves each.

### Done, 2026-09-03

Rewritten in the order the operator's sentence fixes - **what it is → what you
should do → the evidence → how to do it → what it does not tell you** - with the
recommendation moved above the caveat rather than under two tables. **306 → 313
lines**, so the fix was ordering rather than length.

 **The reader's path, section by section, which is the acceptance:**

| the reader wants | before | now |
| --- | --- | --- |
| what this is |  lines 1–13 |  unchanged, plus the seven allocators named |
|  **the recommendation that applies to them** |  §2, under two tables and a caveat |  **§1, a five-row table keyed on what you ship**, with what it buys, what it costs and how sure |
| the published benchmarks |  five sections, none saying which to read first |  **§3**, and §1's "how sure" column links each claim to the run count behind it |
| the examples |  one line before the reader knows why |  **§2**, immediately after the recommendation - *"you decided; here is how"* |
| how to incorporate it |  a link only |  **§2** names the four mechanisms with *"for you if"* per row, then links the how-to |
| the caveat | §1, before the answer |  **§3.1**, sharper - and §1's own  line says the table is not a ranking |

 **Three things it gained that the entry did not ask for**, each a defect found
while rewriting:

-  **The Status block contradicted §4.1 of the same file.** It said *"Seven of
  eight allocators have numbers"* and *"Google tcmalloc has none"* a hundred
  lines below a section reporting tcmalloc's number. `check-counts.py` could not
  catch it: the count was not marked.
-  **"reproduced on four machines" was stale.** Derived from every published
  `run.json`: **5** distinct CPU models across 19 datasets.
-  **"13–42% faster" merged two allocators' sample sets and rounded the floor
  up.** Recomputed per allocator from `libc-contrast`: jemalloc **13.5–37.1%**
  over 9 cells, rpmalloc **12.7–42.0%** over 6.

 **And it now carries four marked counts where it carried none** - work-order
item 7. `check-counts.py` went from 35 claims to **39**.

---

## T-027: the trial-and-error narrative belongs in docs/history/, not in the code

**Source:** the operator, 2026-09-03: *"trim 'fat' from docs and comments from
code/scripts now that all trial and errors are over, move historical artefacts
and lore to docs/history/ not main docs."*
**Category:** instrument
**Priority:** P2
**Effort:** L
**Status:** done

### Problem

This project deliberately records *what it cost to learn* beside the thing
learned, and while it was still finding defects that was load-bearing - a comment
saying "this was `git diff` and it silently discarded every window" is why nobody
reverts the fix.

 **The trials are over, and the ratio has inverted.** Measured 2026-09-03:

| | comments | total | |
| --- | --- | --- | --- |
| shell (`scripts/`, `allocators/`, `examples/`) | **1899** | 5079 | **37%** |
| rust (`crates/*/src/`) | 1720 | 9340 | 18% |
| python (`scripts/`) | 393 | 3601 | 11% |
| `docs/AGENTS.md` | - | **1151** | 187 lines carry a marker |
| `docs/*.md` | - | 3883 across 11 files | |

 **More than a third of the shell in this repository is prose**, and much of it
is incident narrative rather than the technical reason a line is the way it is.

### Approach

 **The test for each comment is: does a reader who has never seen the bug need
this to avoid re-breaking the line?**

- **Keep** the technical reason: *"`|| true` - `grep -c` exits 1 on a count of
  zero, which is the case this line detects."*
- **Move** the incident: *"found on bench run 33723373486, where the diagnostic
  printed a header over an empty list…"* → `docs/history/`.
- **Keep** the  markers on rules that still bite. **Cut** them where they
  decorate ordinary prose.

 **`docs/history/` becomes `docs/history/` at the repository root**, per the
operator, so the lore is visibly separate from the documentation rather than
filed under it.  **The recorded figure for that rename was ~691 relative links, and it was a
misreading.** 691 was `scripts/check-docs.py`'s count of EVERY relative link in
the tree - it prints `N documents, M relative links` - not the links the rename
touches. Measured 2026-09-03: **28** inbound references across 11 files, plus
**28** outbound `../` links inside the moved files, whose depth changes by one.
 The whole-tree figure is the right thing to check AFTER the move, and it is
what proves none broke, in the form that does not go stale: **every reference
resolves, 0 skipped**.  Do NOT copy its link TOTAL into prose - it moves with
every document edited, and nothing marks it, which is the trap
[`T-023`](#t-023-nothing-checks-a-count-written-in-prose) exists for.

 **What must survive the trim**, because it is the project's own rule and not
decoration ([`RULES.md`](RULES.md) §4): *superseded wording is moved, not
deleted.*  A trimmed comment whose finding is not in `docs/history/` is a deletion,
and the next session re-learns it.

 **And one class of comment is exempt**: a note explaining why a check is
written the way it is, where the obvious simpler form fails open. Those read like
lore and are the reason the check works.

### Prove

```sh
python3 scripts/check-docs.py --strict
sh scripts/gate.sh --strict
git grep -c '' -- 'scripts/*.sh' | head
```

 Passing means every link still resolves, the gate is unchanged at 20/20, and
**every finding removed from a comment is findable in `docs/history/`** - that last
one is a reading job and is the point of the entry.

### Done, 2026-09-03

#### The rename

`docs/history/` → **`docs/history/`**, at the repository root. **28** inbound
references across 11 files and **28** outbound links inside the moved files were
updated; `check-docs.py --strict` reports **every reference resolves, 0
skipped**.

 **`check-docs.py` validates link TARGETS, not labels**, and the first pass
left **16** links whose visible text still said `../methodology/reviews.md` while
pointing at `../../../methodology/reviews.md`. Found by comparing label against
target directly; realigned.  A checker that passes is not the same as a
document that reads correctly, and this is a gap in the checker rather than a
slip in the edit.

#### The trim

| | comment lines | total | |
| --- | --- | --- | --- |
| shell, before | 1946 | 5222 | **37.3%** |
| shell, after | **1805** | 5081 | **35.5%** |

**141 comment lines moved** - not deleted - into
[`../what-the-comments-said.md`](../what-the-comments-said.md),
which records each passage **verbatim**, names the file it came from, and says
what stayed behind and why. Files touched: `allocators/lib.sh`,
`scripts/build/libc-surgery.sh`, `scripts/vendor/mine-repo.sh`,
`examples/verify.sh`, `examples/verify-selftest.sh`, `scripts/gate.sh`,
`allocators/tcmalloc/build.sh`, `allocators/hardened_malloc/build.sh`,
`allocators/rpmalloc/build.sh`.

####  Why 37.3% became 35.5% and not 20%

**Because most of what is left is not lore, and cutting it would be the deletion
this entry forbids.** Applying the entry's own test - *does a reader who has
never seen the bug need this to avoid re-breaking the line?* - comment by comment
over the nine densest files, the residual falls into three classes the entry
explicitly protects:

- **the contract.** `allocators/lib.sh`'s header IS the interface every recipe
  implements; `examples/`' headers are the teaching material the examples exist
  to be.
- **the exempt class the entry names**: *"a note explaining why a check is
  written the way it is, where the obvious simpler form fails open."* Nearly
  every remaining  block in `lib.sh`, `verify.sh` and `gate.sh` is one.
- **measured constraints with citations** - `config.log` line 4001, HTTP 420 on
  a browser User-Agent, `fork.lo` defining `fork`. A reader who does not know
  them writes the bug back.

 **What actually moved is what the entry asked to move:** which run found it,
which session, what the diagnostic printed, how many cells were affected, and the
date a fix landed. Narrative-shaped comment lines - those naming a date, a run id
or a session - went from **46 to 31**, and the ones that remain are citations
attached to a technical claim rather than stories.

 **So the honest form of this entry's result is a rule, not a percentage:** the
code now says *why a line is the way it is*, and `docs/history/` says *what it cost to
find out*. A future session that wants a smaller number will have to delete
findings to get it.

---

## T-028: every recipe picked its shared object by name, and one shipped a text file

**Source:** bench run
[`33749457837`](https://github.com/Azathothas/alloc-bench/actions/runs/33749457837),
2026-09-03 - the `preload` dispatch this session made to give the
`preload-x86_64` window a second run.
**Category:** instrument
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

 **tcmalloc's number did not reproduce, and the reason is the recipe rather
than the allocator.** The `debian` cell came back

```
build_failed: allocator build failed (rc=2): cannot read the dynamic symbol
table of .../liballocbench.so with 'gcc-nm'
 This says NOTHING about the allocator: the library was built and the tool
   that inspects it failed. gcc-nm said:
   | /usr/bin/nm: .../liballocbench.so: file format not recognized
```

 **That message is [`T-024`](#t-024-a-mute-diagnostic-reported-a-tool-failure-as-an-allocator-defect) working exactly as designed.** Before that fix this
would have been filed as *"tcmalloc exports no malloc"* - an allocator defect
invented out of a tool failure. It named the right category on its first
contact with a real instance.

 **What it could not say was WHY the file was unreadable**, and that is this
entry. Every recipe that produces a shared object chose it the same way:

```sh
so=$(find -L "$B" -type f -name 'libfoo*.so*' | head -1)
```

Two defects in one line, and **five recipes had it** - `jemalloc`, `mimalloc`,
`snmalloc`, `mesh` and `tcmalloc`:

1. **`*.so*` matches more than `.so`.** Bazel writes its link-action parameter
   file beside the library it builds as `<target>.so-2.params`, and a `.jdeps`
   beside that. Both are TEXT and both match `libtcmalloc*.so*`.
2. **`head -1` takes whatever the directory order yields**, which is not stable
   across filesystems or machines - so the same recipe at the same commit can
   take the library on one runner and a parameter file on the next.

 **The specific file that run took is an INFERENCE, not a reading.** The run's
artefact had expired by the time this was diagnosed
(`AuthenticationFailed … Signature not valid in the specified key time frame`),
so what is established is the glob, the `head -1`, and `nm`'s message.  The
fix deliberately does not depend on the inference.

### Approach

 **Stop trusting the name. The name orders the candidates; the ELF header
decides.** `allocators/lib.sh` gains two functions, so the fix is in the
contract file rather than in five copies:

- `elf_kind` - what a file actually is, in one word: `not-readable`, `not-elf`,
  `elf-relocatable`, `elf-executable`, `elf-shared`.  Four states told apart
  on purpose; an unreadable file and a file that is not a library must never
  produce the same sentence.
- `pick_elf_so` - reads candidates on stdin in preference order, returns the
  first genuine `ET_DYN`, and names every rejection **with its kind** on stderr.
  Duplicates are collapsed, because a caller offering a preferred pattern then a
  general one naturally offers the same path twice and a refusal reporting
  "two candidates" where there was one is a miscount waiting to become a
  sentence in a handoff.

All five recipes now `sort` their candidates and pipe them through it.

### Prove

```sh
sh experiments/180-which-file-did-the-recipe-take.sh
```

### Done, 2026-09-03

[`../../../experiments/180-which-file-did-the-recipe-take.sh`](../../../experiments/180-which-file-did-the-recipe-take.sh),
output committed, exit 0. Over a planted tree holding a real shared object, an
`ET_REL` object wearing a `.so` name, and the two text files Bazel leaves beside
its output:

| | old selector | new selector |
| --- | --- | --- |
| files its glob matches | **4**, one of them a library | - |
| what it returns | `libtcmalloc_lookalike.so` - **`elf-relocatable`** | `libtcmalloc_allocbench.so` - `elf-shared` |
| with only non-libraries present | returns one anyway | **refuses**, naming each file's kind |

 **What the probe does NOT establish, stated in the probe itself:** that the
answer *changes* between two directory orders. Creation order is not `readdir`
order and no probe can dictate what a filesystem enumerates first. What is
demonstrated is that the old selector returns a non-library; the
order-dependence is an argument from `head -1` over an unsorted `find`, and the
fix removes the ambiguity and the ordering question together.

 **`od` was verified in both image families rather than assumed** - the header
read is useless if the tool reading it behaves differently inside a container:

| image | `od -An -tx1 -N4` | `od -An -tx1 -j16 -N2` |
| --- | --- | --- |
| `alloc-bench/alpine-x86_64:local` (GNU coreutils 9.11) | `7f454c46` | `0300` |
| `debian:latest` | `7f454c46` | `0300` |

 **Container half, with the allocator cache deleted so the recipe actually
re-ran:** `alloc-bench run --suite preload --arch x86_64 --distro alpine
--allocator mimalloc --strict` → **2 of 2 cells `ok`**, `validate` exit **0**,
0 errors.

###  Verified end to end by the dispatch it was blocking, 2026-09-03

Bench [`33790455334`](https://github.com/Azathothas/alloc-bench/actions/runs/33790455334),
`preload` on x86_64 with this fix in the tree: **overall conclusion `success`**,
every job green including the `rolling aggregate` job that refused the previous
attempt.

 **Google tcmalloc's number REPRODUCED**, and it is the tightest thing this
project transfers:

| run | machine | `debian / dynamic`, rel time |
| --- | --- | --- |
| [`33729832142`](https://github.com/Azathothas/alloc-bench/actions/runs/33729832142) | AMD EPYC 9V74 | **1.2664×** |
| [`33790455334`](https://github.com/Azathothas/alloc-bench/actions/runs/33790455334) | AMD EPYC 7763 | **1.2822×** |

**1.2% apart, on two different CPUs.**  So the cell that failed with `nm: file
format not recognized` was the recipe copying out the wrong file, and nothing
about the allocator - which is what this entry claimed and could not yet
demonstrate.

 **The `preload-x86_64` window now holds two runs**, its `roll` job committing
them unaided (`6e2bcff`), and it reports every allocator holding its rank in
both groups - the first window in this project that has not refused an ordering.
 **Both runs are AMD EPYCs.** The window says so itself; it is a statement
about two similar machines, not about transfer.
