# Final peer review, 2026-09-04

## Scope

This review covers the release tree, current documentation, committed datasets,
Linux execution path, CI, dependency automation, repository metadata, and the
allocator benchmark proposed for AWSIM. History files were checked for routing
but not treated as current guidance.

## AWSIM comparison

The reviewed
[AWSIM allocator benchmark patch](https://github.com/QaidVoid/awsim/compare/main...feat/allocator-benchmark.patch)
adds opt-in mimalloc and jemalloc builds plus an 836-line Bash/Python benchmark.
It measures six native HTTP workloads with `oha`, warm-ups, repeated medians,
separate load/server CPU sets, tmpfs scratch space, fresh servers, peak and idle
RSS, and rotated allocator order. Its fixed-request SQS case correctly avoids
giving a faster allocator more heap-growth work.

The useful controls already present here are fixed work, discarded warm-ups,
repeated medians, peak RSS, application-level correctness, and recorded host and
tool conditions. `alloc-bench` also adds scaled MAD, cross-run ranges, full
source revisions, dirty-tree state, image digests, independent dataset
validation, and exact allocator/link identity gates.

The AWSIM patch should not be copied as a general benchmark framework:

- allocator identity is a warning based on strings in a binary, so an unproven
  or wrong binary can still be timed;
- `--skip-build` checks only that executables exist, not their source, features,
  or hashes;
- a failed `/proc/<pid>/clear_refs` write is ignored, leaving warm-up memory in
  `VmHWM`; value 5 is valid on supporting Linux kernels, but failure must be
  recorded or fatal;
- cells with request errors still contribute to the geometric-mean summary;
- “fastest overall” combines unlike workloads and concurrency levels without a
  validity or stability gate;
- provenance omits full commits, dirty-tree state, binary hashes, allocator
  revisions, and the load-generator version;
- build, execution, parsing, and reporting share one script with no schema,
  independent validator, fixture, or CI selftest.

Rotating allocator order is the one material control not implemented here.
`alloc-bench` builds and measures inside one cell container, so equivalent
counterbalancing requires a separate build phase rather than a superficial
shuffle. The current deterministic whole-cell order is now stated in
`docs/methodology.md` as a limitation.

No hour-long AWSIM run was needed: these findings follow from its control flow,
failure handling, metadata, and report equations.

## Project review

| Area | Evidence | Result |
| --- | --- | --- |
| repository | one parentless release commit; only the new remote; default Git identity | pass |
| retired paths | no runtime, build, test, or documentation dependency on the removed reference corpus or root TODO/HISTORY paths | pass |
| current guidance | README and `docs/` routes have one owner per subject; history is explicitly non-authoritative | pass |
| identity and correctness | positive and negative allocator evidence, link-kind checks, preload residency, deterministic oracle, exit/count checks | pass |
| measurement | fixed work, warm-ups, `CLOCK_MONOTONIC`, per-child `wait4`, medians, scaled MAD, timeouts, failed-sample exclusion | pass with the order limitation above |
| dataset integrity | 325 imported result JSON files retained the source tree's structure and numeric values; snapshot and aggregate checkers cover published and rolling data | pass |
| reproducibility | full source pins, toolchain pins, build flags, image identity, host data, corpus seed, commit and dirty-tree state | pass |
| security | no credential patterns found; workflow permissions are read-only except the rolling write job; third-party actions use full commit SHAs | pass |
| CI | Rust format, clippy, tests, shell parsing, ShellCheck, actionlint, document links, snapshot/evidence selftests, aggregates, and container smoke | pass |
| repository operations | Dependabot covers Cargo and Actions; `main` rejects force-pushes and deletion while administrators retain bypass | pass |

## Findings closed

1. The README exposed many datasets without naming a primary route. It now
   points to the broad rolling aggregate, its latest complete snapshot, and a
   scoped allocator shortlist.
2. Whole-cell execution order was discoverable only from code and `plan.json`.
   The methodology now states its consequence for slow host drift.
3. Runtime detection used Docker's `.ServerVersion` template for Podman too.
   Podman 5.8.6 rejects that field. Detection now reads `info --format json`,
   accepts Docker and Podman version schemas, and tests both.
4. Four experiment scripts lack executable bits, but the documented and tested
   interface is `sh experiments/<name>.sh`; this is consistent with the
   non-executable build helpers and is not a functional defect.

No release-blocking finding remains. The remaining limits are properties of the
evidence: ripgrep is not a service workload, aarch64 has one current run, cells
are not counterbalanced, and two Wolfi allocator builds in the broad snapshot
failed and remain visible rather than being ranked.
