# Rules

How **this** repository is worked on. [`PROGRESS.md`](PROGRESS.md) is the record
and carries the work order; this file is the part that does not change between
sessions.

 **Everything general is a link.** The rows below name where each rule lives,
and following the link is how you read it. Nothing here restates them.

| topic | where it lives |
| --- | --- |
| what a session owes at its start and its end | [`docs/methodology/sessions.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/sessions.md) |
| the kickoff and resume prompts, and the summary table | the same file |
| what a unit of work passes before it is done | [`docs/methodology/gate.md`](../../methodology/gate.md) |
| the three deep-review lenses | [`docs/methodology/reviews.md`](../../methodology/reviews.md) |
| how an entry is authored before it is filed | [`docs/methodology/authoring.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/authoring.md) |
| the todo model itself | [`docs/methodology/work-todo.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/work-todo.md) |
| commit identity, and what may reach a remote | [`docs/conventions/git.md`](../../conventions/git.md) |
| anything outside this machine | [`docs/security/remote-ops.md`](../../security/remote-ops.md) |
| how documents are written, and the    markers | [`docs/conventions/prose.md`](../../conventions/prose.md) |
| where superseded wording goes | [`docs/methodology/history.md`](../../methodology/history.md), and [`docs/history/`](../) |
| what this project is, and its status | [`docs/AGENTS.md`](../../AGENTS.md) |

---

## 1. This project's specifics

| | |
| --- | --- |
| the record | [`PROGRESS.md`](PROGRESS.md) and [`INDEX.md`](INDEX.md) |
| the one command that runs every host-side gate | `sh scripts/gate.sh` |
| the record's own checker | `python3 scripts/check-todo.py` |
| the host probe | `./target/release/alloc-bench doctor` |
| the instrument's self-check | `./target/release/alloc-runner selftest` |

 **Re-measure the baseline rather than trusting the recorded one**, with
`sh scripts/gate.sh`, before touching anything. The numbers in
[`PROGRESS.md`](PROGRESS.md) were true when they were written and that is all
they claim.

 **`scripts/gate.sh` is the host half only.** It does not build a container
image and it measures nothing. The container half is
`alloc-bench run --suite smoke --arch x86_64 --strict`, which needs Docker or
Podman; run it when the change touches the pipeline, and say in the record when
you could not.

---

## 2. Git, for this project

 **Never push to a branch other than `main`.**

`main` is the default branch and carries the entire history. Work goes directly
onto it.

 **Where a throwaway branch is genuinely needed** - bisecting, a
force-registration trick for a workflow, an experiment you intend to discard -
it is named `ephemeral-<what-it-is>` and **deleted in the same session that
created it**. Nothing named `ephemeral-*` may outlive the session, and nothing
named `ephemeral-*` is ever merged: land the work on `main` as an ordinary
commit instead.

**What it cost to learn, and it is two separate costs.**

 **First: branch sprawl.** The work was developed on
the prior allocator-benchmarking branch, migrated to `main`, and left
behind that branch plus `backup/pre-main-migration-2026-09-01`. Both then had to
be deleted by a person, because a session token cannot delete a ref (below). A
later session opened a second branch for a documentation review and merged it as
[PR #1](https://github.com/Azathothas/alloc-bench/pull/1).  **The residue is a
document that dates itself to a commit no longer reachable from `main`**: the
handoff recorded its own vintage as `e24709b`, the head of that merged branch,
and after the squash `git cat-file -t e24709b` answers *"Not a valid object
name"*. A reader trying to establish which tree the document describes cannot.
Working on `main` makes that failure unrepresentable.

 **Second: a session cannot clean up after itself.** Two ref operations were
attempted during the migration and **refused with HTTP 403**: pushing an
annotated tag, and `git push --delete` of a branch. Branch *create* and *update*
work - that is how `main` got there.  **So a session can create a branch it
cannot remove.** That is the whole argument for the `ephemeral-` rule: if you
cannot delete it from here, do not create it without a name that says out loud
it is rubbish, and ask the operator to remove it before the session ends.

 **Every push runs CI.** `.github/workflows/ci.yml` triggers on
`push: branches: ["**"]`, so a throwaway branch spends a runner on three jobs
including a full container build. That is a second reason not to create one
casually.

Everything else - commit identity, what may reach a remote - is
[`git.md`](../../conventions/git.md) and
[`remote-ops.md`](../../security/remote-ops.md).

---

## 3. The tools this project has

 **Reach for the purpose-built tool before the general one.** A general tool
used where a specific one exists produces answers that are plausible and wrong,
which is the hardest kind to catch.

| question | tool |
| --- | --- |
| can this host run the benchmark | `./target/release/alloc-bench doctor` |
| read anything from the GitHub API | `curl -sS https://api.gh.pkgforge.dev/<GH_API_PATH>`, or `gh` where authenticated - below |
| fetch any other URL that refuses you | `curl -sS https://api.rv.pkgforge.dev/<FULL_URL_WITH_SCHEME>` - below |
| is the instrument itself sound | `./target/release/alloc-runner selftest` |
| is the host-side tree green | `sh scripts/gate.sh` |
| does the record agree with itself | `python3 scripts/check-todo.py` |
| an entry closed, so the counts must move | `python3 scripts/check-todo.py --write`.  Never retype a count. |
| does every documented link resolve | `python3 scripts/check-docs.py` |
| does every published dataset still carry its conditions | `python3 scripts/check-snapshots.py` |
| what actually failed in this cell, and is the published extract still honest | `python3 scripts/report/extract-evidence.py --run … --out …` / `--check … --expect …` |
| which symbols does this archive reference and never define | `alloc-runner ar-unresolved --archive … --symbols …` |
| what does this binary actually contain | `alloc-runner identify --bin … --expect-allocator … --expect-kind …` |
| did the surgery displace anything | `alloc-runner archive-check --archive … --symbol malloc --expect-providers 1` |
| is a dataset trustworthy | `alloc-bench validate --run DIR` |
| what has held across machines | `results/rolling/<suite>-<arch>/aggregate.md` |
| fold a new run into the window | `python3 scripts/report/aggregate.py --window results/rolling/<w> --add DIR` |
| is the aggregator itself sound | `python3 scripts/report/aggregate.py --selftest` |
| what would this suite run | `alloc-bench plan --suite … ` |

 **Every exit code above is read from the process that produced it, unpiped.**
[`shell.md`](../../conventions/shell.md) section 2 says what that costs when it
is not.

### Reaching GitHub and the wider network

 **Read-only GitHub API: use `https://api.gh.pkgforge.dev/<GH_API_PATH>`.**
Same paths, same JSON, no credentials.

```sh
curl -sS "https://api.gh.pkgforge.dev/repos/Azathothas/TEMPLATE/contents/docs/methodology?ref=main"
```

 **Prefer the `gh` CLI where it is available and authenticated.** It is **not**
available in the earlier remote environment - `command -v gh` finds nothing -
so there the mirror is the route. Where a GitHub **MCP** server is attached, its
tools are also fine and are what this session used for Actions data.

 **Not for GraphQL, and not for anything authenticated or write-shaped.**
Discussions are GraphQL-only, so a credential-free route cannot reach them; when
`PROVENANCE.md` records them as skipped that is a real gap.
[`remote-ops.md`](../../security/remote-ops.md) still governs what may be
written anywhere, and the answer is nothing.

 **Any other fetch: use `https://api.rv.pkgforge.dev/<FULL_URL_WITH_SCHEME>`**
- the whole URL including `https://` - **unless the source already works.** If a
direct fetch succeeds, keep it; reach for the mirror when it 401s, 403s, or is
otherwise refused.

```sh
curl -sS "https://api.rv.pkgforge.dev/https://raw.githubusercontent.com/OWNER/REPO/refs/heads/main/FILE"
```

**What it cost to learn.** This session opened by asking
`api.github.com/repos/Azathothas/TEMPLATE/contents/docs/methodology` for a
directory listing and got

```
{"message":"GitHub access to this repository is not enabled for this session..."}
```

 **That is the environment's egress policy, not a missing repository**, and the
message does not say so. The session then spent a `git clone` getting what one
request would have answered. Verified 2026-09-01: the same path through
`api.gh.pkgforge.dev` returns the 15-entry listing immediately, and
`api.rv.pkgforge.dev` fetches the raw files.

---

## 4. The rules that bite most often, here

### The record is part of the change

 [`PROGRESS.md`](PROGRESS.md), [`INDEX.md`](INDEX.md) and the entry are edited
in the **same change** as the work, never after it. A session that fixes
something and leaves the record saying it is open has not finished; it has
published something false into the one file the next session reads first.

 **Enforced rather than remembered:** `python3 scripts/check-todo.py` runs in
`.github/workflows/ci.yml`, so a count that disagrees with the rows cannot reach
a green build.

###  Never weaken a check to get green

If the identity oracle rejects a cell, **the cell is wrong, not the oracle.**

**What it cost:** the first aarch64 dispatch built six cells and the oracle
rejected all six, because `static-pie` does not exist on aarch64 musl. Relaxing
the check would have published six plain-static binaries under a `static-pie-lto`
label - the exact failure the oracle exists to prevent, and the failure this
project was built against after finding it in the prior art. The entry is
[`T-002`](platform.md#t-002-decide-what-core-does-on-aarch64).

###  Never fabricate a number, and never let one lose its conditions

A dash where the value is unknown. A machine named beside every ratio.

**What it cost:** run A of the `mechanisms` suite was published with its
`rankings.json` and **without its `run.json`**. Its CPU is therefore unrecorded,
and a later session trying to establish whether runs A and B were the same host
- which decides whether a 20% disagreement is run-to-run wander or a property of
the machine - **cannot answer the question the snapshot was kept for.** The entry
is [`T-012`](instrument.md#t-012-a-published-snapshot-must-carry-its-own-conditions).

###  A failed or unsupported configuration is published, with its reason

Silently dropping it is the failure this project is built against. CI fails on
any unsupported cell that carries no reason.

###  Nothing closes as "won't fix", "upstream's problem" or "out of scope"

A blocked entry stays open with the blocker named and what would unblock it.

 Where the blocker is code this project vendors, the answer is to patch it here:
[`vendoring.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/vendoring.md), which also settles that
upstreaming is not a topic in this repository.

###  Run `sh scripts/gate.sh --strict` before pushing, not `gate.sh`

A skipped check is not a passed check, and the plain gate is allowed to skip.

**What it cost, on the very commit that added the gate.** `shellcheck` was not
installed on the dev host, so `gate.sh` printed
`SKIP (shellcheck not installed)` - correctly - and the push went out anyway. CI
has shellcheck installed on purpose, ran it, and **failed on `SC2044` in
`gate.sh` itself**: `for f in $(find …)` is a warning-level finding. The two new
record checks in the same job were then **skipped**, so the commit that
introduced them proved nothing about them.

 **`--strict` turns a skip into a failure**, which is what CI passes and what a
push should have to pass. Where a tool genuinely cannot be installed, say so in
[`PROGRESS.md`](PROGRESS.md) rather than pushing past it.

###  Never record a capability as absent without the probe's output

A missing tool, a dead endpoint, an unreachable daemon: each is a **measurement**
and each has a command.  Write the command's output, or write nothing.

**What it cost, and it is the worst mistake of the session that wrote this
file.** A session recorded *"No Docker or Podman daemon was reachable, so
`alloc-bench doctor`, the image build and the `smoke` suite were **not run**"*
into `PROGRESS.md` as a measured baseline. **It never ran the probe.**

The truth, when the operator finally challenged it: the client was installed
(`docker 29.3.1`), the daemon was simply not started, and
[`containers.md`](../../containers.md) documents that exact case - *"client is
there, daemon is not running"* - with the fix, in a section that says in as many
words that this is **where this project was actually developed**:

```sh
sudo dockerd >/tmp/dockerd.log 2>&1 &
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
```

One command later: `alloc-bench doctor: 0 problem(s).`

 **The damage was not the wrong sentence, it was everything scoped around it.**
The session wrote a work order for an *unattended* successor claiming only ~2.0
of 6.5 L-equivalents were reachable "without a runtime", naming five entries as
out of reach. A session that trusted it would have skipped work it could have
done, and would have had no reason to doubt a line that looked measured.

 **This is the exact failure `sessions.md` names - "a wall is a routing problem,
not a verdict" - committed by the session that mirrored that file into this
repository the same day.** Reading a rule is not holding it.

 **Enforced rather than remembered:** `sh scripts/gate.sh` now runs
`alloc-bench doctor` and prints its verdict on every gate run, so the runtime's
state is a line of output rather than something a session believes.

###  Read every exit code from the process that produced it, unpiped

Not a style preference - the same session broke this twice in an hour.

**What it cost.** `./target/release/alloc-bench doctor 2>&1 | tail -20; echo $?`
printed **0** while `doctor` had returned **2**. `$?` was `tail`'s. The session
read that as "doctor passed", which reinforced the wrong conclusion above.

```sh
alloc-bench doctor > /tmp/out 2>&1; rc=$?    #  the real code
alloc-bench doctor | tail -20; echo $?       #  tail's code
```

[`shell.md`](../../conventions/shell.md) section 2 is the general rule.  A
guard piped into anything reports the pipeline's status, so **a guard that failed
reads as green.**

###  Delete the allocator cache after editing a recipe

The cache key covers allocator, commit, mode, PIC, libc, architecture, toolchain
and variant - **not the recipe's contents**.

```sh
rm -rf .cache/<distro>-<arch>/alloc
```

**What it cost:** two of this project's early diagnoses were spent on stale cache
entries, both of them looking like "the change had no effect".

###  A within-run MAD is a floor on the uncertainty, not a bound

**What it cost:** the same comparison run twice on the same host moved 20% while
every cell reported a 1.6–2.9% internal MAD. Publishing "13.1% faster, outside
the run's 2.7% spread" would have been wrong about the number while right about
the ordering. Publish the direction; name the machine; run the control twice.

 **The RULE stands; the FACTOR behind it does not, and the difference matters.**
Measured 2026-09-03 over **ten** `core` runs on one machine, with the machine
asserted from every run's own `run.json`: the between-run MAD is **0.8–2.1%**
against within-run MADs of **3.9–4.8%** - the run-to-run spread is *smaller*.
The 20% above came from **two** samples of a different suite on a host
[`../../AGENTS.md`](../../AGENTS.md) §12 item 11 admits it cannot confirm was
one host.

 **So do not quote a factor, and keep the caution.** It is kept rather than
weakened for two reasons: one machine's ten runs do not license a claim about
every machine - which is this project's whole finding - and a caution that costs
nothing when wrong is not the kind of check to relax.
[`../../../experiments/170-how-much-does-one-host-wander.sh`](../../../experiments/170-how-much-does-one-host-wander.sh).

---

## 5. The end-of-session protocol

 **This is what "run the end protocols" means.** A kickoff prompt names it; it
does not restate it. The general specification is
[`sessions.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/sessions.md); what follows is the concrete
form for **this** repository, in order.

 **Run it when the operator interrupts, when the target is met, or when budget
runs out - never as a reason to stop early.** "Ran out of budget" is a reason;
omitting the protocol is not an option.

1. **Finish or checkpoint the in-flight entry.**  Never leave a half-edit across
   the boundary: the next session cannot tell it from finished work. A partial is
   recorded as `partial` with the correction written underneath, per
   [`work-todo.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/work-todo.md).

2. **Run the gate.**

   ```sh
   sh scripts/gate.sh --strict
   ```

    Plus the container half where a runtime exists -
   `alloc-bench run --suite smoke --arch x86_64 --strict`. Where it does not,
   say so in the record; a skip is not a pass.

3. **Three deep reviews, three different questions.**
   [`reviews.md`](../../methodology/reviews.md).  Three headings over one
   sweep is not three passes. Write them to
   `docs/history/reviews/<date>-<topic>.md`, saying per pass what it swept that
   the others did not, and - for a pass that found nothing - what would have had
   to be true for it to fire.

4. **Update the record in the same change as the work**: the entry, then

   ```sh
   python3 scripts/check-todo.py --write   # never retype a count
   python3 scripts/check-todo.py
   ```

   and rewrite [`PROGRESS.md`](PROGRESS.md) whole - state line with the start
   instant, measured baseline, what this session did, **every premise a
   measurement disproved**, what is in progress, the work order, open questions.

5. **Squash to one commit and push to `main`.**

   ```sh
   git reset --soft <base> && git commit && git push origin main
   ```

    `main` only. Nothing named `ephemeral-*` survives the session.

6. **Verify CI on the pushed head**, through
   `https://api.gh.pkgforge.dev/repos/Azathothas/alloc-bench/actions/runs`.  A
   red job is not "done"; fix it and push again.

7. **Print the summary table in chat.** One markdown table, every cell grounded
   in something you can point at, with before **and** after.  It must be able
   to say nothing moved.

8. **Print the next kickoff prompt in chat only**, in a fenced block.  Never
   into a file, and it carries **no** work order - that is
   [`PROGRESS.md`](PROGRESS.md)'s, where it is already correct.

---

## 6. Settled decisions, not to be relitigated

- **The work model is todo, not stage.** Ruled 2026-09-01. The tree already
  exists and the outstanding work is a set of independently orderable items, not
  a forced sequence - which is exactly the test in
  [`choosing-a-work-model.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/choosing-a-work-model.md).
- **Development happens on `main`.** Ruled 2026-09-01. Section 2, with the two
  incidents behind it.
- **Allocator-internal LTO is off for every allocator**, so that dimension is
  constant. LTO is measured as an *application* build profile instead.
- **`strip=none` on every build.** A stripped binary has no `.symtab`, so the
  identity oracle reports UNPROVEN rather than clean, and this project does not
  time what it could not identify.
- **Emulated timings are recorded and excluded from ranking.** An allocator
  comparison under user-mode emulation measures the emulator too.
- **Upstreaming is not a topic.** Vendored code is fixed here.
  [`vendoring.md`](https://github.com/Azathothas/TEMPLATE/blob/main/docs/methodology/vendoring.md).
