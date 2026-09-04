# Why this window keeps restarting - twice now, for the same reason

 **This window has held three runs, then two, then three, and now one. No data
has been lost at any point, and each restart was the same rule applied.**

 **A rolling window's `rank` column is not comparable across runs with different
candidate sets.** "Position within the run, fastest = 1" means one thing in a
field of four and another in a field of eight, so every candidate would appear to
have *moved* for a reason that is not the machine - and moved ranks are precisely
what this window uses to refuse an ordering.
`scripts/report/aggregate.py --check` says so directly, and it is the check that
forced each restart.

## Restart 1, 2026-09-03: the suite gained rpmalloc and hardened_malloc

`preload` went from **12 cells to 16** when rpmalloc and hardened_malloc - which
had declared the mechanism from the beginning and which no cell had ever paired
with it - were implemented, and mesh started producing numbers. Each group went
from four rows to seven.

| run | machine | where it is now |
| --- | --- | --- |
| `20260902-133258-ci33636229346` | AMD EPYC 7763 | [`../../published/2026-09-02-preload-x86_64-ci-runner/`](../../published/2026-09-02-preload-x86_64-ci-runner/) |
| `20260902-135910-ci33638469352` | Intel Xeon Platinum 8573C | the artefact of [bench `33638469352`](https://github.com/Azathothas/alloc-bench/actions/runs/33638469352) |
| `20260902-130704-local` | Intel Xeon @ 2.80GHz | [`../../published/2026-09-02-preload-x86_64/`](../../published/2026-09-02-preload-x86_64/) |

## Restart 2, 2026-09-03:  tcmalloc produced its first number

The `debian` group went from **seven candidates to eight**. Google tcmalloc had
never produced a measurement in this project's history; it does now
([`../../published/2026-09-03-preload-x86_64-tcmalloc/`](../../published/2026-09-03-preload-x86_64-tcmalloc/)),
and `--check` refused the window in exactly the words it is written to say:

```
aggregate: results/rolling/preload-x86_64: debian / x86_64 / dynamic / distro /
           tcmalloc appears in 1 of 3 runs.
```

So the two seven-candidate runs came out:

| run | machine | where it is now |
| --- | --- | --- |
| `20260903-063056-ci33723373486` | Intel Xeon Platinum 8573C | the artefact of [bench `33723373486`](https://github.com/Azathothas/alloc-bench/actions/runs/33723373486) |
| `20260903-003445-local` | Intel Xeon @ 2.80GHz | [`../../published/2026-09-03-preload-x86_64-all-eight/`](../../published/2026-09-03-preload-x86_64-all-eight/) |

##  What this costs, stated rather than glossed

The window holds **one run on one machine**, so it establishes nothing whatever
about transfer, and its own " One run" banner says so.

 **And the cost is real this time in a way it was not before.** Those two runs
had just become a two-machine comparison that the README's §3 was citing, and
removing them takes that away *from the window*.  The finding itself is not
lost - it is stronger, because the new run is a **third** machine agreeing:

| | machine 1 (Xeon 2.80) | machine 2 (Xeon Platinum 8573C) | machine 3 (EPYC 9V74) |
| --- | --- | --- | --- |
| jemalloc on musl | beats | beats | **0.884×**, lead 11.6% vs a 1.2% MAD |
| rpmalloc on musl | beats | beats | **0.900×**, lead 10.0% vs a 0.8% MAD |
| anything on glibc |  none |  none |  none |

 So README §3 cites the three **datasets**, which is where a claim about three
machines properly lives; the window will say it again once a second run of the
eight-candidate suite lands.

##  What was rejected, twice, and once more today

- **Teaching `--check` to accept a missing candidate.** The window stores
  `rankings.json` and `run.json`, and neither says whether a candidate is absent
  because the suite did not include it or because its cell **failed and was
  dropped** - which is the case the check exists to catch. Weakening it to pass a
  legitimate widening blinds it to an illegitimate disappearance.
-  **NEW, and refused today: making `--check` refuse the GROUP rather than the
  window.** Only the `debian` group gained a candidate; `alpine` has seven in all
  three runs and is perfectly comparable, so a group-level refusal would have
  kept a three-machine `alpine` comparison alive.  It is a *tempting* change and
  it may even be the right one - but it was reached for at the end of a session,
  by the session that disliked the consequence of the existing rule, to avoid
  paying it. That is the exact pressure "never weaken a check to get green" names.
   If a later session wants it, it should arrive as an entry with its own
  argument, not as a convenience.

##  Restart 3 that WASN'T, 2026-09-03: a second run was dispatched and did not land

Bench [`33749457837`](https://github.com/Azathothas/alloc-bench/actions/runs/33749457837)
ran `preload` on x86_64 to give this window the second eight-candidate run the
section above says it needs. **15 of 16 cells came back `ok` with 0 validator
errors**, and the fold was still refused:

```
aggregate: results/rolling/preload-x86_64: debian / x86_64 / dynamic / distro /
           tcmalloc appears in 1 of 2 runs.
```

 **That is the check doing the second of the two jobs its own message names.**
It offers two readings - *the suite's candidate set changed*, or *a cell failed
and was dropped* - and this time it is the second. Google tcmalloc's `debian`
cell came back `build_failed`, so the run has seven candidates there against the
stored run's eight.

 **So the rule from restarts 1 and 2 does NOT apply here**, and applying it
would have been wrong. Those were genuine widenings, where the older runs were
no longer rank-comparable and belonged out of the window. This is a **defect**:
nothing about the suite changed. Evicting the stored run would have thrown away
the only measurement Google tcmalloc has ever produced in order to make room for
a run that is missing it.

 **The defect is [`T-028`](../../../docs/history/todo/instrument.md), and it is not tcmalloc's.**
Every recipe chose its build artefact by name - `find -L … -name 'libfoo*.so*'
| head -1` - and `*.so*` matches the `.so-2.params` and `.jdeps` files Bazel
writes beside the library. The cell failed with `nm: file format not recognized`
on a library that had built fine. Fixed by reading each candidate's ELF header
instead; [`../../experiments/180-which-file-did-the-recipe-take.sh`](../../../experiments/180-which-file-did-the-recipe-take.sh).

 **This window therefore still holds ONE run, deliberately**, and the thing it
is waiting for is now a dispatch with that fix in the tree rather than a decision
about the window.

###  Resolved the same day: the second run landed once the defect was fixed

Bench [`33790455334`](https://github.com/Azathothas/alloc-bench/actions/runs/33790455334),
dispatched with [`T-028`](../../../docs/history/todo/instrument.md)'s fix in the tree, came
back **`success` on every job** - the `rolling aggregate` job included - and its
`roll` job committed this window unaided (`6e2bcff`).

 **Google tcmalloc's number reproduced**, `1.2664×` → `1.2822×`, **1.2% apart
on two different CPUs**. That is the tightest reproduction in this project, and
it settles what the previous section could not: the refusal was the recipe
copying out the wrong file.

 **And read the window's ordering claim with its machines in view.** It now
reports every allocator holding its rank in **both** groups - the first window
here that has not refused an ordering. Both runs are **AMD EPYCs** (7763 and
9V74).  The Xeon runs came out during restarts 1 and 2, so this window has not
yet been asked the question that every other one answers `no`.
