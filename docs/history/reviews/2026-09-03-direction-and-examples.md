# Deep review: direction-of-goodness, the worked examples, and three refusals that were the instrument, 2026-09-03

Three passes, three **different** questions, per
[`../../methodology/reviews.md`](../../methodology/reviews.md). Each names what
it looked at that the others did not, and - for anything it did not find - what
would have had to be true for it to fire.

**Scope.** This session's change: `crates/alloc-bench/src/svg.rs` (rewritten)
and `report.rs`'s ranking, per-libc, ASLR and residency tables; `rank::by_libc`;
`scripts/report/aggregate.py` and `combine.py`; every recipe under
`allocators/` and `allocators/lib.sh`'s new `fortify_cflags`; three new images
(`ubuntu`, `wolfi`, `void`) and the `libc_for` / `dockerfile_for` / `base_image`
maps; `benchmarks/matrix.toml`'s `preload` and new `libc-contrast` suites; the
whole of `examples/`; `docs/replacing-the-allocator.md` and the README;
`experiments/100-mesh-artefacts.sh`; `bench.yml`'s cadence and window size; and
the datasets, windows and record published alongside them.

---

## Pass 1 - the door sweep

**"What other caller reaches this, and does every path say the same thing?"**

 **What this pass looked at that the others did not:** the *enumeration*. Not
whether a check can fail (pass 2), nor whether a published sentence is true
(pass 3), but whether the set of places a human meets a ratio is the set I
believed it was. The list written from memory was, as always, incomplete.

Swept by grep rather than recall: every caller of `relative_time_chart`,
`relative_rss_chart`, `size_chart`, `bar_chart`, `rel_phrase`,
`tie_with_control` and `direction_note`; every file mentioning `rel_time` or
`rel_rss`; and every place `.github/workflows/*.yml` renders a number into a job
summary.

###  Found: `docs/results.md` teaches a reader how to read the tables and never says which direction is good

The five *producers* were all found and fixed - `report.rs`, `svg.rs`,
`aggregate.py`, `combine.py`, and `rank.rs` (which produces no prose). The
workflows turned out to render nothing of their own: both `bench.yml` and
`ci.yml` `sed` sections straight out of `report.md`, so they inherit whatever it
says.  That is the good case - one place to fix.

But `docs/results.md` §3 is a **column glossary**, hand-written, and its `rel`
row read *"that time ÷ the control's, in the same group. 1.000 is the image's own
allocator."* - true, and silent on whether `1.138×` is the win. A reader is more
likely to meet that table than the generated one. Fixed: every row now carries a
`good direction` column, and a new §3.1 names the **two tables where higher is
better**, which is the case the whole entry exists for.

###  Found and deliberately not changed: `docs/AGENTS.md` §11's tables

They are hand-written prose, and they carry their direction in words already
("relative to musl's own allocator", "0.595×" with the ordering spelled out
underneath). Adding `↓` to a prose table would be cargo-culting the mechanism
into a place that does not have the failure.

### What would have had to be true for this pass to find nothing

That the only human-facing ratios were the generated ones. It nearly was: four
of the five producers are code. The fifth is a document, and documents are
exactly what a grep for a *function name* does not reach - which is why the
sweep was run twice, once over identifiers and once over the rendered strings
`rel`, `×` and `MAD`.

---

## Pass 2 - can each new guard fail?

**"Plant the defect, and read the exit code from the process that produced it."**

 **What this pass looked at that the others did not:** the *refusing*
direction. Pass 1 asks whether the check is reached; pass 3 asks whether its
verdict is true. This one asks the question those two both assume: given input
that is wrong, does the check say so, and does anything downstream notice?

This project has shipped two guards that could not fail - an `LD_PRELOAD`
residency control that skipped its own search when no library was set, so
`resident: 0` was true by construction; and, **this session**, one described
below.

###  Built: `examples/verify-selftest.sh`, 16 planted cases, all correct

>  **19 cases as of pass 4**, which added the three for `want_displaced`.

Every check in `examples/verify.sh` is handed an input that must make it fail
**and** one that must make it pass, and the assertion is on `VERIFY_FAIL` /
`VERIFY_PASS` - the counters `verify_summary` reads - not on the printed output.
A check that printed `` without recording it would let a failed example exit 0.

