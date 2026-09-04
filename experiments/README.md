# Experiments

Numbered scripts answer bounded questions outside the main benchmark. Numbers
are never reused because documentation and captured output cite them. Exit 0
means the probe ran and passed, 1 means it ran and observed the asserted failure,
and 2 means it could not run.

| Script | Question |
| --- | --- |
| `10-probe-host.sh` | Can the host run the benchmark, and what are its conditions? |
| `20-base-image-arch-support.sh` | Which architectures do target images publish? |
| `30-ripgrep-default-allocator.sh` | Which allocator does unmodified ripgrep use on musl? |
| `40-allocator-build-matrix.sh` | Do declared allocator modes produce the required artifact or an explicit unsupported result? |
| `50-libc-surgery-verify.sh` | Does a musl archive splice displace the original allocator? |
| `60-static-pie-aslr.sh` | Do claimed PIE profiles randomize at runtime? |
| `70-aarch64-static-pie.sh` | Can the stable aarch64 musl Rust target produce static-PIE? |
| `80-rolling-window-commit-guard.sh` | Does CI detect a newly created rolling window? |
| `90-preload-residency.sh` | Can preload verification distinguish mapped, absent, and wrong-path libraries? |
| `100-mesh-artefacts.sh` | Where does Mesh place its built shared object? |
| `110-chimera-ar-mri.sh` | What does Chimera's musl archive contain and why is replacement refused? |
| `120-stranded-on-a-real-libc.sh` | Does unresolved-symbol derivation accept Alpine and reject Chimera? |
| `130-libc-surgery-after-the-guard.sh` | Does the production guard preserve a valid archive and leave a refused archive untouched? |
| `140-gate-sees-a-skip-below.sh` | Does the strict gate propagate nested skips? |
| `150-symbol-reads-tell-their-states-apart.sh` | Do export checks distinguish empty output from inspection failure? |
| `160-does-core-count-explain-it.sh` | Does core count alone explain a ranking change on one host? |
| `170-how-much-does-one-host-wander.sh` | How much does repeated ranking vary with no intentional input change? |
| `180-which-file-did-the-recipe-take.sh` | Does artifact selection choose a loadable shared object rather than a similarly named build file? |

Each script records host, tools, date, and relevant inputs in
`experiments/out/<name>.txt`. A one-host observation is scoped to that host.
Reusable checks belong in tests or `scripts/gate.sh`; investigation history
belongs under `docs/history/`.

```sh
sh experiments/10-probe-host.sh
```

Scripts resolve repository paths from their own locations.
