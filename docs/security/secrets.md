# Secrets

This project does not require repository secrets for normal builds or pull
request checks.

- Use the workflow-provided `GITHUB_TOKEN` with the narrowest job permissions.
- Never print tokens, credentials, authenticated URLs, or complete environment
  dumps.
- Do not pass secrets to builds from untrusted pull requests.
- Keep local credential files, `.env` files, caches, and runtime sockets out of
  Git.
- Treat third-party source archives and container images as untrusted input;
  verify pinned revisions and digests before use.

If a future workflow needs a secret, document its purpose, owner, scope,
rotation procedure, and trusted trigger before adding it.
