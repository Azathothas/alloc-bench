# Code

- Prefer the smallest change that preserves explicit contracts.
- Keep orchestration, measurement, parsing, and reporting separate.
- Use typed errors and include the failing path, cell, or command in messages.
- Represent missing measurements as missing values, never zero.
- Validate transformed source and binary identity before benchmarking.
- Centralize shared policy such as support checks and path construction.
- Treat unsupported configurations as recorded outcomes, not hidden rows.
- Add a regression test for every fixed parsing, validation, or ranking defect.
- Avoid commented-out code, speculative abstractions, and dependencies that do
  not remove more complexity than they add.

Run formatting, linting, unit tests, and the checks appropriate to the changed
execution path.
