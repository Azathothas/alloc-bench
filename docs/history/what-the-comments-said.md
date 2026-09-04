# What the comments said

 **This file exists so that trimming a comment is a MOVE and not a deletion.**
[`todo/instrument.md`](todo/instrument.md) T-027 trimmed the incident
narrative out of this repository's shell and left the technical reasons behind.
Every passage below was removed from a file that still exists, and is recorded
here **verbatim**, with the file it came from and the line it explained.

 **The test that was applied to each comment:** *does a reader who has never
seen the bug need this to avoid re-breaking the line?*

- **Kept in the code**: the technical reason - *"`|| true`: `grep -c` exits 1 on
  a count of zero, which is the case this line detects."*
- **Kept in the code**: any note explaining why a check is written the way it is
  where the obvious simpler form **fails open**. Those read like lore and are
  the reason the check works.
- **Moved here**: which run found it, which session, what the diagnostic printed,
  how many cells were affected.

 **So the code says why a line is the way it is, and this file says what it
cost to find out.**

---

## `allocators/lib.sh`

### On `finish()` reading `nm`'s output once and checking the read worked

>  FOUND BY A DOOR SWEEP, not by a failure. `finish_so` was fixed first
> because a real artefact tripped it (T-024); `finish` had the identical
> `"$NM" … 2>/dev/null | grep -q …` in FOUR places and is the path every
> non-preload cell takes - `rust-global`, `libc-surgery`, `link-override`:
> 103 of the matrix's 131 planned cells against preload's 28. The defect
> that announced itself was in the smaller path.

### On the `prefixed`-mode malloc check being the one that fails open

> A broken `nm` would have passed a prefixed archive that DOES define malloc,
> and the rust-global and libc-surgery cells would then have been the same
> experiment reported as two - exactly what this check exists to prevent.
> Reading the captured text closes it, because an unreadable table now exits 2
> above.

 The **first** sentence of that passage stays in the code, because "this test
fails open where the others fail closed" is the reason the line is written the
way it is. What moved is the history of how it was found.

### On `$OUT/lib/liballocbench.so` being a fixed name

>  run-cell.sh used to take the first `*.so*` it found under `$OUT/lib`, which
> is a `head -1` over an unordered `find`: a recipe that left a second shared
> object about would have had one picked for it silently.

### On `pick_elf_so` reading ELF headers instead of trusting names

>  MEASURED, not reasoned about. bench run 33749457837 built tcmalloc's
> generated shared library successfully and then failed the cell with
>
>     cannot read the dynamic symbol table of .../liballocbench.so with 'gcc-nm'
>     | /usr/bin/nm: ...: file format not recognized
>
> on the same recipe and the same commit that had produced a real number one run
> earlier. The build was fine; the recipe copied out the wrong file.
>
>  That the specific file was the `.params` one is INFERRED from the glob and
> the error, not read from that run - its artefact had expired by the time this
> was diagnosed.

### On `finish_so` reading the DYNAMIC table

>  THIS IS NOT HYPOTHETICAL. It fired on bench run 33723373486: tcmalloc's
> generated `cc_binary(linkshared = 1)` produced a real `.so`, `finish_so`
> refused it, and the diagnostic printed
>
>     --- dynamic symbols it does export (first 40) ---
>
> followed by NOTHING - leaving a reader unable to tell an object with no
> dynamic exports from an `nm` that never ran.
>
>  Two of tcmalloc's four recorded refusals were certainly the instrument
> (a TLS failure reported as a build failure; `find -P` not following the
> `bazel-bin` symlink) and one is certainly upstream (musl is unsupported).
> This fourth is UNDECIDED, and saying so is the point of the fix.

 **And the count in that passage is now wrong**, which is its own small lesson:
tcmalloc has **five** recorded refusals, **four** of them this project's
instrument. [`todo/instrument.md`](todo/instrument.md) T-028.

---

## `scripts/build/libc-surgery.sh`

### On why the internal allocator symbol names are listed, not just the public ones

