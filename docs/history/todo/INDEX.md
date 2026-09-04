# TODO

Every entry, one line each, sorted by id. The entry itself lives in the
category file its row links to, and it closes **there**, in place, with its own
acceptance command actually run and the output recorded.

 **What to work on next is not here.** [`PROGRESS.md`](PROGRESS.md)'s
"Start here next session" is the work order and is the only place that carries
one. This file carries the list, the definitions, the counts, and the argument
behind the current ordering.

[`RULES.md`](RULES.md) is how this repository is worked on.
[`../../AGENTS.md`](../../AGENTS.md) is what the project is.

 **The counts below are derived from the rows, never typed.** Closing one entry
moves several numbers at once, and a session that gets one wrong fails a gate
after the work is done and the message is written.

```bash
python3 scripts/check-todo.py --write     # re-derive the counts from the rows
```

```bash
python3 scripts/check-todo.py             # assert they agree; runs in CI
```

---

## Priority

- **P0** breaks correctness, loses data, or takes the process down.
- **P1** a documented capability does not work, or a flag does nothing.
- **P2** worth doing; nothing is wrong without it.
- **P3** worth recording so it is not rediscovered.

## Effort

S is under a day. M is a few days. L is a week. XL is longer, and  is almost
always two entries pretending to be one.

###  L-equivalents, so "how much did this session do" is countable

A session's target is stated in **L-equivalents**, and the scale is fixed here so
it is arithmetic rather than judgement:

| effort | L-equivalents |
| --- | --- |
| S | **0.25** |
| M | **0.5** |
| L | **1.0** |
| XL | 2.0  and it should have been two entries |

 **A `partial` entry counts only for what it actually closed**, and the entry
says which half. Moving something to `partial` and claiming its full weight is
the fabricated-progress failure this project is built against.

 **The whole remaining backlog is 0 L-equivalents** (nothing open), plus
whatever remains of `T-001`, which is `partial` and whose remainder is
editorial.  **Do not retype that figure**: `python3 scripts/check-todo.py`
derives it from the rows and fails when it disagrees, because it is the
denominator a session's target is set against and a wrong one silently rescales
the next session's plan. It was typed wrong once, on 2026-09-02, in this file.

## Status

`open`, `partial`, `blocked`, `done`.  There is no `wontfix` and no
`deferred`: a blocked entry stays open with the blocker named and what would
unblock it.

---

## The ordering, and the argument behind it

 **The ordering is derived, so it can be re-derived rather than re-argued.**
Written down here; when the argument changes, rewrite it and say so in
`PROGRESS.md`.

 **This section has now been rewritten three times, and each rewrite is a
record of what the project's weakest point was at the time.** Keeping the
history is the point: the argument is derived, so a reader can see it move.

| written | the argument | why it stopped applying |
| --- | --- | --- |
| 2026-09-01 | *evidence integrity first - everything downstream is a published dataset*, so `T-012` and `T-011` led | it paid: running those two checks for the first time found **three false claims in published documents**. Both closed. |
| 2026-09-02 | *the weak thing is coverage* - three suites had never run and two of eight allocators had never been measured |  **every suite in the matrix has now run at least once.** `profiles`, `distros`, `toolchain-control` and `preload` all closed, most of them on two machines. |
| 2026-09-02, amended |  **tier 0: [`T-014`](instrument.md)** - *a defect in the path that PUBLISHES evidence outranks the evidence* |  **closed.** `bench.yml`'s `roll` job has since committed three windows. That is why this section needed rewriting. |

 **The general principle from the amended tier is the part worth keeping**, and
this session instanced it a fourth time: *a defect in the instrument outranks
the thing the instrument was pointed at.* Three of this project's refusals have
now turned out to be the search rather than the allocator - tcmalloc's `find`
not following the `bazel-bin` symlink, its TLS failure reported as a build
failure, and mesh's artefact sitting in a directory nothing looked in.

