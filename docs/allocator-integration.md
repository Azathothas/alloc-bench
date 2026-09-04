# Allocator integration

Allocator policy lives in `allocators/allocators.toml`; pinned revisions live
in `allocators/allocators.lock.json`; build behavior lives in
`allocators/<id>/build.sh`. The scripts are authoritative when this guide and a
recipe disagree.

## Mechanisms

| Mechanism | Scope | Output |
| --- | --- | --- |
| `rust-global` | Rust allocations in a rebuilt application | prefixed static archive linked through `rgalloc-shim` |
| `libc-surgery` | every later static link against a patched musl `libc.a` | override static archive inserted into each libc archive |
| `link-override` | experimental link-order control | override static archive placed before libc |
| `preload` | an existing dynamic binary | override shared object loaded with `LD_PRELOAD` |

These mechanisms answer different questions. Reports keep dynamic, static, and
static-PIE binaries in separate comparison groups.

### `rust-global`

The application installs `rgalloc_shim::Alloc` as `#[global_allocator]`. The
shim calls allocator-specific symbols such as `mi_malloc`, `je_mallocx`, or
`sn_malloc`; libc's allocator remains available to C libraries in the process.
Prefixed symbols make a missing archive fail at link time instead of silently
falling back to libc.

### `libc-surgery`

`scripts/build/libc-surgery.sh` reconstructs musl's `libc.a`: it removes archive
members that provide allocation entry points, inserts the replacement archive,
and adds only the required mapped aliases. The member list is derived from the
archive rather than tied to one musl release.

The operation refuses to remove a member that also defines unrelated critical
symbols such as `fork`, `pthread_create`, `printf`, `open`, or `memcpy`. After
the splice it requires exactly one provider of `malloc` and `free` and no
unresolved musl allocator aliases. It patches both the distribution archive and
Rust's self-contained musl archive.

Static allocator replacement is not supported for glibc. Its allocator objects
also satisfy internal glibc references; removing them breaks the archive and
retaining them leaves competing allocation symbols.

### `link-override`

This control places an override archive ahead of libc. It is not a deployment
method: success depends on the program's link closure, and musl static links can
fail with duplicate allocation symbols. Do not use a linker option that accepts
multiple definitions; that makes allocator selection depend on link order.

### `preload`

Preload applies only to dynamic binaries. `alloc-runner preload-check` verifies
the shared object's allocator symbols, observes the library in the subject's
`/proc/<pid>/maps`, and confirms it is absent from the control process. Missing
or ambiguous residency is a failed identity check, not a usable result.

## Recipe contract

Every recipe receives `SRC`, `OUT`, `MODE`, `PIC`, `LIBC`, `TARGET_ARCH`, `CC`,
`CXX`, and `AR`. It produces one of:

```text
$OUT/lib/liballocbench.a
$OUT/lib/liballocbench.so
```

Exit code 3 with `UNSUPPORTED: <reason>` records an unsupported configuration.
Other nonzero exits are build failures. Recipes must run the shared export and
archive checks from `allocators/lib.sh` before returning success.

`CC` and `CXX` compile the allocator. Rust may use a different link driver;
`build.json` records both `cc` and `alloc_cc`.

## Allocator notes

### mimalloc

The CMake recipe switches between prefixed and override APIs with
`MI_OVERRIDE`. `MI_LIBC_MUSL` follows the target libc, and PIC is part of the
cache key. Exit-time collection remains enabled because disabling it would
change the startup workload in mimalloc's favor.

### jemalloc

The autotools recipe disables C++ exports and initial-exec TLS. C++ exports add
an unrequested runtime dependency; initial-exec TLS is incompatible with a
fully static process that has no dynamic loader.

### snmalloc

The C++20 recipe removes `new.cc.o` so a Rust link does not receive competing
C++ allocation operators. It resolves `libstdc++.a` through the selected C++
compiler. On musl it uses `CXX11_DESTRUCTORS`. `libc-surgery` is unsupported
because the override archive needs a C++ runtime in every static link.

### rpmalloc

The recipe compiles the C sources directly. The Rust shim initializes rpmalloc
once per process and once per thread before allocation. Prefixed builds localize
plain allocation aliases and verify the result.

### hardened_malloc

The recipe archives the objects produced by upstream's configuration while
forcing `CONFIG_NATIVE=false`, disabling the C++ allocator, and removing
allocator-internal LTO. The `default` and `light` variants are separate cache
and report dimensions. This project measures their cost; it does not validate
their security properties.

### Mesh and Google tcmalloc

Both are preload-only. Neither provides a distinct prefixed C API or a suitable
self-contained static archive. Mesh is pinned to a branch commit. Google
tcmalloc is built through Bazel 8.6.0 and is unsupported on musl upstream.

## Cache safety

The allocator cache key includes revision, mechanism, PIC, libc, architecture,
toolchain, and variant. It does not hash recipe contents. Delete the affected
allocator cache after changing a recipe.
