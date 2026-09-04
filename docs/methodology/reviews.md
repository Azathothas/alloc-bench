# Reviews

Review correctness before style.

1. Confirm the changed code preserves the invariants in `docs/AGENTS.md`.
2. Trace configuration through planning, execution, metadata, validation, and
   reporting.
3. Check failure paths: unsupported, build failure, missing measurement,
   unproven identity, and emulation.
4. Verify that comparison groups do not cross libc, distribution,
   architecture, profile, toolchain, or link kind.
5. Confirm generated files match their generators and published datasets are
   not silently rewritten.
6. Run the gate and any required container smoke test.

Report a finding with its path, consequence, and a reproducible trigger. Keep
preference-only comments separate from correctness issues.
