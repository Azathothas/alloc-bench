# Documentation

Each fact has one current owner. Other documents link to it instead of copying
it.

| Subject | Owner |
| --- | --- |
| project entry point and findings | `README.md` |
| maintenance routes and invariants | `docs/AGENTS.md` |
| measurement design | `docs/methodology.md` |
| allocator builds and integration modes | `docs/allocator-integration.md` |
| dataset interpretation | `docs/results.md` |
| completed work and corrections | `docs/history/` |

Keep current guides procedural and history-free. Use relative links for files
inside the repository, verify every link, and name exact paths and commands.
Generated reports must identify their generator and must not be edited by hand.

When behavior changes, update the owning guide in the same commit. Archive a
superseded claim only when its context remains useful.
