# Deep review: the gate, the windows, and four checks that could not tell two states apart, 2026-09-03

Three passes, three **different** questions, per
[`../../methodology/reviews.md`](../../methodology/reviews.md). Each names what
it looked at that the others did not, and - for anything it did not find - what
would have had to be true for it to fire.

**Scope.** This session's change: `scripts/gate.sh`'s skip accounting and
`--strict` pass-through; `scripts/check-snapshots.py`'s new rule 5 and its
`windows()` reader; `scripts/report/aggregate.py`'s candidate key; the new
`scripts/check-counts.py`; `scripts/report/combine.py`'s per-architecture key;
`crates/alloc-bench/src/rank.rs`'s verdict and per-libc roll-up;
`allocators/lib.sh`'s `finish` and `finish_so`; `experiments/140-` and `150-`;
the nine datasets folded (or argued out of) `results/rolling/`; and the README,
`docs/AGENTS.md` and the record published alongside them.

---

## Pass 1 - the door sweep

**"What other door reaches this code, and does every path say the same thing?"**

 **What this pass looked at that the others did not:** the *enumeration*. Not
whether a guard can fail (pass 2), nor whether a published sentence is true
(pass 3), but whether the set of places a defect lives is the set I believed it
was after fixing the one that announced itself.

 **It found three more instances of two defects, and in each case the instance
that announced itself was the smaller one.**

### 1. `finish_so` was fixed; `finish` is the bigger path

`finish_so` was corrected because a real artefact tripped it - tcmalloc's first
`.so`. The sweep asked which other function reads a symbol table the same way:

```
$ grep -rn '2>/dev/null[[:space:]]*|[[:space:]]*grep -q' allocators/ scripts/
allocators/lib.sh:86   …nm --defined-only "$ARCHIVE"…   ← finish
allocators/lib.sh:102  …nm --defined-only "$ARCHIVE"…   ← finish, prefixed
allocators/lib.sh:107  …nm --defined-only "$ARCHIVE"…   ← finish, override
```

 **Four places, in the function every non-preload cell takes** - 103 of the
131 planned cells, against `preload`'s 28. Nothing had tripped it, which is
precisely why a sweep was needed rather than a bug report.

 **And one of the four failed OPEN.** The other three refuse when `nm` breaks:
a symbol reads as absent, the build stops. The `MODE=prefixed` assertion asks
the opposite question - *does this archive define `malloc`?* - so `grep` finding
nothing is the answer that **lets the build through**. A broken `nm` would have
passed a prefixed archive that does define `malloc`, and `rust-global` and
`libc-surgery` would then have been the same experiment published as two. That
is `docs/AGENTS.md` §2.2's failure, reached from inside the build rather than
from the report, and it would have produced numbers rather than an error.

### 2. The variant-blind key was in three places, not one

[`T-022`](../todo/instrument.md) fixed `aggregate.py`. The sweep asked who
else keys a candidate:

| where | what it did | why it is worse than the one that was found |
| --- | --- | --- |
| `scripts/report/combine.py:135` | `(allocator, integration)` | the merge is **across architectures** - one arch's `light` in the same row as another's `default` |
| `rank.rs`, the verdict | printed `first.allocator` | *"hardened_malloc is 37.2% faster than the next row"*, where the next row **is** hardened_malloc |
| `rank.rs`, the per-libc roll-up | `(allocator, integration)` |  **this is the code the README's "jemalloc on musl, nothing on glibc" headline is computed from** |

 **The instructive part is that `Row` already carried `variant`, with a doc
comment saying "without this the table cannot be read".** The *table* used it.
The verdict and the roll-up did not. A partial fix that reads as a complete one
is the shape this project keeps finding - and the first draft of `T-022` said
in as many words that `rank.rs` was untouched *because* it carried the field.
That sentence was written from memory instead of from a grep.

### 3. A marker inside a fenced code block