```
   want_elf: a dynamic binary called static       refused, as it must
   want_no_symbol: a symbol that IS defined       refused, as it must
   want_resident: a library nobody preloads       refused, as it must
   want_not_resident: libc, always mapped         refused, as it must
   want_run: a command killed by SIGSEGV          refused, as it must
   want_count: the wrong expected count           refused, as it must
   want_aslr: a PIE told to be fixed              refused, as it must
  …
16 case(s), 0 failures
```

 `want_not_resident` is given **libc**, which every process maps. That is the
case that catches a control which cannot fire, and it is the same input
`experiments/90-` uses for the same reason.

###  Found, the hard way: a guard that fired WRONGLY, and disabled what it guarded

`trust_extra_ca` asked *"is the proxy CA already in this trust store?"* by
grepping for the bundle's **first** base64 line. The bundle leads with a public
root every distribution already ships - so the answer was yes, it appended
nothing, and Alpine's `apk` then failed with **"no such package"**, which is what
a trust failure looks like there. An entire example run was lost to it.

 **This is the mirror image of the rule this project already has.** "A guard
that cannot fail is not a guard" covers the check that never fires. This is the
check that fires when it should not and silently disables the thing it protects.
Both are the same underlying error - *the guard was never tested against the
input that distinguishes its two answers.* Replaced with a marker file, and the
case is written into `T-016`.

###  Not planted: the recipe changes

`allocators/mesh/build.sh`, `rpmalloc` and `hardened_malloc` were exercised
positively - all three produced `ok` cells in a 16-cell run - and their refusing
direction is covered by `allocators/lib.sh`'s `finish_so`, which was not changed
and whose refusal is exercised by every recipe.  **`allocators/tcmalloc/build.sh`
was not exercised in either direction**, and that is stated in three places
rather than glossed: Bazel cannot run on this host at all.

### What would have had to be true for this pass to find nothing

That every check I wrote had already been given a wrong input. The Alpine
example gave two of them wrong inputs by accident - `want_elf` and `want_aslr`
both fired for real when `-static` turned out to produce a static-PIE - which is
how I knew the harness worked at all before the selftest existed. The other
eight had never refused anything.

---

## Pass 3 - is every published sentence true?

**"Take each claim to the artefact it rests on, and read the artefact."**

 **What this pass looked at that the others did not:** the *numbers and the
prose beside them*, in the documents and datasets published this session, against
the JSON and the transcripts they were derived from. Pass 1 and pass 2 are about
code; this one is about whether the sentences are load-bearing or decorative.

###  Found: "every candidate loses to glibc's allocator", in five places, and it is not true

The 2026-09-03 dataset's Debian group has six candidates. Five are slower than
the control by more than their own MAD. The sixth, **snmalloc at 1.028× against
a 3.6% MAD, is a tie** - and the report itself marks it ` ≈ control`, because
this session taught it to.

 **So the snapshot's own README contradicted its own table**, two paragraphs
apart. The musl side had the same defect in the other direction: hardened_malloc
is 1.008× against 1.7%, also a tie, counted as a win in the sentence "every one
beats musl's allocator".

Corrected in `docs/AGENTS.md` §13, `docs/history/todo/PROGRESS.md`, the snapshot README,
`docs/history/todo/mechanisms.md`, `examples/README.md` and two example scripts, to the form
the data supports: **five of six beat musl's allocator and the sixth ties it;
five of six lose to glibc's and the sixth ties it.**  Which is a better
finding: the exceptions are the same shape on both sides.

 **The same overstatement was inherited from the previous session** -
`examples/10-debian-preload.sh` cited the 2026-09-02 run as "jemalloc, mimalloc
and snmalloc were all SLOWER on Debian", and in that run snmalloc is 1.082×
against a 10.5% MAD. Also a tie. Fixed.

###  Found: the example asserted a link failure that does not happen

`examples/30-alpine-static-pie.sh` said the naive `cc -static-pie prog.c
libmimalloc.a` would fail with `multiple definition`, generalising this
project's measured `link-override` result. **It links.** The binary contains
mimalloc, contains none of musl's allocator, and passes every check.

The nine-symbol collision `docs/AGENTS.md` §5.1 measures is a **Rust** link,
whose std drags in enough of musl to pull in objects referencing musl's internal
`__libc_malloc`. A small C program never extracts `malloc.lo` at all.

 **And the corrected version is a better example**, because the real objection
