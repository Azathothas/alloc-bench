# Three review passes, 2026-09-03 - the wander experiment and the artefact selectors

 **Three different questions, not one sweep written up three times.**
[`../../methodology/reviews.md`](../../methodology/reviews.md). Each
pass below says what it swept **that the others did not**, and each found
something.

 **The previous session shipped one pass**, under a licence the operator granted
for that session only. This is the rule back in force.

---

## Pass 1 - the door sweep: *what other door reaches the code this session changed?*

**Swept, and only by this pass:** every caller and every sibling of the three
surfaces this session touched - the artefact selectors in the recipes, the
`host` block of `run.json`, and the `docs/history/` → `docs/history/` rename. Started
from `git grep` over the whole tree rather than from the list of files edited,
because the list written from memory has never been complete.

###  Finding 1.1 - the fix closed the `.so` selectors and left the `.a` ones

`T-028` fixed five recipes that picked a **shared object** with
`find … -name 'libfoo*.so*' | head -1`. The sweep then asked *what else is picked
that way*, and found four recipes picking the **archive** the same way:

```
allocators/jemalloc/build.sh:91   find "$B" -name 'libjemalloc*.a'   | head -1
allocators/mimalloc/build.sh:82   find "$B" -name 'libmimalloc*.a'   | head -1
allocators/snmalloc/build.sh:93   find "$B" -name 'libsnmallocshim*.a' | head -1
allocators/mesh/build.sh:81       find … -name 'libmesh*.a'          | head -1
```

 **And the archive is the path MOST cells take** - `rust-global`,
`libc-surgery` and `link-override` all consume `liballocbench.a`; only `preload`
consumes the shared object. This is the same asymmetry `T-024` recorded: the
defect that announces itself is in the smaller path.

**Fixed** by generalising the selector into `_pick_by_kind` and adding `ar_kind`
/ `pick_ar` beside `elf_kind` / `pick_elf_so`, so an archive is now identified by
its `!<arch>` magic. Case 6 of
[`../../../experiments/180-which-file-did-the-recipe-take.sh`](../../../experiments/180-which-file-did-the-recipe-take.sh)
covers it, including the refusal when nothing in the tree is an archive.

###  Checked and clean, by the same pass

- **`scripts/build/run-cell.sh`** - already takes one fixed name and says why.
  Not a third instance.
- **`host.env` consumers.** `scripts/report/aggregate.py` and
  `scripts/check-snapshots.py` read named keys out of `host`, never iterate it,
  so an added sub-object cannot break either. Verified by reading both.
- **The rename.** No `docs/history` reference survives in any `.yml`, `.py`,
  `.rs`, `.toml` or `.json`; the two left in Markdown are prose *about* the move.

---

## Pass 2 - the guard mutation: *can the guards added today actually fail?*

**Swept, and only by this pass:** the guards themselves, by planting the defect
each exists to catch and reading the exit code unpiped. Distinct from pass 1,
which asked who *calls* the code and never asked whether it can refuse.

| guard | defect planted | result |
| --- | --- | --- |
| `170-`'s conditions assertion | one run's `run.json` claims a different `cpu_model` |  **exit 1**, both machines named |
| the same | one run records `cpuset: "0-1"` |  **exit 1**, `cpusets seen: ['0-1', None]` |
| the same | one run's `run.json` deleted |  **exit 1**, "cannot establish that it ran on the same machine" |
| the same, **negative control** | unmutated datasets |  **exit 0**, "all 10 runs record ONE machine" |
| `pick_elf_so` | a tree holding only an `ET_REL` object and text files |  refuses, naming each file's kind |
| `pick_ar` | the only archive removed |  refuses |
| `envinfo`'s `unread` invariant | - | a unit test asserts every empty field carries a reason; `scaling_governor` is genuinely absent on this host and exercises it live |

###  Finding 2.1 - the mutation test overwrites the committed transcript

