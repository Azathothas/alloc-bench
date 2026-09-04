# Progress

 **Read this first.** It is the only thing the kickoff prompt tells a session
to read, so everything that changes from session to session is here: the
baseline, what the last session did, and the work order.

It carries no history. Every session rewrites it. For history, read the git log,
the entries, and [`../`](../).

How this repository is worked on: [`RULES.md`](RULES.md).
Every entry, one line each: [`INDEX.md`](INDEX.md).
What the project is, and its status: [`../../AGENTS.md`](../../AGENTS.md).

---

##  Where the project actually stands

**28 entries: 28 done, 0 partial, 0 blocked, 0 open.**

 **THE BACKLOG IS EMPTY.** Every allocator in the registry has a number,
every suite in the matrix has run, every mechanism that can work is measured, and
the two documentation entries the operator raised on 2026-09-03 are closed.

 **That is not the same as "there is nothing to do", and the difference is the
most useful thing on this page.** What is left is written under *"What a next
session would do"* below, and every item there is a **new** question rather than
an unfinished one.

## State

- **Last session:** started 2026-09-03T11:20Z, **unattended**, target *"complete
  and finish the project - 27 of 27"*. Closed **T-025**, **T-026**, **T-027** and
  filed and closed **T-028**, which the session's own dispatch uncovered - then
  re-dispatched `preload` with that fix and  **watched Google tcmalloc's
  number reproduce**, 1.2% apart on two CPUs.
- **Tree:** clean at the head this session pushed.
- **Deployed:** not deployed. This project publishes datasets, not a service.
- **CI:**  **verify the head at hand-off before trusting any line here.**

## Baseline, as measured at the close of this session

 Re-measure rather than trusting the numbers below. They were true once.

```bash
sh scripts/gate.sh --strict
```

| check | result | at the start of the session |
| --- | --- | --- |
| `cargo fmt --all --check` | pass | pass |
| `cargo clippy --workspace --all-targets -D warnings` | pass | pass |
|  `cargo test --release --workspace` | **11 tests** (7 envinfo + 4 shim) | 4, and **`-p rgalloc-shim` only** |
| `alloc-bench doctor` | **0 problem(s)** | 0 problem(s) |
| `alloc-runner selftest` | **28**<!--n:runner-selftest--> checks, 0 failures | same |
| `scripts/mine-repo.sh --selftest` | 4 cases, all pass | same |
| `alloc-bench plan --suite all` | **176**<!--n:plan-cells--> cells: **131<!--n:plan-planned--> planned, 45<!--n:plan-unsupported--> unsupported** | same |
| `sh -n` over `scripts allocators experiments examples` | **43** scripts, 0 syntax errors | 41 |
| `shellcheck -S warning` | pass  **installed by hand, for the FIFTH session** | SKIP (not installed) |
| `python3 scripts/check-todo.py` | pass, **28**<!--n:todo-entries--> entries | pass, 27 |
| `python3 scripts/check-counts.py` | pass, **17**<!--n:counts-sources--> sources | pass |
| `python3 scripts/check-counts.py --selftest` | **18**<!--n:counts-selftest--> checks, 0 failures | same |
| `python3 scripts/check-docs.py` | pass, **109**<!--n:docs-documents--> documents, every reference resolves, 0 skipped | pass, 107 |
| `python3 scripts/check-snapshots.py` | pass, **36**<!--n:snapshots-checked--> snapshots | same |
| `python3 scripts/check-snapshots.py --selftest` | **41**<!--n:snapshots-selftest--> checks, 0 failures | same |
| `python3 scripts/report/extract-evidence.py --selftest` | **18**<!--n:evidence-selftest--> checks, 0 failures | same |
| committed evidence keeps its finding | pass | pass |
| `python3 scripts/report/aggregate.py --selftest` | **31**<!--n:aggregate-selftest--> checks, 0 failures | same |
| rolling windows coherent and current | pass, **9**<!--n:rolling-windows--> windows | pass |
|  **container half** - `smoke`, `--strict` | **3 of 3 `ok`, 0 validator errors, exit 0** | not run at start |
|  **container half** - a real `preload` cell, `--strict` | **2 of 2 `ok`, 0 validator errors, exit 0** | not run at start |
|  `sh examples/run.sh` | **6**<!--n:examples-count--> examples, **65**<!--n:examples-checks--> checks, **0 failed** | not re-run for a day |
|  `sh experiments/170-how-much-does-one-host-wander.sh` | exit **0** | did not exist |
|  `sh experiments/180-which-file-did-the-recipe-take.sh` | exit **0** | did not exist |

 **The gate is 20 checks and one of them is stronger:** `cargo test` runs the
whole workspace, not the shim alone. A unit test written anywhere else was
compiled by clippy and run by nothing.