is worse than "it fails": *whether it works is a property of your program's link
closure*, and it changes the day someone adds a library call. Corrected in the
script, in `docs/replacing-the-allocator.md` §5.2 and in the mechanism table.

###  Found: "`cc -static` gives you a non-PIE binary"

Alpine's gcc is `--enable-default-pie` (verified: `gcc -v` names it), so
`-static` yields a **static-PIE** and the example's ASLR contrast was comparing
a static-PIE with itself. It failed its own check and said so, which is how it
was found. `-static -no-pie` is required.

 Same shape as the `-fno-PIC` without `-fno-PIE` trap already recorded in
`allocators/lib.sh`: **the flag that names the property is not the flag that
turns it off.**

###  Checked and true

- tcmalloc's "0 `cc_shared_library`, 0 `linkshared`" - re-counted across all
  four BUILD files **and both `.bzl` files**: 0 and 0 in every one.
- hardened_malloc's "the objects are the archive's objects, byte for byte" -
  read off upstream's `Makefile:42`, `SOURCES := chacha.c h_malloc.c memory.c
  pages.c random.c util.c`, which is exactly the recipe's loop, with
  `CONFIG_CXX_ALLOCATOR=false` adding nothing.
- `libmesh.so` at 313 424 bytes exporting `malloc` - from
  `experiments/out/100-mesh-artefacts.txt`.
- every figure in the snapshot README - from `rankings.json` via the
  regenerated `report.md`.

### What would have had to be true for this pass to find nothing

That I had computed the tie rule while writing the prose rather than after. The
irony is exact: **this session's own feature is the thing that caught this
session's own overstatement.** The ` ≈ control` marker in the regenerated table
is what made the contradiction visible; without `T-015` the README's sentence and
its table would have agreed, and both would have been wrong.

---

## What the passes have in common, and it is worth naming

 **All of them found the same class of error, at different altitudes:**

| pass | the error |
| --- | --- |
| 1 | a *document* that renders a number was not in the set of things that render numbers |
| 2 | a *guard* was never given the input that distinguishes its two answers |
| 3 | a *sentence* was written from the shape of the result rather than from the result |
| 4 | a *guard* keyed on a symbol that had not existed since musl 1.2.1 - and an *example* asserted four properties of a distribution it had not asked |

 And the session's three headline findings are a fourth instance of it: mesh's
refusal, tcmalloc's `find`, and tcmalloc's TLS error were all **the instrument
reporting the strongest available claim from the weakest available evidence** -
"there is no such thing", from a search that could not look.

---

## Pass 4 - the examples the operator asked for last, and what they found

**Swept:** `examples/50-archlinux-glibc.sh` and `examples/60-chimera-musl.sh`,
added on request as a third glibc distribution and "a niche distro where the
patching is a bit complicated". Both had to be written, run, and read.

###  Found: example 50 proved its claim with a test that could not fail

The section headed *"the static replacement, attempted"* deleted glibc's
`malloc.o` from a **copy** of `libc.a`, passed the copy on the command line, and
reported that the link failed.  It also passed when it should not have: the
compiler driver still appends `-lc`, so the **real** `libc.a` satisfied
everything the deletion removed. The link's outcome was a statement about the
driver, not about the surgery.

 Fixed by installing the modified archive as the system `libc.a` and linking
with **no archive named**. The transcript now carries 368 undefined-reference
lines and names `malloc`, `free`, `calloc`, `realloc` among them. The claim is
the same; it is now supported.

###  Found: example 60 asserted four things about a distribution and its own transcript contradicted two

The file was written from reading rather than from running. Its header said
`/usr/lib/libc.a` does not exist on Chimera - the transcript printed
`/usr/lib/libc.a exists? yes` eleven lines later. It said llvm-nm writes
`libc.a(member):` headers - the transcript printed bare `aio.lo:`.

 **Both were in the same file as the rule they break** (§4: *a comment
describing what the code should do is not evidence that it does*).
`experiments/110-chimera-ar-mri.sh` re-asked all four against the image.

###  Found, and it is the largest of the session's findings: a guard that could not fail, shipped by the pass that wrote the rule against them

Three examples asserted the displaced allocator was gone with

```sh
want_no_symbol "$binary" __bin_chunk unbin
```

`__bin_chunk` belongs to musl's **oldmalloc**, replaced by mallocng in musl
1.2.1. Measured count in Alpine's `libc.a`: **0**. In Chimera's: **0**. The
assertion had passed on every binary ever built here and could not have failed
for any input - the exact defect pass 2 was created to catch, in code pass 2
did not think to point at because it was checking the *checks* and this was a
*use* of one.

 Fixed by `want_displaced`, which takes the pre-surgery binary as well and
reports "absent from both" as **no evidence** rather than as a pass. Examples 30
and 40 now show the count going 2 → 0. Three planted cases added to the
self-test, which is now 19.

 **This never touched a published number.** `crates/alloc-runner/src/ident.rs`
has always keyed on mallocng's real internals. The vacuous control lived only in
the examples layer.

###  Found: "the surgery is a musl technique" is false, and the counter-example was in the example added to confirm it

Chimera's musl ships **mimalloc** as its libc allocator, in a `libc.a` member
that also defines `__malloc_tls_default` - referenced by `pthread_create.lo` and
`__init_tls.lo`. The existing guard passes it (the member defines nothing
unrelated), the splice succeeds, and the **link** fails three steps later on a
threading symbol.

 A second guard now looks at references rather than definitions and refuses
with exit 3, naming the symbols. Example 60 shows it refusing and then **forces
the deletion anyway**, so the transcript carries the linker error the guard
prevents. `docs/history/todo/mechanisms.md` T-018.


###  Found by re-reading, not by running: the production script had the same defect

T-018's finding was a guard keyed on a symbol that no longer exists. The obvious
next question - *does anything else here key on a written-down list?* - pointed
at `scripts/build/libc-surgery.sh`, whose own header criticises the prior art
for exactly that and whose post-splice check then asks about four hard-coded
alias names.

 **It was never producing a wrong number**: a stranded symbol fails the link
loudly and the cell is recorded `build_failed`. What it cost was the diagnosis.

 Closed by `ar::stranded`, which derives the answer by asking what the
ORIGINAL archive defined - the baseline is what makes a list unnecessary, since
symbols `libc.a` never defined were undefined before the splice too.
 **And it was measured before it was allowed to refuse**, because a check that
refuses working archives is worse than the gap it closes: on Alpine, after
synthesis, it reports nothing; on Chimera it reports `__malloc_tls_default`.
`docs/history/todo/mechanisms.md` T-019.

 **The probe that proved it had the pipe defect in its own oracle.** Its first
draft ran the production script through `| sed` and read `$?` - sed's status -
so Chimera's refusal was reported as exit 0. The probe's own assertions caught
the contradiction (a refusal message and a success code), which is the argument
for asserting rather than eyeballing, made against the person writing it.

### What would have had to be true for this pass to find nothing

The examples would have had to be written from measurements instead of from
recollection of how these distributions work.  Two of the four findings were
visible in transcripts that had already been committed - the evidence was
present and unread. **Running a script and reading its output are different
acts**, and only the second is a review.

---

## Pass 5 - does every number in a human-facing document match the dataset it cites?

**Swept:** every ratio, percentage and absolute time in `README.md`, the two
datasets published today, and `docs/history/todo/PROGRESS.md`, recomputed from
`rankings.json` and the raw `results/*.json` rather than read back.

**Not swept:** whether the measurements are any good. This pass asks only
whether the sentence and the file agree.

###  Checked and true

Every per-libc figure in
[`2026-09-03-libc-contrast-x86_64/`](../../../results/published/2026-09-03-libc-contrast-x86_64/)
and in `README.md` §2 recomputes exactly - five allocators × two libcs, medians,
ranges and win counts. jemalloc's "34–37% on all three musl distributions" is
36.2 / 34.5 / 37.1. The three musl leaders really are three different
allocators: rpmalloc on Void (0.580), snmalloc on Alpine (0.619), mimalloc on
Wolfi (0.602). Every peak-RSS figure in §3.1 recomputes from `maxrss_kb` medians
to three decimals - rpmalloc 1.086 / 1.010 through mimalloc 3.265 / 3.070.
hardened_malloc's 2.108× is `rel_time` to four figures.

###  Found: one table, two datasets, no citation

`README.md` §3 read:

| | musl | glibc |
| --- | --- | --- |
| control's own time, same workload | 0.0730 s | 0.0411–0.0429 s |
| what the best candidate buys | **33–42%** | nothing |

The **percentages** are `libc-contrast`, which the section is about. The
**times** are the `distros` run of 2026-09-02 - a different suite, a different
machine, one musl distribution and two glibc. `libc-contrast`'s own control
times are **0.0500–0.0532 s** on musl against **0.0246–0.0264 s** on glibc.

 Nothing here was fabricated and every number was true where it was first
published. The defect is the pairing: two runs in one table, with no line saying
so, which reads as one measurement.  The finding survives - the ratio is 1.78×
in one run and ~2.0× in the other - and that is now stated instead of implied.
Corrected in `README.md` and `docs/history/todo/PROGRESS.md`.

### What would have had to be true for this pass to find nothing

Every table would have had to be built from one dataset, or say which datasets
it mixes.  The error was introduced *by this session*, in the rewrite that was
supposed to make the results page clearer - a table gains authority by being
tidy, and tidy is not the same as sourced.

---

## Pass 6 - can every guard this session added actually fail?

**Swept:** the assertions added or changed today, asked one at a time: *what
input makes this print ?* - `want_displaced`, `musl-libc-surgery.sh`'s
stranded refusal, `libc-surgery.sh`'s refusal, `ar::stranded`, and every
`want_symbol` / `want_no_symbol` call site in the six examples.

**Not swept:** the checks that predate today. Pass 2 covered those.

###  Four of five have a demonstrated firing

| guard | what makes it fail | seen firing |
| --- | --- | --- |
| `want_displaced` | symbol absent from the before-binary, or surviving in the after-binary | `verify-selftest.sh`, two planted cases |
| `ar::stranded` | a symbol the baseline defined and the splice dropped | `alloc-runner selftest`, and the false-positive case |
| `musl-libc-surgery.sh` exit 3 | Chimera | `examples/out/60-chimera-musl.txt`, then the forced deletion showing the link error it prevents |
| `libc-surgery.sh` refusal | Chimera | `experiments/out/130-…`, exit 1, `libc.a` byte-identical |

###  Found: the fifth, in the file this session wrote about guards that cannot fail

`examples/60-chimera-musl.sh` ended with

```sh
want_no_symbol /tmp/probe nontrivial_free get_meta
```

- mallocng's markers, asserted absent from a Chimera binary.  **Section 3 of
the same script had already counted them in Chimera's `libc.a` at zero.** They
cannot be in any binary that image produces. Two assertions that could not fail,
written into the example whose entire subject is an assertion that could not
fail, by the pass that removed the last one.

 Removed rather than repaired, because there is nothing to repair: on Chimera
the allocator the surgery would install is the one already present, so **no ELF
check can distinguish "displaced" from "never replaced"**. The transcript now
says that in words and prints the count as context rather than as a verdict.
Example 60 is 11 checks, not 13, and the two it lost were worth nothing.

### What would have had to be true for this pass to find nothing

Every new assertion would have had to be written against a binary whose *before*
state was known.  The general lesson is narrower than "check your guards": a
negative control is a claim about **two** states, and a checklist that records
only the second cannot tell them apart.

---

## Pass 7 - what did a late change leave inconsistent?

**Swept:** counts and cross-references that a change made after they were
written would silently invalidate - example check totals, self-test case counts,
entry counts, the experiments index, and every document naming a number this
session changed.

**Not swept:** correctness of any claim. Pass 5 did that. This pass only asks
whether the tree agrees with itself.

###  Found: three stale counts, all created within the hour

- `docs/history/todo/PROGRESS.md` and `docs/history/todo/mechanisms.md` said the examples run **67**
  checks. Pass 6 removed two, so it is **65**.
- `docs/history/todo/mechanisms.md` T-018's `Prove` block quoted example 60 at `13 passed`.
  It is `11 passed`, and the entry now says why the number went down.
- `examples/README.md` and the self-test's own closing text still said **16**
  planted cases and "the four examples"; both are corrected (19, six).

 **`check-todo.py` caught none of these and could not have** - it verifies the
entry counts, which were right. The counts that go stale are the ones written
into prose, and nothing checks those.  That is a gap worth an entry rather than
a promise, and it is in the work order.

### What would have had to be true for this pass to find nothing

Every number in prose would have had to be regenerated rather than typed.  The
session's own rule - *never retype a count* - has a tool behind it for the entry
tables and nothing behind it anywhere else, and three of the four counts that
went stale today were in files the rule does not reach.
