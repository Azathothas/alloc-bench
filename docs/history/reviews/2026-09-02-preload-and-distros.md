# Deep review: the preload mechanism, the dynamic baseline, and the roll guard, 2026-09-02 (second session)

Three passes, three **different** questions, per
[`../../methodology/reviews.md`](../../methodology/reviews.md). Each names what
it looked at that the others did not, and - for anything it did not find - what
would have had to be true for it to fire.

**Scope.** This session's change: `MODE=preload` across six allocator recipes
and `allocators/lib.sh`'s `finish_so`; `alloc-runner preload-check` and
`crates/alloc-runner/src/preload.rs`; the identity oracle's dynamic-baseline
branch and `elf::imports`/`elf::defines`; `validate.rs`'s preload evidence
check; `report.rs`'s preload table; `model.rs`/`run.rs`'s `preload` field;
`run-cell.sh`'s residency step; the `roll` guard in `.github/workflows/bench.yml`;
`allocators.toml`'s snmalloc entry; `experiments/80-` and `90-`; and every
document and dataset published alongside them.

---

## Pass 1 - the door sweep

**"What other caller reaches this, and does every path pass the same check?"**

 **What this pass looked at that the others did not:** the *enumeration*. Not
whether a guard can fail (pass 2), nor whether a published sentence is true
(pass 3), but whether the set of paths into each changed behaviour is the set I
believed it was. The list written from memory was, as always, incomplete.

Swept, by grep rather than by recall: every caller of `ident::judge`,
`ident::detect` and `detect_libc_allocator`; every `finish`/`finish_so` call
site across the six recipes; every consumer of `$SHARED` /
`liballocbench.so`; and every branch on the string `preload` in `crates/`,
`scripts/`, `allocators/` and `benchmarks/`.

###  Found: two allocators declare `preload` and their recipes do not implement it

`allocators.toml` declares `preload` for **five** allocators plus mesh and
tcmalloc. Three recipes gained a `MODE=preload` branch this session
(mimalloc, jemalloc, snmalloc) and two did not: **rpmalloc** and
**hardened_malloc**.

 **It is unreachable today and the failure mode is still wrong.** No suite
pairs either with `preload` - `docs/AGENTS.md` §5 already says so about the
*exercised* column - so nothing had ever taken the path. Traced by hand: the
mode falls through to each recipe's `prefixed` branch, builds a perfectly good
**archive**, and `run-cell.sh` then reports

```
preload needs …/liballocbench.so and the allocator build produced none
```

which is true and misleading. It reads as an allocator that cannot produce a
shared object.  For hardened_malloc it is exactly backwards: upstream's
default `make` output *is* `out/libhardened_malloc.so`, and this recipe goes out
of its way to get an archive instead.

**Fixed** by an explicit refusal at the top of each recipe - above the source
checks, so it does not depend on a source tree being present - naming the gap as
this project's rather than upstream's. Verified in a container with the current
recipes bind-mounted over the image's, exit code read from the process that
produced it:

```
rpmalloc         MODE=preload  rc=3  UNSUPPORTED: this recipe implements prefixed and override, not preload…
hardened_malloc  MODE=preload  rc=3  UNSUPPORTED: this recipe implements prefixed and override, not preload…
rpmalloc         MODE=prefixed rc=3  UNSUPPORTED: rpmalloc/rpmalloc.c not found at this revision…
```

 The third line is the mode control: the same invocation with a different
`MODE` reaches a **different** refusal, so the new branch is mode-specific and
is not swallowing every failure.

 **The first attempt at this verification was worthless and said so.** Run
against the image as built, both allocators exited 3 - on the *source* check,
because `/opt/alloc-bench/allocators` is baked in at image build time and still
held the old recipes. The mutation had not landed. Reading that as "the guard
works" is precisely the failure `RULES.md` §4 warns about.

### Checked and clean

- **`ident::judge` has one production caller**, `cmd_identify`, plus six
  selftest call sites. No second path reaches the baseline rule.
- **`detect` gained a second consumer** - `cmd_preload_check`, which applies it
  to a `.so` rather than an executable.  That is a new door into the oracle and
  it deliberately does **not** use `judge`: `judge`'s link-kind and
  negative-control logic is written for executables, and a `.so` classifies as
  `static-pie` (ET_DYN, no PT_INTERP), so asserting a link kind there would
  report a true-looking field with a misleading value. Recorded in the code.
