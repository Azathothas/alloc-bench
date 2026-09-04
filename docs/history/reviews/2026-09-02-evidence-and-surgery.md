# Deep review: the evidence checks, the surgery, and the aarch64 rule, 2026-09-02

Three passes, three **different** questions, per
[`../../methodology/reviews.md`](../../methodology/reviews.md). Each names what
it looked at that the others did not, and - for a pass that found nothing -
what would have had to be true for it to fire.

**Scope.** This session's change: `scripts/check-snapshots.py`,
`scripts/report/extract-evidence.py`, `alloc-runner ar-unresolved` and its
`ar::unresolved`, the alias synthesis in `scripts/build/libc-surgery.sh`, the
identity oracle's `any_prefix` and its new override-mode evidence, the
`aarch64`/musl rule and `profiles_by_arch` in the planner,
`allocators/rpmalloc/build.sh`, `experiments/70-aarch64-static-pie.sh`, and the
documents that describe any of them.

---

## Pass 1 - the door sweep

**"What other caller reaches this, and is the guard on every path?"**

 **What this pass looked at that the others did not:** the *callers*. Not
whether a guard can fail (pass 2) or whether a published sentence is true (pass
3), but whether every path into the same action passes through the same check.

Enumerated the affordances added, then grepped for the callers not enumerated:

```sh
grep -rn 'SIGNATURES\|detect(\|detect_libc_allocator\|has_symbol' crates/ --include=*.rs
grep -rn 'profiles_by_arch' crates/ benchmarks/
grep -rn 'check-snapshots\|extract-evidence\|libc-surgery.sh\|ar-unresolved' \
  --include='*.sh' --include='*.yml' --include='*.md' --include='*.rs' .
find results/rolling -name 'rankings.json'
```

### Findings

| # | finding | fixed |
| --- | --- | --- |
| 1.1 |  **`detect_libc_allocator` ignored `any_prefix`.** The field was added for `detect` and the sibling function was left reading `any_of` alone - a struct field one of its two consumers silently drops. Both `LIBC_ALLOCATOR_SIGNATURES` entries carry an empty `any_prefix` today, so nothing was wrong; but this path **is the negative control**, and a later session adding a mangled-namespace prefix to the musl or glibc signature would have got a control that never fires. A replacement build could then pass with the displaced allocator still in it - the exact failure `docs/AGENTS.md` §2.2 exists to prevent. | `any_prefix` honoured on both paths, and pass 2 proved the branch is live |
| 1.2 |  **`check-snapshots.py` swept `results/published/` only, and the rolling window is full of snapshots.** Every `results/rolling/<w>/runs/<id>/` carries a `rankings.json` **and** a `run.json` - snapshots by the checker's own definition - and `bench.yml`'s `roll` job commits them to `main` weekly **with nobody watching**. That is the tree most in need of the check and the one it did not look at.  `aggregate.py --check` covers the CPU and the suite; it does not cover `git_commit`, `tool_versions`, `corpus_seed` or commit-reachability. | the walk now covers all of `results/`, minus the gitignored `results/local/`; 6 snapshots became **10** |
| 1.3 |  **A `profiles_by_arch` key naming an architecture the suite does not run was silently ignored.** `arm64` for `aarch64` would put `core` back to planning `static-pie-lto` on aarch64 - where every cell fails the identity gate - with no error anywhere. The key was added *to fix that state*. | the planner returns an error naming the key; guard-tested in pass 2 |
| 1.4 | `docs/ci.md` described the `configuration` job's checks as "those last two". Two new ones had been added to the job. | rewritten as four, each named with what it asserts and what it needs |
| 1.5 | `docs/history/todo/RULES.md` §3's tool table - *"reach for the purpose-built tool before the general one"* - did not list the three tools this session added, so the next session would reach for `grep` and `tail`. | three rows added |
| 1.6 | `docs/extending.md` §5 tells a contributor how to teach the oracle about a new allocator and named only the **prefixed** case. That is precisely the trap two allocators fell into today. | an  block on override-mode evidence, with the `nm` command and the `chacha_` near-miss |
| 1.7 | `docs/troubleshooting.md`'s `no symbol evidence` section attributed the failure to the archive missing from the link, which is now only one of two causes. | the second cause documented, **with the test that separates it from the first** - `libc_allocator_detected` non-empty means the cell is wrong, and no evidence may be added |

 **What this pass did not look at:** whether any of the checks can actually