**What is weak now is neither the evidence nor the coverage: it is that the
output is only usable by this project.** Everything below follows from that.

 **Two things make that concrete**, and both were raised from outside the
backlog rather than derived from it, which is itself worth recording - the
backlog had **no open entries at all** when they arrived:

- a reader meeting `1.138×` in a table or a bar in a chart was never told which
  direction was good. The charts said "lower is faster" in a subtitle; the
  tables said nothing; the size chart said nothing at all; and two of the
  report's own tables are read the **other** way round. [`T-015`](instrument.md).
- there was no path from "this benchmark says X" to "here is how I do it on
  Debian". Every mechanism was implemented, measured and documented **as this
  project's own build pipeline**, which is not a form anybody else can use.
  [`T-016`](mechanisms.md).

0.  **[`T-016`](mechanisms.md) and [`T-015`](instrument.md) first, together.**
   They are the same argument twice: a measurement nobody can read and a
   technique nobody can apply are both work that stops at this repository's
   edge.  And they check each other - writing the examples is what surfaced
   that the *direction of goodness* was missing from the report, because a
   how-to has to state it in the first paragraph.

1. **Then [`T-003`](mechanisms.md)'s remaining half.** It is down to **one
   allocator**: mesh produced its first number on 2026-09-03 and Google
   tcmalloc has still never produced one.  Its two refusals are now of
   different kinds and only one is this project's - musl is genuinely
   unsupported upstream, and the glibc route needs a runner without a
   TLS-inspecting proxy to execute a recipe that has been written and cannot be
   run here.

2. **[`T-001`](measurement.md) sits deliberately out of numeric order.** It is
   the project's central question and it is **P1**, but its remaining half is
   *editorial* - what the README says instead of a per-machine ordering - and it
   was ruled by default in [`PROGRESS.md`](PROGRESS.md).  Its evidence base
   has doubled twice: four rolling windows now refuse an ordering, and the
   `preload` window refuses one in both of its groups.

 **What the order is not.** It is not strict priority order, and it is not a
dependency graph pretending everything is sequential. Any of these could be done
today by anyone with a container runtime. The argument is about **leverage** -
and note that leverage has moved three times, which is why this section is
derived rather than inherited.

---

## Counts

**28 items. 0 open, 0 partial, 0 blocked, 28 done.**

| priority | open | partial | blocked | done | total |
| --- | --- | --- | --- | --- | --- |
| P0 | 0 | 0 | 0 | 0 | 0 |
| P1 | 0 | 0 | 0 | 17 | 17 |
| P2 | 0 | 0 | 0 | 9 | 9 |
| P3 | 0 | 0 | 0 | 2 | 2 |
| **All** | 0 | 0 | 0 | 28 | 28 |

---

## Entries

