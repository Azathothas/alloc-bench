# Troubleshooting

Start with the cell's `reason`, then `steps.log`.

| Outcome | Meaning |
| --- | --- |
| `ok` | built, identified, passed correctness, and measured |
| `unsupported` | excluded by a documented technical constraint |
| `build_failed` | an attempted build failed |
| `identity_failed` | the artifact does not prove the requested configuration |
| `correctness_failed` | the subject returned a wrong result or status |
| `measurement_failed` | no workload produced a usable sample |

Cell files live under `results/<run>/cells/<cell-id>/`. `build.json` records
inputs, `identity.json` records ELF and allocator evidence,
`correctness.json` records oracle checks, and `measure-*.json` contains samples.

## Identity failures

`no symbol evidence of <allocator>` means the archive did not reach the link or
the identity signature is incomplete. Check the recorded link flags and the
binary with `nm`. Add a signature only when it is unique to that allocator and
the displaced libc signature is absent.

`binary has no .symtab` means the artifact was stripped. Restore
`CARGO_PROFILE_RELEASE_STRIP=none`; inability to inspect is not evidence of
absence.

`replacement build still contains ... libc allocator` means the splice failed
or a negative signature is not unique. Never relax the check or accept multiple
definitions.

`baseline binary contains candidate allocator` means the control is
contaminated. Rebuild the image and confirm patched archives did not persist
between cells.

## Build failures

- Duplicate `malloc`, `free`, or `__libc_*` symbols are the expected failure of
  some `link-override` cells. Do not use `--allow-multiple-definition`.
- Missing `stdc++` requires the recipe to locate the archive with
  `$CXX -print-file-name=libstdc++.a`.
- Duplicate C++ allocation operators require removing the allocator's operator
  object or disabling its C++ API.
- A bare architecture token on a compiler line can come from GNU make's
  built-in `TARGET_ARCH`; clear it on the make command line.
- Autoconf failure to run a C program in a PIC-disabled build may be a default
  PIE conflict. Inspect `config.log` and pair `-fno-PIE` with `-no-pie`.
- TLS certificate failures require a trusted CA in `images/extra-ca/`, never
  disabled verification.
- A successful rebuild with unchanged behavior may be a stale allocator cache;
  remove the affected cache after recipe edits.

## Correctness failures

Uniform off-by-one counts usually mean metadata was placed inside the searched
corpus. A `-j1` and `-j4` disagreement is a concurrency defect and must not be
retried into a pass. Equal case-sensitive and case-insensitive counts indicate
an ignored option or a broken corpus oracle.

## Empty or noisy results

Use absolute bind-mount paths for manual container runs. A relative source may
become an unrelated named volume. A ranking requires an `ok` control and at
least one comparable candidate.

A `noisy` warning means the relative MAD exceeds the configured threshold. Use
more repetitions, a larger corpus, or a quieter host. The smoke corpus is for
pipeline validation and cannot support fine rankings.

## Diagnostic commands

```sh
./target/release/alloc-bench validate --run results/local/<id>
alloc-runner identify --bin ./rg --expect-allocator mimalloc --expect-kind static-pie
alloc-runner archive-check --archive /usr/lib/libc.a --symbol malloc --expect-providers 1
alloc-runner ar-members --archive /usr/lib/libc.a --symbols malloc,free
alloc-runner selftest
```

Run one cell interactively as described in [`containers.md`](containers.md).