- **`$SHARED` has exactly one consumer**, `run-cell.sh`, and it now names the
  file rather than taking `find … | head -1` over an unordered walk.
- **`build-ripgrep.sh` reaches `preload` in one place** (the no-shim branch) and
  its link-configuration `case` has no preload arm, which is correct: a preload
  cell is a plain dynamic build.
- **`validate.rs`'s preload check sits inside the `"ok"` arm**, after the match
  that `continue`s on `unsupported`, so an unsupported preload cell is not asked
  for residency evidence it could not have.

### What would have had to be true for this pass to find more

It swept callers of things this session *changed*. A defect in a path that
touches none of them - the report's composite formula, the corpus generator,
`combine.py` - is outside its reach by construction, and pass 3 is the one that
would meet those, through their published output rather than their callers.

---

## Pass 2 - the guard mutation

**"Can each new guard actually refuse, and does the refusal name the right
thing?"**

 **What this pass looked at that the others did not:** whether a check that
has only ever been seen to *pass* can fail at all. Pass 1 asks where a guard is
missing; this one assumes it is present and asks whether it is theatre.  Every
mutation below is asserted to have landed **before** its guard's verdict is
read.

### `finish_so` - the dynamic-export assertion

The trap it exists for: a library that defines `malloc` in `.symtab` and does
not export it, so `LD_PRELOAD` interposes nothing while every static-minded
symbol check says the library is fine.

```
mutation: a .so with __attribute__((visibility("hidden"))) on malloc
  landed:  .symtab defines malloc -> 1     .dynsym exports malloc -> 0
  verdict: rc=1, "shared object … does not EXPORT required symbol(s): malloc free realloc calloc"
```

 Fires, and names the symbols.

### `validate.rs` - the preload residency evidence, three ways

Mutating the published 12-cell dataset one cell at a time. Baseline: **0
errors**.

| mutation | landed | validator |
| --- | --- | --- |
| `with_preload.library_resident` 4 → 0 | asserted | **1 error**, `preload-not-resident` |
| `without_preload.library_resident` 0 → 4 | asserted | **1 error**, `preload-not-resident` |
| the `preload` key removed entirely | asserted | **1 error**, `preload-evidence-missing` |

 All three refuse and exit 1, with distinct messages.  The middle row is the
one that matters: a positive observation whose control also fires is not
evidence, and the validator says so in those words.

### `preload-check` - its own negative control

[`../../../experiments/90-preload-residency.sh`](../../../experiments/90-preload-residency.sh),
case 3: `--so` pointed at the libc the subject loads anyway.

```
with LD_PRELOAD:    resident 3 of 3 sampled
without (control):  resident 3 of 3 sampled
reason: the library was mapped in 3 of 3 runs with NO LD_PRELOAD set:
        the positive observation does not distinguish a working preload
        from a library that is there anyway
exit 1
```

 The control can fail, and this input makes it.

###  And writing that probe found three defects in the thing it was probing

None of them would have been found by reading the code - one of them is a
comment that states the opposite of what the code beneath it does.

1. **The control could not fail.** `probe` took `Option<&str>` and skipped the
   `/proc/<pid>/maps` search when it was `None`, so the control reported
   `library_resident: 0` **by construction**, for every input, forever.
2. **The reader could not match a canonical path.** `/proc/<pid>/maps` reports
   resolved paths; where `/lib` is a symlink to `/usr/lib`, an exact match
   against the caller's string finds nothing - including glibc itself.
3. **The poll stopped before the loader ran.** It broke as soon as the subject's
   own text appeared. The *kernel* maps the executable and the ELF interpreter
   at `execve`; every shared library, `LD_PRELOAD` included, is mapped
   afterwards by `ld.so`. So the first read in which the subject exists is
   systematically the earliest possible one, and the check reported **every**
   library absent from **every** process.

 **A comment three lines above that loop claimed the library was looked for
"in the SAME read"**, while two reads were issued.  The probe found it; a
careful reading of the comment would have confirmed the bug.

### `experiments/80-` - the roll guard, both directions

| case | old guard | new guard | wanted |
| --- | --- | --- | --- |
| a window that does not exist yet | SKIP | COMMIT | COMMIT |
| an existing window gains a run | COMMIT | COMMIT | COMMIT |
| nothing changed | SKIP | SKIP | SKIP |

 Case 3 is not padding: a guard that always committed would pass case 1 and be