| ID | Priority | Category | Status | Item |
| --- | --- | --- | --- | --- |
| [T-001](measurement.md#t-001-decide-what-the-project-claims-now-that-the-ranking-does-not-transfer) | P1 | measurement | done | Decide what the project claims, now that the ranking does not transfer |
| [T-002](platform.md#t-002-decide-what-core-does-on-aarch64) | P1 | platform | done | Decide what `core` does on aarch64 |
| [T-003](mechanisms.md#t-003-implement-modepreload-in-the-allocator-recipes) | P1 | mechanisms | done | Implement `MODE=preload` in the allocator recipes |
| [T-004](mechanisms.md#t-004-fix-rpmallocs-override-mode-build) | P1 | mechanisms | done | Fix rpmalloc's override-mode build |
| [T-005](mechanisms.md#t-005-make-libc-surgery-work-beyond-mimalloc) | P2 | mechanisms | done | Make `libc-surgery` work beyond mimalloc |
| [T-006](measurement.md#t-006-run-the-profiles-suite-on-x86_64) | P2 | measurement | done | Run the `profiles` suite on x86_64 |
| [T-007](measurement.md#t-007-run-the-distros-suite-on-x86_64) | P2 | measurement | done | Run the `distros` suite on x86_64 |
| [T-008](measurement.md#t-008-run-the-toolchain-control-suite) | P2 | measurement | done | Run the `toolchain-control` suite |
| [T-009](mechanisms.md#t-009-exercise-hardened_mallocs-light-variant) | P3 | mechanisms | done | Exercise hardened_malloc's `light` variant |
| [T-010](instrument.md#t-010-write-experiments40--and-60-) | P3 | instrument | done | Write `experiments/40-` and `60-` |
| [T-011](instrument.md#t-011-publish-the-build-log-with-the-failure-it-documents) | P2 | instrument | done | Publish the build log with the failure it documents |
| [T-012](instrument.md#t-012-a-published-snapshot-must-carry-its-own-conditions) | P2 | instrument | done | A published snapshot must carry its own conditions |
| [T-013](mechanisms.md#t-013-libc-surgery-cannot-carry-a-c-allocator-into-libca) | P2 | mechanisms | done | `libc-surgery` cannot carry a C++ allocator into `libc.a` |
| [T-014](instrument.md#t-014-benchymls-rolling-window-commit-has-never-once-run) | P1 | instrument | done | `bench.yml`'s rolling-window commit has never once run |
| [T-015](instrument.md#t-015-every-human-facing-number-must-say-which-direction-is-good) | P1 | instrument | done | Every human-facing number must say which direction is good |
| [T-016](mechanisms.md#t-016-a-worked-path-from-this-benchmark-says-x-to-here-is-how-i-do-it) | P1 | mechanisms | done | A worked path from "this benchmark says X" to "here is how I do it" |
| [T-017](measurement.md#t-017-musl-meant-alpine-and-glibc-meant-debian) | P1 | measurement | done | "musl" meant Alpine and "glibc" meant Debian |
| [T-018](mechanisms.md#t-018-the-surgery-is-not-a-musl-technique-and-one-of-its-guards-could-not-fail) | P1 | mechanisms | done | The surgery is not a musl technique, and one of its guards could not fail |
| [T-019](mechanisms.md#t-019-the-production-surgery-asked-about-four-names-it-had-written-down) | P1 | mechanisms | done | The production surgery asked about four names it had written down |
| [T-020](instrument.md#t-020-gatesh---strict-could-not-see-a-skip-one-level-down) | P1 | instrument | done | `gate.sh --strict` could not see a skip one level down |
| [T-021](instrument.md#t-021-a-published-dataset-that-reaches-no-rolling-window) | P1 | instrument | done | A published dataset that reaches no rolling window |
| [T-022](instrument.md#t-022-the-aggregator-merged-two-allocators-into-one-row) | P1 | instrument | done | The aggregator merged two allocators into one row |
| [T-023](instrument.md#t-023-nothing-checks-a-count-written-in-prose) | P1 | instrument | done | Nothing checks a count written in prose |
| [T-024](instrument.md#t-024-a-mute-diagnostic-reported-a-tool-failure-as-an-allocator-defect) | P1 | instrument | done | A mute diagnostic reported a tool failure as an allocator defect |
| [T-025](measurement.md#t-025-which-property-of-the-machine-decides-the-ordering) | P2 | measurement | done | Which property of the machine decides the ordering |
| [T-026](instrument.md#t-026-the-readme-is-written-for-this-project-not-for-a-reader) | P1 | instrument | done | The README is written for this project, not for a reader |
| [T-027](instrument.md#t-027-the-trial-and-error-narrative-belongs-in-docshistory-not-in-the-code) | P2 | instrument | done | The trial-and-error narrative belongs in docs/history/, not in the code |
| [T-028](instrument.md#t-028-every-recipe-picked-its-shared-object-by-name-and-one-shipped-a-text-file) | P1 | instrument | done | Every recipe picked its shared object by name, and one shipped a text file |