refuse (pass 2), and whether the numbers now published are right (pass 3).

---

## Pass 2 - the guard mutation

**"Can each new guard actually fail, and does its name match what it checks?"**

 **What this pass looked at that the others did not:** the guards' own
behaviour under a planted defect. Pass 1 asked whether a guard is on every path;
this one asks whether it does anything when it is.

 Every exit code below was read from the process that produced it, unpiped.

### Mutations planted, and what refused

| what was mutated | result |
| --- | --- |
| `check-snapshots.py`: `is_placeholder` always returns `False` | selftest **6 FAIL** |
| `check-snapshots.py`: the recovery route needs the sha **or** `git fetch`, not both | selftest **2 FAIL** |
| `check-snapshots.py`: the walk stops at the top level | selftest **3 FAIL**, incl. `finds-a-NESTED-snapshot` |
| `extract-evidence.py`: classes ordered noise-first | selftest **2 FAIL** |
| `extract-evidence.py`: de-duplication removed | selftest **1 FAIL**, 111 near-duplicates published |
| `extract-evidence.py`: `--check` counts no problem when the pattern is absent | selftest **2 FAIL** |
| `extract-evidence.py`: the header drops the elision count | selftest **1 FAIL** |
| `benchmarks/matrix.toml`: `profiles_by_arch` key `arm64` | `alloc-bench plan --suite core` **exit 2**, naming the key |
| `ident.rs`: musl's negative control reachable **only** through `any_prefix` | `libc_allocator_detected = ['musl']` - the branch is live.  Before finding 1.1 this mutation would have reported `[]` |

### Findings

| # | finding | fixed |
| --- | --- | --- |
| 2.1 |  **A check in this session's own selftest was satisfied by its own header.** `collision-outranks-the-noise` was written as `body.index("multiple definition") < body.index("__popcountdi2")` and **passed** under the mutation that reordered the classes - because the `# classes:` accounting line names both classes above everything. A check whose name claims more than it checks is the shape this lens names, and only the mutation showed it. | now tested against the payload, and it fails under that mutation |
| 2.2 |  **The first evidence budget dropped a whole class.** At `--budget 40` on run D's real log the extractor published 31 `undefined reference` lines and **all three** `error:` lines were cut - a class the reader needs, lost to one they already had. Found by reading the published extract, not by the selftest, which had only two classes. | per-class floor of three lines, plus `every-matched-class-survives-a-tight-budget` |
| 2.3 | `alloc-runner selftest` printed a **literal `9`** as its check count while running nine checks - a typed count, in the project whose record checker exists so counts are never typed. The next check added would have made it a lie. | derived from the checks actually run; it now prints 13, with a skip count |
| 2.4 |  The `ar-unresolved` selftest needs a C compiler to build real relocatable objects. Where there is none it is reported as **SKIPPED**, not passed. | a `SKIP` line and a skipped count in the summary |

### Every new CLI path, exit codes read unpiped

| invocation | exit |
| --- | --- |
| `ar-unresolved` with no `--archive` / no `--symbols` / empty `--symbols` | 2, 2, 2 |
| `ar-unresolved --archive /nope` / `--archive README.md` | 2, 2 |
| `check-snapshots.py --help`, `extract-evidence.py --help` | 0, and **neither does any work** - `docs/AGENTS.md` §12 item 14 |
| `extract-evidence.py` with no arguments / `--check` without `--expect` / `--run` without `--out` / `--budget 0` | 2, 2, 2, 2 |

 **What this pass did not look at:** whether the *published sentences* about
these guards are true. A guard that refuses correctly can still be described
wrongly.

---

## Pass 3 - the claim audit

**"Which sentence about to be published is not backed by an artefact I can point
at?"**

 **What this pass looked at that the others did not:** the numbers and the
attributions, re-derived from `run.json`, `rankings.json` and the build logs
rather than from the prose that quotes them.

### Findings

