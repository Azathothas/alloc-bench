# The pre-cleanup image caveat

**Retired 2026-09-01** by re-running `core` from a current image.

 **This is history.** No document needs to carry the caveat any more, and the
finding that replaced it - the ranking does not transfer between machines - is in
`docs/AGENTS.md` §11.1.

---

## What the caveat said

The published `core` and `mechanisms` datasets came from an image built **before**
the clippy and dead-code cleanup (`f7a46b5`), so they did not correspond to
current `HEAD`, and every number in them carried an unquantified doubt about
whether the tree that produced them was the tree being documented.

## The superseded wording, from `docs/AGENTS.md` §13, kept verbatim

>  **RESOLVED: the pre-cleanup image caveat.** It used to read that the
> published `core` and `mechanisms` datasets came from an image built **before**
> the clippy/dead-code cleanup (`f7a46b5`) and so did not correspond to current
> `HEAD`. `core` has now been re-run from a `194ed63` image
> (`results/published/2026-09-01-core-x86_64-run-b/`) and the answer is direct:
> **five of the six ripgrep binaries are byte-identical across the two images**,
> the sixth (jemalloc) differing by 1496 bytes in an autotools build that embeds
> build-time strings. The cleanup did not change what was measured, and the
> question no longer needs to be asked from prose.
>
>  **What the re-run found instead is worse, and it is in §11.1.** `core` has now
> been measured on three CPUs and all three disagree - the GitHub runner *inverts*
> the ranking while reporting the tightest noise of the three. The problem was
> never the image. **The answer is a property of the machine.**

##  What this cost, and what it bought

The caveat sat in the handoff for several commits as prose nobody could act on.
Retiring it took **one re-run** and produced a byte-comparison anybody can check.

 **The lesson is not "the caveat was wrong"** - it was a correct statement of an
unverified doubt. The lesson is that a doubt expressed in prose stays expensive
until somebody converts it into a command. This one converted into
`cmp` over six binaries.

 **And the re-run found something the caveat was hiding.** The doubt about the
image was absorbing attention that belonged to a much larger problem: the same
suite on a different CPU inverts its ranking. A caveat that is cheap to retire
should be retired, because until it is, it is the thing everyone looks at.
