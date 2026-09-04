# Review: tcmalloc's first number, and two claims withdrawn by their own guards, 2026-09-03

 **One pass, not three, and the reason is recorded rather than glossed:** the
operator interrupted the session and asked for a single review before the
end-of-session protocol. [`../../methodology/reviews.md`](../../methodology/reviews.md)
asks for three, and the earlier block of this session's work got them
([`2026-09-03-gates-and-windows.md`](2026-09-03-gates-and-windows.md)). This
covers only what happened after that review.

**Scope.** `HostInfo.cpuset` and its passthrough in `run.rs`/`envinfo.rs`/`main.rs`;
`check-snapshots.py` rule 6; `examples/verify.sh`'s two symbol helpers and the
two planted cases for them; `experiments/160-`; the tcmalloc dataset and its
README; the `preload` window's second restart; and README §2, §3, §3.1, §4.1.

## The lens: the claim audit

**"Which sentence am I about to publish that is not backed by an artefact I can
point at?"** - chosen over the other two because this block produced *numbers and
a dataset*, where the earlier block produced checks.  The door sweep and the
guard mutation both ran inline as the work happened (below), so the risk left
standing was a published claim, not an unswept caller.

###  It withdrew a finding I had already written the arithmetic for

`experiments/160-`'s first execution gave:

```
wander (A vs C, identical conditions) : 1.5% – 6.9%
effect (B vs the mean of A and C)     : 11.1% – 31.6%   (all one direction)
```

That separates cleanly, and it supports *"core count has a measured effect on the
size of each allocator's advantage"* - a genuinely new, quotable result for the
project's oldest untested hypothesis.

 **Instead of publishing it, the comparison was moved INTO the script and the
experiment re-run.** The second execution:

```
wander : 0.5% – 15.3%
effect : 6.4% – 33.2%
 The effect is NOT cleanly outside the wander, so this run separates
  neither, and no claim is made about magnitude either.
```

 **The separation did not survive one repeat, forty minutes later, on the same
host.** Had the first execution's table been written into the record - and it
was drafted - the project would have carried a false headline about its own
central question.

 **And the first execution's transcript is gone**, overwritten by the re-run, so
its numbers are **not citable** and none of them appear in
[`../todo/measurement.md`](../todo/measurement.md)'s T-025. What it
contributes is the methodological point, not data.

 **The generalisable lesson, and it is not "run things twice":** the wander was
being *sampled once* - a single A-vs-C difference - and a single difference is
not a spread. The work order's item 1 now says so.

###  Every published number re-derived from JSON

Not re-read from the prose that quoted it:

```
alpine  jemalloc rel=0.884 mad=1.2%   rpmalloc rel=0.900 mad=0.8%   mesh 1.251
debian  tcmalloc rel=1.266 mad=2.5%   jemalloc 1.004   rpmalloc 1.032
commit c13689af  dirty: False  cpuset: none  cpu: AMD EPYC 9V74
cell outcomes: {'ok': 15, 'unsupported': 1}
```

Every figure in the snapshot README, `docs/AGENTS.md` §5 and §13, README §3 and
§4.1, and T-003's closing section matches those.  The one that needed care was
README §3's *"mesh from `0.636×` to `1.251×`"* - the earlier draft said `1.232×`,
which is the **second** machine's value, not the third's.

###  And it caught a decision this session had made and defended

The earlier review recorded a *decision* to leave `examples/verify.sh` alone.
Re-reading the code rather than the argument showed `want_no_symbol` **failing
open**: "nothing found" is its passing answer, so an unreadable binary reported
*"the displaced allocator is gone"* with a  - in the layer whose whole subject
is negative controls, and ten lines below a header asserting the opposite.

 **Mutation-tested in a container** rather than argued: with the old pipe
restored, `want_no_symbol: a file nm cannot read  DID NOT REFUSE (pass=1 fail=0)`.
`pass=1` - it did not merely fail to refuse, it **actively passed**.

## What ran inline, and is recorded here rather than as its own pass

- **Door sweep.** `finish` was found by sweeping for `2>/dev/null | grep -q`
  after `finish_so` was fixed; `combine.py` and `rank.rs` by sweeping for the
  variant-blind key after `aggregate.py`; `examples/verify.sh` by the same grep.
   The sweep's own output is in the earlier review.
- **Guard mutation.** Every guard added in this block has a demonstrated firing:
  rule 6 has four planted cases; `verify.sh`'s fix has two and a mutation;
  `experiments/160-`'s magnitude guard **fired for real**, on the second
  execution, and is the finding above.

## What this pass did NOT find, and what would have had to be true

- **No fabricated number.** Every published figure traces to a committed
  `rankings.json` or `run.json`. For this to be wrong a number would have had to
  travel between documents without being recomputed - which is what the
  `1.232×`/`1.251×` slip above was, caught by recomputing.
- **No dataset published that should not have been.** The tcmalloc snapshot is
  `git_dirty: false`, `cpuset: none`, 0 validator errors.  The three
  `experiments/160-` datasets are **not** published and could not be: run B
  records `host.cpuset`, and rule 6 - written in this same block - would refuse
  it. The guard was tested against the tree it was written for.
-  **What a second pass would most likely have found**, had there been one: the
  `preload` window now holds a single run while three published datasets say more
  than it does. That is legal, argued and recorded - and it is a *coverage* gap a
  door sweep over "what does a reader of `results/rolling/` conclude?" would have
  pressed harder on than a claim audit did. It is work order item 4.