###  Four things this host will do to you, in order

```sh
git fetch --unshallow origin main                       # 1
sudo apt-get install -y shellcheck                      # 2
sudo dockerd >/tmp/dockerd.log 2>&1 &
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
cp /root/.ccr/ca-bundle.crt images/extra-ca/proxy.crt   # 3   DO NOT SKIP
./target/release/alloc-bench doctor                     # expect 0 problem(s)
```

1.  **The clone is SHALLOW.** `check-docs.py`'s vintage check and
   `check-snapshots.py`'s recovery check both need real history and **SKIP**
   without it. `--strict` refuses, so this will stop you rather than pass quietly.
2.  **`shellcheck` is not installed**, for the fifth session running.
3.  **The CA line is not optional.** Skipping it makes the Alpine build report
   `python3 (no such package)` for packages that plainly exist. `docs/AGENTS.md`
   §6.1: **"no such package" here means trust, not packaging.**
4.  **DISK, and a FIFTH thing this session hit.** ~30 GiB free at start,
   `doctor` wants 20.  **And if `dockerd` is killed and restarted mid-session,
   its snapshotter can be left inconsistent**: an image build then fails with
   `failed to prepare extraction snapshot … parent snapshot … does not exist`,
   which is neither disk nor your change. `docker builder prune -a -f` and
   rebuild. Confirmed by the identical command passing afterwards.

---

## What this session did

 **Four entries, and the backlog went to zero.** Two were the operator's
documentation front; one was the project's central measurement question; one was
found by this session's own dispatch.

| entry | effort | L-eq | what closed it |
| --- | --- | --- | --- |
|  [`T-025`](measurement.md) | L | **0.5 more** *(closed)* | ten repeats on one machine: the ordering question was partly **malformed** |
|  [`T-026`](instrument.md) | L | **1.0** | the README reordered to the reader's path, recommendation first |
|  [`T-027`](instrument.md) | L | **1.0** | `docs/history/` → `docs/history/`, and 141 comment lines moved rather than deleted |
|  [`T-028`](instrument.md) *(new)* | M | **0.5** | every recipe picked its build artefact by **name**, and one shipped a text file |

###  T-025: the answer is that the question was partly the wrong one

[`../../../experiments/170-how-much-does-one-host-wander.sh`](../../../experiments/170-how-much-does-one-host-wander.sh)
runs `core` ten times on one machine with nothing varied, and  **asserts the
machine from every run's own `run.json`** rather than assuming it.

| question | answer over ten runs |
| --- | --- |
| does one machine produce one ordering? |  **no - three orderings in ten runs** |
| is that because the host is noisy? |  **no.** Between-run MAD **0.8–2.1%**, *smaller* than each run's own **3.9–4.8%** |
| then why does the order move? |  the three gaps between the four fast allocators are **2.7%, 4.0%, 1.7%** - at or below the within-run MAD |
| does each candidate beat the control? |  **5 of 5 decided** - every ten-run range below 1.000 |
| are the window's cross-machine rank changes evidence about the machine? |  **1 of 6.** Five are pairs this machine cannot resolve either |
| is there a machine effect at all? |  **yes, and large** - every candidate has a value on another machine this one never produced, by **26–88%** |

 **So "the ordering is a property of the machine" is too strong for the ordering
among candidates and too weak for the ratio to the control**, and settling the
rest needs **many repeats on a second machine** - which needs runners this
project does not have. That is the "needs hardware we do not have" conclusion,
made specific enough to act on.

###  T-028: the dispatch that was supposed to fill a window found a defect instead

