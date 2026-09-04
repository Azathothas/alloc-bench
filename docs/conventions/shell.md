# Shell

Shell scripts target POSIX `sh` unless a file declares another interpreter.

```sh
#!/bin/sh
set -eu
```

- Quote substitutions unless intentional splitting is documented.
- Use `printf`, not `echo`, for data.
- Pass paths after `--` where supported.
- Preserve a command's exit status when capturing or filtering output.
- Send machine-readable output to stdout and diagnostics to stderr.
- Use temporary directories with cleanup traps.
- Validate destructive targets as absolute paths inside the intended work area.
- Use NUL-delimited paths when filenames may contain whitespace.
- Keep scripts non-interactive in CI and bound every retry or wait.
- Store repository text with LF line endings.

Use `shellcheck` and `sh -n` for changed scripts. Run Linux-only scripts in the
same container environment used by the benchmark.