`experiments/170-` writes to a **fixed** path under `experiments/out/`, so
running it against mutated datasets replaced the real transcript with the
mutated one. Caught because the refusal text was read back out of the committed
file. **Restored by re-running against the real datasets**, and the negative
control above is that restoration.

 Recorded rather than fixed: making the output path depend on `TMPDIR` would
make a probe's own output location vary with the environment, which is worse.
The hazard belongs to anyone mutation-testing a probe in place.

---

## Pass 3 - the claim audit: *which sentence about to be published is not backed by an artefact?*

**Swept, and only by this pass:** every number in the rewritten README, the two
closed entries and `docs/AGENTS.md`, recomputed from the datasets rather than
copied from the previous wording. Distinct from passes 1 and 2, which never
looked at prose.

###  Finding 3.1 - the adjacent-gap figures were wrong, in three files

Published as *"the gaps are small - 1.7%, 2.7%, 4.0%, 5.8% between adjacent
candidates"* in `README.md`, `docs/history/todo/measurement.md` and `docs/AGENTS.md`.
Recomputed from the ten runs:

```
snmalloc(0.591) < rpmalloc(0.606) < jemalloc(0.631) < mimalloc(0.642) < hardened_malloc(0.945)
   2.7%              4.0%              1.7%              47.2%
```

 **There are THREE gaps between the four fast allocators, not four**, and
`5.8%` is `rpmalloc → mimalloc`, a pair with jemalloc between them - not
adjacent at all. It came from the *pairwise* table, where it is a correct entry,
and was read into a sentence about neighbours. Corrected in all three files, and
the 47.2% gap to hardened_malloc is now stated too, because it is the one gap
that IS decided every run and its absence made the sentence read as though
nothing was resolved.

###  Finding 3.2 - the between-run/within-run ratio compared a range to a MAD

Drafted as *"the between-run spread is 5.2×–19.5× each cell's own within-run
MAD"*. A range over N runs grows with N; a MAD does not. Recomputed MAD against
MAD: **0.20×–0.52×**, the opposite conclusion.  Withdrawn before publication,
the probe now computes both and prints the range only as context, and
`docs/history/todo/RULES.md` §4 records that its own factor did not reproduce while keeping
the caution.

###  Finding 3.3 - a "value outside the range" that cleared it by 0.02%

The control cross-reference counted a window value as outside this host's ten-run
range when it exceeded the maximum by `0.000149` - **0.02%** - on equal terms
with one that exceeded it by 12%. Now a value counts only if it clears the range
by more than that cell's own within-run MAD, which is §9's rule applied to the
gap, and the margin is printed either way.

###  Findings 3.4–3.7 - four stale or unsupported numbers

| claim | where | what it actually is |
| --- | --- | --- |
| *"Seven of eight allocators have numbers"* | `README.md` Status | **8 of 8**, and §4.1 of the same file said so a hundred lines above |
| *"reproduced on four machines"* | `README.md` Status | **5** distinct CPU models across 19 published datasets |
| *"13–42% faster"* on musl | `README.md` §1 | merged two allocators' samples and rounded the floor up. Per allocator: jemalloc **13.5–37.1%** over 9 cells, rpmalloc **12.7–42.0%** over 6 |
| *"the rename touches ~691 relative links"* | `docs/history/todo/instrument.md` T-027 | 691 is `check-docs.py`'s count of **every** relative link in the tree. The rename touches **28** inbound and **28** outbound |

 **None of these was fabricated** - each was true of something, and each was
attached to the wrong subject. That is the failure mode this lens is for.

---

## What the review owes the record

- **Files touched by the fixes above:** `allocators/lib.sh`,
  `allocators/{jemalloc,mimalloc,snmalloc,mesh}/build.sh`,
  `experiments/170-*.sh`, `experiments/180-*.sh`, `README.md`,
  `docs/history/todo/measurement.md`, `docs/history/todo/instrument.md`, `docs/history/todo/RULES.md`,
  `docs/AGENTS.md`.
- **Everything listed was fixed in this session.** Nothing is deferred.
- **The one thing recorded and not acted on** is finding 2.1, with its reason.