>  THE PUBLIC ENTRY POINTS ARE NOT ENOUGH, and measuring is how that was found.
> On Alpine musl 1.2.6 (`experiments/50-libc-surgery-verify.sh`, 2026-09-01):
>
>     lite_malloc.lo  defines  malloc          <- the public name
>     malloc.lo       defines  __libc_malloc_impl, __malloc_alloc_meta,
>                              __malloc_allzerop, __malloc_atfork
>     donate.lo       defines  __malloc_donate
>
> Deriving only from the public names displaces 11 members and leaves
> `malloc.lo` - musl's actual mallocng IMPLEMENTATION - inside the archive.
> The resulting binary is still correct, because nothing references it once
> `lite_malloc.lo` is gone, and the post-splice assertion confirms that. But
> leaving an entire second allocator implementation in libc.a for a later
> reference to find is not a property worth relying on, so the internal names
> are listed too and all 13 members go.

### On `__malloc_atfork`, which was added and then removed

> Adding `__malloc_atfork` to this list looked obviously right and was a serious
> regression, caught on the run after it was added (2026-09-01). On musl 1.2.6:
>
>     fork.lo  defines  __malloc_atfork, __aio_atfork, __ldso_atfork,
>                       __pthread_key_atfork, __tl_lock, __tl_unlock,
>                       and *** fork ***
>
> so keying on it deleted `fork()` from libc.a. The splice still passed its own
> malloc/free assertion, because that assertion says nothing about the rest of
> the C library.

 The one-sentence form of this - *"musl's `fork.lo` defines `__malloc_atfork`
AND `fork`"* - stays in the code, because it is what stops the next reader
adding the symbol back.

---

## `scripts/vendor/mine-repo.sh`

### On why a sweep writes into the repository and not a scratch directory

>  TWO SWEEPS, TWO WAYS OF LOSING THE SAME WORK, BOTH OBSERVED:
>
>   1. A session cloned eleven repositories, read them, wrote a few markdown
>      files of conclusions, and kept NONE of the trees. The next session that
>      wanted to check a citation had to clone all eleven again, which meant
>      the write-up was a claim rather than evidence.
>   2. A session spent about fifteen minutes writing its own issue and pull
>      request fetchers in Python, ran them, produced real JSON, and then
>      deleted the JSON and the fetchers on the way out. The clones had gone
>      to a scratch directory and the scripts to a session-local scratchpad,
>      so neither survived the session and the work was simply gone.
>
>  Both are the same defect: the DERIVED file was treated as the product and
> the EVIDENCE as scratch. It is the wrong way round. A conclusion nobody can
> re-check is an opinion, and the cost of re-fetching is paid by every later
> session rather than once by this one.

 **What stayed in the code** is the rule itself and the three measured
properties of the `api.gh.pkgforge.dev` route - that it is *not* unauthenticated,
that its route set is wider than `/repos/*`, and that a browser-like User-Agent
is refused with **HTTP 420**. Those are the exempt class: a caller who does not
know them writes a client that reports 420 as a network error.

---

## `examples/verify.sh`

### On the header's claim that every check reads its own exit code

>  THAT SENTENCE WAS FALSE UNTIL 2026-09-03, in this file, about the two
> functions directly below it: `want_symbol` and `want_no_symbol` piped `nm`
> into `grep -q` and read grep's status. `want_no_symbol` therefore failed OPEN
> - a dead `nm` reported the negative control as passed. Fixed; the note is
> kept because a document that states a rule its own code breaks is the harder
> defect to find.

 Moved rather than kept because `want_no_symbol` now carries the technical
reason **at the function**, where a reader editing it will see it: *"A FAILED
READ IS A FAILURE HERE, NEVER A PASS … 'nothing found' is this function's
passing answer, so an unreadable binary would otherwise be reported as a clean
displacement."*

---

## `allocators/tcmalloc/build.sh`

### On `find -L` over `bazel-bin`