`check-counts.py` reads a claim as the number before a `<!--n:…-->` marker.
`docs/history/todo/instrument.md` **documents the syntax** inside a ```` ```markdown ````
fence, and that example was being read as a live claim.  It passed only because
the number in the example happened to be current; `--write` would eventually
have silently edited the documentation of the feature. Fenced blocks are now
blanked (position-preserving, so `--write` still splices correctly).

### What this pass did NOT find, and what would have had to be true

- **No fourth caller of `finish`/`finish_so`.** Every recipe under
  `allocators/*/build.sh` calls one or both and nothing else does; a fifth would
  have shown in the grep above.
- **No consumer of `aggregate.json`'s rows outside the three fixed files.**
  `grep -rln 'aggregate.json'` returns `aggregate.py`, `check-snapshots.py` and
  `experiments/80-`; the last reads only paths. For this to be wrong, a consumer
  would have to reach the rows without naming the file - through the window
  directory, say - and none does.
- **The examples layer has the same `2>/dev/null | grep -q` shape** in
  `examples/verify.sh` and five example scripts.  **Deliberately left**, and
  this is the one place the sweep chose not to act: the examples are ruled to
  use only the distribution's own tools, each installs `binutils` explicitly in
  the image it runs in, and their transcripts are committed and re-validated by
  `sh examples/run.sh`.  It is still the same class of defect, and it is
  recorded here rather than fixed so that a later session finds a decision
  rather than an oversight.

---

## Pass 2 - the guard mutation

**"Can each guard I added actually fail, and has it been seen to?"**

 **What this pass looked at that the others did not:** the *exit codes*, one
guard at a time, against a planted defect. Pass 1 asks where a guard is missing;
this asks whether the ones present are theatre.

Sixteen guards were added or changed. Fifteen had a demonstrated firing:

| guard | how it was seen to refuse |
| --- | --- |
| gate sees a checker's internal skip | `experiments/140-`, and `0 skipped` → `2 skipped` on the same tree from the same command |
| gate passes `--strict` down | `experiments/140-` half A: exit 1, refusal **naming both checkers** |
| rule 5: never folded | selftest, plus 9 real findings on the tree |
| rule 5: README route | selftest - a README that does *not* name the run is still refused |
| rule 5: eviction allowance | three cases - not-full cannot excuse; full excuses an *older* one; full does **not** excuse a newer one |
| rule 5: prefix-ambiguous run id | selftest |
| aggregate variant key | **mutation test**: variant removed from the key → **7 of 8** new cases fail, reproducing `positions=[[1,3,1,3],[2,2]]` and `movers=['h']` on identical runs |
| `check-counts`: every rule | 18 planted cases, and 7 real findings on its first run |
| `finish` / `finish_so` | `experiments/150-`, four states each, plus the fail-open case |
| `combine.py`, `rank.rs` | regenerated against the real `hardening-variants` dataset |

 **The sixteenth was `check-counts.py --strict`, and it was worse than
undemonstrated.** It was implemented in `main()` by **re-running every source a
second time** after `check()` had already read them. Two objections, and the
second is the real one:

1. it doubles what CI pays;
2.  **the verdict is about a different reading than the one printed.** The
   operator sees the skips from read #1 and the exit code from read #2, and
   nothing makes them the same - which is [`RULES.md`](../todo/RULES.md)
   §4's *read the result from the process that produced it*, in a checker
   written to enforce a sibling rule.

Fixed by passing `strict` into `check()`, as `check-docs.py` and
`check-snapshots.py` already did, and given two cases: the skip becomes a
failure, and - the negative control - `--strict` is harmless once the unreadable
source is gone.

### What this pass did NOT find, and what would have had to be true

- **No guard that passes because another path satisfies it.** The one candidate
  was `check-snapshots`'s `sweeps-the-rolling-window-too`, which expects a
  refusal - and the `good` fixture had been left **corrupt** by an earlier case
  (`{not json`, written and never restored), so *every* case after it saw a tree
  that already failed.  A planted defect that did nothing would still have
  read as "refused". Fixed, with a case asserting the tree is clean again.
- **No test whose name claims more than it checks**, after two were renamed:
  `naming-a-LONGER-run-id-does-not-account-for-its-prefix` became
  `a-run-id-that-prefixes-another-cannot-be-accounted-for-by-prose`, because the
  check that fires is the ambiguity detector, not a smarter matcher.

---

## Pass 3 - the claim audit

**"Which sentence I am about to publish is not backed by an artefact I can point
at?"**

 **What this pass looked at that the others did not:** the *prose*, recomputed
against the JSON rather than re-read. Every ratio in the README's §3 and §3.1,
every count in the entries, and every number in `docs/AGENTS.md` that this
session moved.

 **It cut two claims and corrected six numbers.**

**1. A wrong denominator, in my own comment.** `allocators/lib.sh` and
`T-024` said `finish` covers *"some 115 of the matrix's 131 planned cells
against preload's 16"*. The 16 is the `preload` **suite on x86_64**; the matrix
also has aarch64 and other suites. Recounted from `plan --suite all`:

```
planned total          : 131
  integration=preload  : 28    -> finish_so
  everything else      : 103   -> finish
```

 The *argument* survives - `finish` is still much the bigger path - but the
figure was a suite count wearing a matrix count's clothes.

**2. An overclaim about tcmalloc.** The draft said this was *"the third of four
refusals that is the instrument rather than the allocator"*.  **Not
established.** Two of the four were certainly the instrument (a TLS failure
reported as a build failure; `find -P` not following `bazel-bin`) and one is
certainly upstream (musl). **The fourth is undecided** - and it is undecided
*because the diagnostic destroyed the distinction*, which is the entry's own
finding. Claiming it as instrument would have been the same error one level up.

**3. Six stale counts, found by the tool this session wrote**, and one of them
had nothing to do with this session: `docs/AGENTS.md` §13 said the matrix
expands to **146 cells (122 planned, 24 unsupported)** where it expands to
**176 / 131 / 45** - wrong by 30 cells and 21 unsupported configurations, in the
table a reader consults to find out what the project covers.

**4. Two figures I typed into the README's memory table were wrong**, caught by
recomputing rather than re-reading: mimalloc's glibc range is 3.07–3.43×, not
3.07–3.25×, and jemalloc's is 1.25–4.75×, not 1.25–4.74×.

**5. Every surviving README claim was recomputed from `aggregate.json`:**

```
rank_movers      : ['jemalloc','rpmalloc','mimalloc','snmalloc','mesh']   (5)
control_crossers : ['mimalloc','snmalloc','mesh']
beat_every_run   : ['jemalloc','rpmalloc']          (alpine)
beat_every_run   : []                               (debian)
mesh musl rel    : min=0.636  max=1.232
```

which is exactly what §3 now says.

### What this pass did NOT find, and what would have had to be true

- **No fabricated number.** Every figure published traces to a committed
  `rankings.json`, `aggregate.json` or transcript. For this to be wrong, a
  number would have to have been carried between documents without being
  recomputed - which is what caught §11.2's `12%` and README §3's mismatched
  pairing on previous sessions, and is why every figure here was re-derived from
  JSON rather than copied from prose.
- **No claim that a dataset was published when it was not.** The one dataset
  this session produced locally - the two-cell `preload` verification - is
  **deliberately not published**: `alloc-bench` warned that the checkout was
  dirty, so it is recorded as a gate observation and nothing more.  A session
  that published it would have hit `check-snapshots.py`'s `git_dirty` rule, and
  the rule is right.