| # | finding | fixed |
| --- | --- | --- |
| 3.1 |  **`mechanisms` run C was published as measured at `194ed63`.** Its own `run.json` records `e24709ba1f9bba9a40de5d38e55b186df17d83e7`, and its 16 cells carry image digest `sha256:a0631865…` against run B's `sha256:6989b3c4…` - a different image, so not even a reuse of `194ed63`'s. Found by `check-snapshots.py` on its first run. | corrected in the snapshot README and `docs/AGENTS.md` §11.2; the withdrawal is in [`../README.md`](../README.md) |
| 3.2 |  **`docs/AGENTS.md` said run C "does not confirm the nine" collision symbols.** Run D re-measured the cell: the log carries **9** `multiple definition` lines naming exactly the same nine. Run C reproduced it; run C's *extract* lost it. | §5.1 rewritten with the measured table |
| 3.3 |  **A number went into a document unmeasured, in this session.** The run-D README and `docs/AGENTS.md` both stated the full log holds **145** `undefined reference` lines. `grep -c` says **210**. Nothing produced the 145; it was written from nothing. | corrected in both;  recorded here because it is the exact failure this project's §15 forbids, committed while writing about evidence integrity |
| 3.4 |  **`T-004`'s premise was a misread tail.** It attributed rpmalloc's build failure to the C++ operator aliases. Recompiled with the recipe's own flags: `malloc.c` alone gives **74 errors**, the first `unknown type name 'size_t'`; the alias errors are the tail that survived truncation. `rpmalloc.c` ends with `#include "malloc.c"`. | the entry carries the correction and the three-row measurement |
| 3.5 |  **The recorded reason for the aarch64 limitation was wrong.** It said `rust-lld` rejects `-static-pie`, it being a GCC driver flag. Both musl targets carry `linker-flavor: gnu-cc` and the aarch64 link is driven by `cc`; the difference is `static-position-independent-executables`, true for x86_64 and absent for aarch64. | corrected in `docs/AGENTS.md`, `docs/static-linking.md` and the entry; `experiments/70-` is the re-runnable measurement |
| 3.6 |  **Run D weakens a headline this project likes.** The surgery beat the shim a fourth time, but by **4.82%** against that cell's own **6.4%** MAD - inside the noise, which §9's own rule reports as no result. | `docs/AGENTS.md` §11.2, `docs/results.md`, `README.md` and the snapshot README all now say the direction held four times and that run D cannot establish it alone |
| 3.7 |  **`docs/AGENTS.md` §5.1's table is about to be superseded and says so.** Its  rows for jemalloc, snmalloc, hardened_malloc and rpmalloc describe the **pre-2026-09-02** state. | a  banner above the table naming the date and the entry, until the re-measurement is published |

### Re-derived and found correct, so nobody re-checks

- every figure in the four-run mechanism table - `0.4435 / 0.5014`,
  `0.4603 / 0.6056`, `0.5230 / 0.5966`, `0.6439 / 0.6749` - read from each run's
  `rankings.json`, and the four margins **13.05 / 31.56 / 14.08 / 4.82 %**
  recomputed as `shim ÷ surgery − 1`;
- run D's log accounting: **68 719 bytes, 414 lines, 9** `multiple definition`,
  **210** `undefined reference`; `tail -n 80` holds **0** and **47**;
- the collision-symbol counts that explain both mechanism columns at once:
  mimalloc **9**, rpmalloc **5**, hardened_malloc **5**, the difference being
  exactly the `__libc_*` aliases (plus `strdup`);
- `plan --suite all` moving **122 planned / 24 unsupported → 102 / 44**, and the
  per-suite aarch64 split.

 **What this pass did not look at:** the `core` and `profiles` datasets, which
this session did not touch, and the numbers in `results/rolling/`, which
`aggregate.py --check` re-derives on every gate run.

---

## What would have had to be true for a pass to find nothing

No pass came back empty, so the question is which finding each *only* its own
lens could have produced:

- **1.1 and 1.2 are pass-1-only.** Both guards work perfectly on the path they
  were written for; nothing about running them reveals the path they are not on.
  A mutation of `detect` passes. A mutation of `check-snapshots.py` passes. Only
  enumerating callers finds them.
- **2.1 is pass-2-only.** The check was green, its name was right, and its
  subject was correct. Only planting the defect it claimed to catch showed it was
  answering with the file's own header.
- **3.3 is pass-3-only.** The sentence was fluent, in the right place, in a
  document about evidence integrity, and no check in this repository can tell a
  wrong number from a right one.
