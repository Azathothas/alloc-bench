# Replacing an allocator

Choose the mechanism from what you can change.

| Available change | Mechanism | Applies to |
| --- | --- | --- |
| source | `#[global_allocator]` or another prefixed API | rebuilt applications |
| image and later static builds | `libc-surgery` | musl images only |
| runtime environment | `LD_PRELOAD` | dynamic binaries only |
| link line | `link-override` | experimental control, not a general deployment method |

Measure the application on its deployment hardware before selecting an
allocator. The published ripgrep results do not establish a universal choice.

## Source integration

Bind the allocator's prefixed API so a missing library fails the link. In Rust,
the project uses `rgalloc-shim` as the global allocator. This changes Rust
allocations; C libraries may continue to use libc.

Verify the final binary:

```sh
alloc-runner identify \
  --bin ./application \
  --expect-allocator mimalloc \
  --expect-kind static-pie
```

## Dynamic replacement

Build the allocator's override shared object, then preload it:

```sh
LD_PRELOAD=/opt/allocator/lib/liballocbench.so ./application
```

Use `alloc-runner preload-check` before benchmarking. It confirms both symbol
identity and live residency in the subject process. Preload does not work for a
fully static binary.

## musl image replacement

Build an override archive through its allocator recipe, then patch each musl
archive:

```sh
SRC=/work/mimalloc OUT=/opt/mimalloc MODE=override PIC=1 \
LIBC=musl TARGET_ARCH=x86_64 CC=cc CXX=c++ \
  sh /opt/alloc-bench/allocators/mimalloc/build.sh

sh /opt/alloc-bench/scripts/build/libc-surgery.sh \
  /opt/mimalloc/lib/liballocbench.a \
  /usr/local/bin/alloc-runner
```

The script derives displaced members, protects unrelated libc symbols, supplies
approved unresolved aliases, patches Rust's self-contained musl archive, and
requires exactly one `malloc` and `free` provider afterward. Do not reproduce
the operation with a hard-coded archive-member list.

Verify the archive and a newly linked binary:

```sh
alloc-runner archive-check \
  --archive /usr/lib/libc.a --symbol malloc --expect-providers 1
alloc-runner identify \
  --bin ./application --expect-allocator mimalloc --expect-kind static-pie
```

glibc archive replacement is unsupported. Use source integration or preload
there.

## Runnable examples

`examples/run.sh` runs every supported example and `examples/verify.sh` checks
its transcript. Individual scripts cover Debian, Ubuntu, and Arch preload plus
Alpine, Void, and Wolfi musl replacement. See [`../examples/`](../examples/).

## Acceptance checks

Before deployment:

1. Confirm the expected allocator and link kind from the final artifact.
2. Run application correctness tests under representative concurrency.
3. Measure time, peak RSS, and binary size against the system control.
4. Repeat on the deployment hardware.
5. Retain the exact allocator revision, compiler, flags, image, and results.
