# Deep review: coverage, the variant dimension, and the record, 2026-09-02

The session's **second** set of three passes, taken at its close. The first set
is [`2026-09-02-evidence-and-surgery.md`](2026-09-02-evidence-and-surgery.md)
and swept a different change; nothing here re-reads that one.

Three passes, three **different** questions, per
[`../../methodology/reviews.md`](../../methodology/reviews.md). Each names what
it looked at that the others did not, and - for a pass that found nothing -
what would have had to be true for it to fire.

**Scope.** `T-008`, `T-009` and `T-010`: the `toolchain-control` and
`hardening-variants` datasets and their READMEs, the variant dimension
(`Suite.variants`, `Cell::slug_with_variant`, `applicable_variants`, the
`HM_VARIANT` plumbing, the rank row and report label), `git_dirty` /
`git_untracked` and the `check-snapshots.py` rule that keys on them, the
`cc`/`alloc_cc` split in `build-ripgrep.sh`, the `/etc/ssl` fix in three
Dockerfiles, `experiments/40-` and `60-`, and every document changed alongside.

---

## Pass 1 - the arithmetic sweep

**"Is every number I published today actually in the dataset it cites?"**

 **What this pass looked at that the others did not:** the *values*. Not
whether a check can fail (pass 2), not whether two documents agree with each
other (pass 3), but whether each printed figure survives being recomputed from
`rankings.json` and `run.json`.

 **It exists because this session already failed it once.** Earlier today a
document claimed "145 undefined reference lines" and `grep -c` said **210** -
a number written from nothing, in a passage about evidence integrity. That
withdrawal is recorded in [`../README.md`](../README.md).

Every ratio, MAD, spread, byte count and RSS figure in
`results/published/2026-09-02-toolchain-control-x86_64/README.md`,
`…-hardening-variants-x86_64/README.md`, `…-run-b/README.md`, `docs/results.md`,
`README.md`, `docs/AGENTS.md` §13 and the three closed entries was recomputed
directly from the committed JSON.

| claim as published | recomputed | agrees |
| --- | --- | --- |
| mimalloc `rel` 0.649 / 1.027 / 0.973 | 0.6485 / 1.0265 / 0.9727 |  |
| its MADs 7.8/17.2, 3.4/5.2, 4.4/3.3 % | same to one decimal |  |
| control time spread **1.807×** | 1.807 |  |
| mimalloc time spread **1.145×** | 1.145 |  |
| `light` faster than `default` **48.7% / 50.9%** | 48.74 / 50.91 |  |
| `light` / `default` peak RSS **1.178× / 2.875×**, both runs | identical to three decimals |  |
| binary size **24 bytes** apart | 8 565 368 − 8 565 344 = 24 |  |
| `default` vs control 1.084× then 1.003× | 1.0842 / 1.0028 |  |

 **Found nothing.** For this pass to have fired, a figure would have had to be
typed from memory rather than derived - which is exactly what happened earlier
today, so the pass is not idle. What changed between the two occasions is
mechanical: every number above was produced by a script printing it out of the
JSON and pasted, rather than read off a screen and retyped.

 **What it does not cover:** whether the *dataset* is right. A wrong
measurement recorded faithfully passes this pass completely.

---

## Pass 2 - the adversarial-guard sweep

**"For each check I added today, what gets past it?"**

 **What this pass looked at that the others did not:** the *negative space* of
the new guards. Pass 1 asks whether a number is right; this asks what a check
would fail to notice, and answers by planting the thing rather than reasoning
about it.

### `git_dirty` - probed, in a scratch repository

| planted | `--untracked-files=no` porcelain | caught |
| --- | --- | --- |
| staged modification | `M  f.txt` |  |
| deleted tracked file | ` D f.txt` |  |
| ignored file only | *(empty)* |  correctly not dirty |
| untracked file only | *(empty)* |  **by design** - see below |

 **The untracked case is the one this pass changed.** The first version used a
