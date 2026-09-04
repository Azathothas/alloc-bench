# `bench.yml` would not register

**Resolved 2026-09-01.** Kept because a workflow with no `push` trigger can hit
this again, and re-deriving it costs about an hour.

 **This is history, not a live constraint.** `bench.yml` is registered
(workflow id `347273098`) and dispatches normally. Nothing here needs acting on
today.

---

## The superseded wording, from `docs/AGENTS.md` §13, kept verbatim

>  **RESOLVED: `bench.yml` would not register, and a push that modifies the file
> fixed it.** For two pushes it was absent from `GET /actions/workflows` and
> `POST .../workflows/bench.yml/dispatches` returned 404 - it was the single thing
> between this repository and an aarch64 number. Adding a comment to the file
> registered it (workflow id `347273098`) and dispatch succeeded immediately
> after.  The `on:` block was never changed; **the fix was touching the file, not
> editing its triggers.** Keep the investigation below - a workflow with no `push`
> trigger can hit this again, and re-deriving it costs an hour:
>
> | hypothesis | checked | result |
> | --- | --- | --- |
> | the file was never pushed | `git ls-tree -r origin/<branch> -- .github/` | present |
> | it is not valid YAML | `yaml.safe_load` | parses |
> | it violates GitHub's workflow schema | validated against `json.schemastore.org/github-workflow.json` | **0 errors**; `ci.yml` scores the same |
> | it is not on the default branch | repo API `default_branch` | it is (**the default branch is this feature branch**) |
> | the repo is private / Actions disabled | repo API `private`, and `ci.yml` runs | public, Actions work |
>
> What is left is GitHub-side registration: `ci.yml` has a `push` trigger and was
> registered by the first push, while `bench.yml` has only `schedule` +
> `workflow_dispatch` and had not been indexed as of two pushes in.  **Do not
> "fix" the file** - it is valid, and editing it on a guess will cost a later
> session the same hour. Re-check `list_workflows` first; if it still has not
> appeared after a further push or after the weekly `schedule` first fires, the
> next thing to try is the Actions UI (which sometimes forces indexing) or adding
> a temporary `push` trigger on a throwaway branch to make GitHub register it.

## The correction, written underneath

 **One row of that table has since stopped being true, and it is worth saying
because the wording invites a wrong inference.** "the default branch is this
feature branch" described the repository in the middle of a branch migration. The
default branch is now `main`, verified by both `git remote show origin` and the
repository API. The hypothesis it recorded - *is the workflow on the default
branch* - was ruled out correctly either way; only the parenthetical is stale.

 **What still transfers.** The diagnosis held: registration is GitHub-side, and
a workflow whose only triggers are `schedule` and `workflow_dispatch` may not be
indexed until a push modifies the file itself. That is the reusable finding.

 **The last sentence recommends a throwaway branch.** `docs/history/todo/RULES.md` §2 now
governs that: such a branch is named `ephemeral-*`, is deleted in the same
session, and  a session cannot delete a remote ref itself (HTTP 403, measured),
so the operator has to. Prefer touching the file on `main`, which is what
actually worked here.