worse than the bug it replaced.

### What would have had to be true for this pass to find more

It mutated the guards this session added. Guards it did not touch - the
correctness gate's needle counts, the ASLR probe's sampler, `patch-rg`'s
assertion - were exercised only incidentally by the runs, and a defect in one of
those would have had to change a published number to be visible here.

---

## Pass 3 - the claim audit

**"Which sentence about to be published is not backed by an artefact I can point
at?"**

 **What this pass looked at that the others did not:** the *prose*, against the
JSON. Not the code's behaviour but the wording of the four snapshot READMEs, the
two closed entries, and the `docs/AGENTS.md` rows - re-derived from
`rankings.json` with a script rather than re-read.

###  Found: "only jemalloc beats the control" overstated the data

The `profiles` CI-runner README said *"On the Xeon all three candidates beat the
control in every profile, by 28–47%. Here only jemalloc does"*. Re-derived:

| profile | mimalloc `rel` | margin | its MAD | control MAD |
| --- | --- | --- | --- | --- |
| `static` | 1.0069 | −0.69% | 2.0% | 1.8% |
| `static-lto` | 0.9984 | +0.16% | 2.1% | 1.1% |
| `static-pie` | 0.9815 | **+1.85%** | 2.2% | 1.3% |
| `static-pie-lto` | 0.9936 | +0.64% | 0.5% | 1.3% |

 **mimalloc is nominally below the control in three of the four profiles**, and
a reader scanning the table would call that a win. It is not one - every margin
is inside the noise - but the sentence as written did not say which sense of
"beats" it meant, and the table it sat above showed `0.982×`. Corrected in the
README and in `T-006` to say *"by more than the run's own spread"*, with the
four margins and their MADs spelled out.

###  Found: a range that was wrong in the second digit

`T-006` said snmalloc had been *"39–47% faster"* on run 1. Re-derived from the
dataset: **34.0–47.3%** - `static-lto` is 34.0%, not 39%. Corrected.

 Both of these are the same failure in different sizes: a number recalled from
a neighbouring sentence instead of recomputed. The audit script is four lines
and would have caught either at any point.

### Re-derived and confirmed

- *"the four C allocators pass `libc-surgery` and the one C++ one does not"* -
  run E's `results/`: hardened_malloc `ok`, jemalloc `ok`, mimalloc `ok`,
  rpmalloc `ok`, snmalloc `build_failed`.
- *"snmalloc is the fastest row on musl under preload"* - 0.6478 against
  jemalloc 0.7503 and mimalloc 0.7684.
- *"18 of 18 ASLR randomised"* in `distros` - counted from the 18 cell
  documents.
- *"jemalloc 15–18% faster"* (15.2–17.7%) and *"snmalloc 10–15% slower"*
  (10.2–15.0%) on the EPYC.
- *"28–47%"* for run 1's candidates - 28.1–47.3%.
- Every control ratio in the static-PIE table, recomputed to four places from
  `time_s`: 1.0303, 1.0114, 0.9853, 0.9673. The README's rounded 1.030/1.011/
  0.985/0.967 match.

###  Deliberately left as unexplained rather than folded into a nearby sentence

- **jemalloc's two ~20 KB binary differences** between the two `profiles` runs.
  The 8-byte differences have a recorded explanation (autotools embeds
  build-time strings); the 20 KB ones are on the `PIC=0` cells and were not
  investigated. The README says so instead of extending the explanation to
  cover them.
- **jemalloc's absolute peak RSS, 6 700 kB on one machine and 31 864 kB on the
  other**, on the same workload. Both hosts report 4 CPUs, so the obvious
  arena-per-core story does not fall out of the recorded conditions, and
  nothing was measured that would settle it.
- **Why mesh's build leaves no library.** Every object of the `mesh` target is
  there and no `.so` or `.a` anywhere. Whether its shared-library link sits
  behind an unset CMake option is not established; nobody has read its
  `CMakeLists.txt`.

### What would have had to be true for this pass to find more

It audited claims that have a dataset behind them. A claim with no artefact at
all - a sentence about what a tool *would* do, an assertion about upstream
behaviour taken from a header - has nothing to be re-derived from, and passes
this lens untouched. The `preload` entry's statement that *upstream rpmalloc
supports LD_PRELOAD* is one such: it is read from the source, not measured, and
is written as a reason to keep a declaration rather than as a result.
