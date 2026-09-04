# Static linking

The project distinguishes three artifact kinds:

| Kind | ELF shape | Runtime loader | Typical allocator mechanisms |
| --- | --- | --- | --- |
| dynamic | executable plus interpreter | required | `preload`, `rust-global` |
| static | fixed-address executable | none | `rust-global`, `libc-surgery`, `link-override` |
| static-PIE | position-independent static executable | none | `rust-global`, musl `libc-surgery` |

Reports never compare these kinds in one ranking group.

## Verification

Do not infer link kind or allocator identity from requested flags. Read the
final artifact:

```sh
alloc-runner identify \
  --bin ./rg \
  --expect-allocator mimalloc \
  --expect-kind static-pie
```

For static-PIE, verify runtime randomization separately:

```sh
alloc-runner aslr-probe \
  --bin ./rg --corpus /path/to/corpus \
  --runs 6 --expect randomised
```

One load address cannot establish ASLR. The probe starts repeated subjects and
reads their mapped base addresses from `/proc` after timing is complete.

## Platform limits

The stable x86_64 musl Rust target supports static-PIE. The stable aarch64 musl
target does not enable `static-position-independent-executables`; requesting a
PIC relocation model still produces a non-PIE static artifact. The planner
therefore marks unsupported cells or substitutes the suite's explicit
architecture profile.

Some compiler drivers accept an option without producing the requested kind.
For example, Zig's driver may ignore `-static-pie`; use `-static -pie` where
supported and always verify the ELF. Current Zig selection compiles allocator
sources and does not replace Rust's link driver.

## PIC and LTO

PIC is a property of allocator objects as well as the final application. It is
part of the allocator cache key. A non-PIC archive cannot be linked safely into
static-PIE.

Allocator-internal LTO is disabled across recipes. Application LTO is a separate
profile dimension applied equally to the control and candidates. Do not compare
profiles to attribute an effect to the allocator.

## Archive replacement

musl replacement patches every `libc.a` used by later builds, including Rust's
self-contained archive. The splice requires one provider of each allocation
entry point and refuses members that own unrelated libc functionality. glibc
archive replacement is unsupported; use source integration or preload.
