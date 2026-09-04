# Remote operations

Remote changes require an explicit repository and action.

- Inspect the authenticated account and destination URL before pushing.
- Push only the branch or tag requested by the task.
- Do not force-push, delete refs, change protection rules, or alter repository
  settings without specific authorization.
- Give workflows read-only permissions unless a job must write.
- Pin third-party actions to immutable revisions.
- Do not run privileged containers or mount host credentials into benchmark
  images.

After a push, check every required workflow and report the failing job and log
URL if any job is not green.