>  Verified rather than reasoned about, 2026-09-02:
>
>     ln -s real bazel-bin; touch real/libtcmalloc.so
>     find    bazel-bin -type f -name '*.so'  ->  0
>     find -L bazel-bin -type f -name '*.so'  ->  1
>
>  It surfaced only when a GitHub-runner dispatch got PAST the TLS failure that
> had been stopping this recipe on the dev host: Bazel built, the search could
> not look, and the refusal blamed the build. docs/history/todo/mechanisms.md T-003.

---

## `scripts/gate.sh`

### On why a passing check's output is scanned for a skip marker

>  Measured on this gate's own opening run, on a shallow clone: it printed
> "18 passed, 0 failed, 0 skipped" while `check-docs.py` had skipped the vintage
> check and `check-snapshots.py` the recovery check, both of which need real
> history. Two checks retired themselves and the summary line said nothing.

### On `:(glob)` anchoring the markdown-line count to the repository root

> 7283 of the 18806 lines it reported on 2026-09-02 were text nobody in this
> project wrote, and the number grew whenever a DATASET was published, which
> reads like the documentation growing. Found by asking why the count moved
> across a commit that changed no markdown.

### On `--strict` being passed down to the checkers

> It was not: `.github/workflows/ci.yml` runs `check-docs.py --strict` and
> `check-snapshots.py --strict`, and this file ran both WITHOUT the flag in
> either mode - so the check a session ran before pushing was strictly weaker
> than the one that would judge the push.

---

## `allocators/hardened_malloc/build.sh`

### On `-DH_MALLOC_PREFIX` being the mode switch

> Building without it and then hunting for `h_malloc` in the archive finds
> nothing - observed here on 2026-09-01 - and the objcopy-based workaround that
> was written first was solving a problem upstream already has a flag for.

### On both symbol checks having read grep's status

>  Until 2026-09-03 both functions below were `nm … 2>/dev/null | grep -q …`,
> so the status read was GREP'S and nm's own error went to /dev/null. The header
> of this very file says "every check reads an exit code from the process that
> produced it" - and these two did not. A file that states a rule and breaks it
> is worse than one that never stated it.
>
>  AND `want_no_symbol` FAILED OPEN. … That is the same direction the
> production `finish` failed in (docs/history/todo/instrument.md T-024), in the layer whose
> entire subject is negative controls.

### On `__bin_chunk` as a negative control

> Measured 2026-09-03 (`experiments/110-chimera-ar-mri.sh`): the count in
> Alpine's and Chimera's libc.a is ZERO. Asserting its absence therefore passed
> on every binary ever built here, displaced or not.

---

## `allocators/rpmalloc/build.sh`

### On why T-004's original diagnosis was wrong

>  THE RECORDED DIAGNOSIS WAS WRONG BECAUSE THE ERROR WAS A TAIL. TODO
> T-004's premise read the cell's `detail` field - a truncated tail whose last
> visible line is `'_ZdaPv' aliased to undefined symbol 'rpfree'` - and
> concluded the C++ operator aliases were the cause. They are the LAST errors,
> not the first.

## `allocators/hardened_malloc/build.sh` and `allocators/rpmalloc/build.sh`

### On when `MODE=preload` arrived

>  MODE=preload. Added 2026-09-03; before that this recipe refused the mode
> with an accurate message saying the gap was here rather than in rpmalloc, and
> the refusal was right about whose gap it was.

 Both recipes declared `preload` from the beginning and neither implemented
it, and **no cell in any suite paired them with it** - so nothing ever took the
path to find out. `docs/history/todo/mechanisms.md` T-003.

## `allocators/lib.sh` and `examples/verify-selftest.sh`

### On the date the symbol reads were fixed

> Until 2026-09-03 every test below was `"$NM" -D … 2>/dev/null | grep -q …` …
> So a missing, wrong-format or refusing `nm` was reported as *the allocator
> exports nothing*, which is a defect in the allocator being invented out of a
> defect in the tool.

 The mechanism - that the exit code read is grep's - stays in the code, because
it is what stops the pipe being reintroduced. Only the date and the history of
the fix moved here.