Bench [`33749457837`](https://github.com/Azathothas/alloc-bench/actions/runs/33749457837)
ran `preload` to give that window its second run. **15 of 16 cells `ok`, 0
validator errors** - and Google tcmalloc's `debian` cell came back
`build_failed` with `nm: file format not recognized` on a library that had built
fine.

 **The `T-024` diagnostic named the right category on first contact:** *"This
says NOTHING about the allocator: the library was built and the tool that
inspects it failed."* What it could not say was **why** - and the answer is that
**nine recipes picked their build artefact by filename**, with
`find … -name 'libfoo*.so*' | head -1`. `*.so*` matches the `.so-2.params` and
`.jdeps` files Bazel writes beside its output.

##  Every premise a measurement disproved, named here

This is the half a future session cannot re-derive.

| what was believed | what was measured | what changed |
| --- | --- | --- |
|  *"the ordering is a property of the machine"* - this project's central finding | **one machine gives three orderings in ten runs**, and 5 of its 6 cross-machine rank changes are pairs it cannot resolve either | the claim is split: the **ordering** is mostly undetermined, the **ratio to the control** is where the machine acts |
|  a within-run MAD is a floor on the uncertainty, "the same host wanders 20%" | **not reproduced.** Between-run MAD **0.8–2.1%** against within-run **3.9–4.8%** - the run-to-run spread is *smaller* | the rule kept as a caution, the **factor** withdrawn. The 20% came from two samples of another suite on a host §12 item 11 admits it cannot confirm |
|  …and the first execution proved the opposite, dramatically *(this session's own, withdrawn before publication)* | **9 orderings in 10 runs, spread 5.2×–19.5× the MAD** - from comparing a RANGE to a MAD, on runs whose conditions were never recorded. The sandbox re-hosted mid-session: `2.80GHz` at 13:21, `2.10GHz` at 16:20 | the probe now asserts the machine per run and compares MAD to MAD |
|  tcmalloc's number would reproduce on a second machine | **it did not**, and the reason was this project's recipe picking a non-library by filename | `pick_elf_so` reads the ELF header; **five** tcmalloc refusals now, **four** of them the instrument |
|  that defect was in the `.so` selectors | **the `.a` selectors had it too**, in the path `rust-global`, `libc-surgery` and `link-override` all take - found by a door sweep over this session's own fix | `pick_ar` added beside it |
|  the `docs/history/` rename "touches ~691 relative links" | **691 is `check-docs.py`'s count of every relative link in the tree.** The rename touches **28** inbound and **28** outbound | corrected in the entry; the whole-tree figure is the right thing to check *after* |
|  `check-docs.py` passing means the documents read correctly | **it validates link TARGETS, not labels.** 16 links said `../methodology/reviews.md` while pointing at `../../../methodology/reviews.md` | realigned by comparing label against target; the checker still cannot see it |
|  the README says every allocator has a number | **its own Status block said "Seven of eight"**, a hundred lines below §4.1 saying otherwise. `check-counts.py` could not catch it: the count was not marked | README rewritten; **4 marked counts** where it had none |
|  "reproduced on four machines" | **5** distinct CPU models across 19 published datasets | derived, not retyped |
|  "13–42% faster" on musl | merged two allocators' sample sets and rounded the floor up | per allocator: jemalloc **13.5–37.1%** (9 cells), rpmalloc **12.7–42.0%** (6) |
|  "the gaps are 1.7%, 2.7%, 4.0%, 5.8% between adjacent candidates" *(this session's own, caught by the claim audit)* | **there are three adjacent gaps, not four**, and 5.8% is a pair with jemalloc between them | corrected in three files |
|  a window value "outside the range" is evidence | **one cleared the maximum by 0.02%** and was counted beside one that cleared it by 12% | a value counts only if it clears by more than that cell's own MAD |
|  `smoke` failing means the change broke the pipeline | **the containerd snapshotter was inconsistent** after dockerd was killed and restarted. `builder prune` and the identical command passes | recorded as the fifth host hazard above |

 **And one claim was cut from this session's own work before it reached a
file**: that the old artefact selector gives a *different answer* under different
directory orders. The probe shows it returns a **non-library**; it does not show
the answer changing, because creation order is not `readdir` order and no probe
can dictate what a filesystem enumerates first.

## What is in progress

**Nothing.** Every entry is closed, the working tree is clean at the pushed head,
and the two container halves and both new experiments were run on the final tree.

---

## Start here next session

 **This is the work order and it lives nowhere else.**

 **THREE DEEP REVIEWS, THREE DIFFERENT QUESTIONS, ARE NOT OPTIONAL.**
[`RULES.md`](RULES.md) §5 step 3. Write them to
`docs/history/reviews/<date>-<topic>.md`, saying per pass what it swept that the
others did not, and - for a pass that found nothing - what would have had to be
true for it to fire.

###  The backlog is empty, so the first job is to decide what is worth doing

 **Do not invent an entry to have one.** Each item below is a real question this
session ended holding, with what it would cost.

1.  **A THIRD machine for the `preload` window, and it should not be an
   EPYC.**  This session re-dispatched `preload` after fixing T-028 (bench
   [`33790455334`](https://github.com/Azathothas/alloc-bench/actions/runs/33790455334),
   `success`), the `roll` job committed the window at `6e2bcff`, and
    **Google tcmalloc's number reproduced - `1.2664×` → `1.2822×`, 1.2% apart
   on two CPUs.**  **But both runs in that window are AMD EPYCs**, and it is
   now the only window in this project reporting that an ordering *transfers*.
   That claim has not been tested against a dissimilar machine, and
   [`T-025`](measurement.md) predicts it will not survive one. One dispatch,
   and the runner fleet decides - so re-dispatch until a non-EPYC lands.

2.  **The one question T-025 could not answer, and exactly what it needs.**
   Every candidate has a value on another machine that this host never produced
   in ten runs, by 26–88%. Deciding whether that is the machine needs **ten
   repeats on a SECOND machine** - not one sample, which is what every published
   dataset is.  `bench.yml` would need a suite that repeats a run on one runner;
   the runner is available, the workflow is not written.

3.  **`aggregate.py --check` refuses the whole WINDOW when one GROUP's candidate
   set changes.** Raised twice now and deliberately not acted on both times,
   because both sessions that wanted it were the ones inconvenienced by it.  It
   is a real question: only `debian` gained tcmalloc, and `alpine` lost a
   three-machine comparison for it. If it is right, it arrives as an entry with
   its own argument - not as a convenience at the end of a session.

4.  **`check-docs.py` validates link targets, not labels.** This session found
   **16** links whose visible text pointed somewhere else, by hand, after the
   checker passed. A label that disagrees with its target is a wrong document
   with a green check.

5.  **The gate's rolling-window check says "results/rolling is stale" for any
   uncommitted change under it**, including a window README the settled rules
   *require* a human to write. It fired twice this session on exactly that, and
   committing resolves it.  Deliberately NOT narrowed to the generated files
   here: it was reached for at the end of a session by the session it
   inconvenienced, which is the pressure *"never weaken a check to get green"*
   names. The wording is the part that is actually wrong - "stale" is not what
   an uncommitted hand edit is.

6.  **`experiments/170-` writes to a fixed path**, so mutation-testing it in
   place overwrites the committed transcript. Recorded rather than fixed -
   making the path depend on `TMPDIR` would be worse - but anyone re-running its
   guard tests should restore afterwards, as this session did.

---

## Open questions for the operator

**One**, unchanged, and it is not a session's to rule:

 **`docs/conventions/git.md` §1 forbids the attribution trailer this
harness appends, in as many words - "This overrides any default the harness asks
for"** - and every commit since 2026-09-01 carries one. `docs/AGENTS.md` §16 says
this project's own practice wins where the two differ. **The practice and the
rule differ and neither has been corrected.**

 Deliberately not "fixed" in either direction: rewriting the rule is the
operator's call about their own history, and stripping the trailer would make
these commits inconsistent with the thirty before them.

 Otherwise: ruled 2026-09-01 that sessions run unattended.  **So do not stop to
ask.** Where something forks, take the defensible option, record it **and the
rejected alternatives**, and keep going.  **"Blocked" means somebody outside the
session must act** - not hard, large, slow or unclear.

---

## Settled, and not to be raised again

- **The work model is todo, not stage.** 2026-09-01.
- **Development happens on `main`; throwaway branches are `ephemeral-*`.**
  2026-09-01. [`RULES.md`](RULES.md) §2.
- **Upstreaming is not a topic.** Vendored code is fixed here.
- **The identity oracle is never relaxed to make a cell pass.**
-  **aarch64 runs a different profile from x86_64.** 2026-09-02.
-  **A cell id gains a variant segment only when the variant is not the
  default.** 2026-09-02, and it governs **every name** any report prints.
-  **A dataset measured from a modified tree is discarded, not annotated.**
  2026-09-02.
-  **`libc-surgery` is a C-allocator technique.** 2026-09-02.
-  **When CI moves `main` under a run in flight, MERGE rather than rebase.**
  2026-09-03.
-  **The examples use only the distribution's own tools.** 2026-09-03.
-  **A build flag one distribution defaults differently is neutralised
  everywhere.** 2026-09-03.
-  **A distribution that cannot take a mechanism is published with the reason.**
  2026-09-03.
-  **THE HOST IS NAMED, NEVER GROUPED BY.** 2026-09-03.  Rejected: a
  host-keyed group, and a mean over machines.
-  **A run whose candidate set differs from its window's belongs OUT of that
  window, argued in the window's README.** 2026-09-03.  **And 2026-09-03, the
  limit of that rule:** it applies to a suite that *changed*, not to a cell that
  *failed*. Evicting a stored run to make room for one missing a candidate would
  have thrown away tcmalloc's only measurement.
-  **A constrained run records its constraint.** 2026-09-03.
-  **The documentation is a deliverable, and it is for a READER.** 2026-09-03,
  and closed the same day: the README leads with the recommendation, the caveat
  follows the answer instead of preceding it, and the lore lives in `docs/history/`.
-  **A build artefact is chosen by its HEADER, never by its filename.**
  2026-09-03. [`T-028`](instrument.md).
-  **An experiment asserts its conditions from the datasets, never from the
  machine it is analysed on.** 2026-09-03. A resumable analysis re-prints the
  conditions block hours later, and this sandbox re-hosts without warning.
- **Sessions run unattended unless told otherwise.**