plain `--porcelain`, and the first CI dataset came back `git_dirty: true` at a
commit nobody had touched: `bench.yml` writes `conditions.txt` into the
repository root before it measures. A flag that fires on every CI run is worse
than no flag, because the README note it demands becomes boilerplate. Split
into `git_dirty` (tracked) and `git_untracked` (a count, recorded not policed).

 **What still gets past it:** an untracked file that *does* change a build - a
stray header on an include path. `git_untracked` records the count so it is
visible, but nothing refuses on it, and that is a deliberate limit rather than
an oversight.

### `dirtiness_documented` - a word match, and knowingly so

Passes on any of `uncommitted`, `git_dirty`, `dirty tree`, `dirty checkout`,
`modified tree` appearing anywhere in the snapshot's prose.  **A README that
uses the word in an unrelated sentence passes.** The alternative - demanding a
fixed phrase - makes the check a house-style linter that is routed around by
rewording. Recorded in the code, not just here.

### The variant dimension - planted, three ways

| planted | result |
| --- | --- |
| `variants = ["default", "ligth"]` | `plan` exit **2**, naming the variant |
| `variants = ["light"]` alone, control present |  still yields **one `default` control** - the ratio has something to be taken against |
| the default variant's cell id | unchanged: `plan --suite all` 146 → **147**, +1 planned, unsupported still 44 |

### `experiments/60-` - three mutations of the document

Each planted in `docs/static-linking.md`'s own table, each caught with the right
message and exit 1: a false ASLR claim, a false ELF type, a false `PT_INTERP`.

### `experiments/40-` - the silent-success case

A recipe made to `exit 0` without producing `lib/liballocbench.a` was reported
` NO ARCHIVE`, exit 1.

 **And the first attempt at that mutation was a broken test, not a working
script.** `mimalloc/build.sh` has no `set -` line to insert after, and the
mutation script printed `mutated` unconditionally, so a no-op looked like a
pass. The second attempt asserts the mutation landed before running anything.
 **That is the finding of this pass**: a mutation test that never mutated is
indistinguishable from a check that works.

---

## Pass 3 - the cross-document sweep

**"Does anything published today contradict something this repository already
holds?"**

 **What this pass looked at that the others did not:** *other* documents and
*older* datasets. Pass 1 checks a number against its own dataset; this checks a
sentence against datasets it does not cite.

###  It found a false claim, written today, in a file published today

`results/published/2026-09-02-hardening-variants-x86_64/README.md` opened with

> the project reported hardened_malloc as the slowest allocator it had
> measured, **on every machine**

Checked against all four `core` datasets rather than against the sentence's own
run:

| dataset | slowest row | hardened_malloc |
| --- | --- | --- |
| `core` run A | hardened_malloc | 1.075×, **6 of 6** |
| `core` run B | **system** | 0.890×, 5 of 6 |
| `core` CI runner | hardened_malloc | 1.225×, 6 of 6 |
| `core` aarch64 | hardened_malloc | 1.106×, 6 of 6 |

 **Three of four, not four.** In run B the *control* is the slowest row.
Corrected in the snapshot README and in `docs/history/todo/mechanisms.md`'s T-009 entry,
which carried a looser version of the same sentence from before this session.

 **Note what produced the error**: the claim was inherited from the entry's own
Problem section and strengthened while being restated. Repeating a sentence is
where a hedge gets dropped.

### Also checked, and consistent

- `README.md`'s `core` table still says what the datasets say; the new glibc
  block does not contradict it, and the "What it does not say" list now names
  the musl-only scope explicitly.
- `benchmarks/matrix.toml`'s `toolchain-control` `why` no longer claims to
  remove "the compiler" - corrected to the allocator's compiler, with the three
  gcc versions that linked the three ripgreps as evidence.
- `docs/AGENTS.md`'s allocator table said **both** replacement mechanisms fail
  for hardened_malloc; `libc-surgery` has worked for it since run E. Corrected
  against that dataset's `rankings.json` (0.8855×), not against the prose.
- `docs/history/todo/measurement.md`'s T-007 no longer says the Debian and Arch images have
  never been built - T-008 built both.

 **What this pass does not cover:** a claim that is consistent everywhere and
wrong everywhere. Nothing here re-derives the older `core` datasets themselves.
