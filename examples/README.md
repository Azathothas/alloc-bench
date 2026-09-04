# Examples

These scripts demonstrate allocator replacement and verify the resulting
artifact or process. They do not benchmark performance.

```sh
sh examples/run.sh       # all examples
sh examples/run.sh 30    # one numbered example
```

Exit 0 means every check passed, 1 means a check failed, and 2 means the example
could not run. Docker or Podman and network access are required. Captured output
is committed under `examples/out/`.

| Script | Environment | Demonstrates |
| --- | --- | --- |
| `10-debian-preload.sh` | Debian/glibc | packaged allocator through `LD_PRELOAD` |
| `20-ubuntu-preload.sh` | Ubuntu/glibc | source-built mimalloc through `LD_PRELOAD` |
| `30-alpine-static-pie.sh` | Alpine/musl | `libc.a` replacement and static-PIE |
| `40-void-musl-static.sh` | Void/musl | replacement on a second musl distribution |
| `50-archlinux-glibc.sh` | Arch/glibc | preload and the reason static replacement is unsupported |
| `60-chimera-musl.sh` | Chimera/musl | refusal when libc already has allocator-specific coupling |

`verify.sh` checks ELF kind, allocator symbols, displaced symbols, preload
residency, execution, known-answer counts, and ASLR. `verify-selftest.sh` gives
each check passing and failing inputs. `allocprobe.c` exercises allocation,
alignment, zeroing, concurrency, and known-answer search behavior.

`musl-libc-surgery.sh` is a readable demonstration for mimalloc. The production
implementation in `scripts/build/libc-surgery.sh` additionally derives and
supplies approved musl-internal aliases for compatible C allocators.

See [`../docs/replacing-the-allocator.md`](../docs/replacing-the-allocator.md)
for deployment guidance and [`../docs/results.md`](../docs/results.md) for
measurements.
