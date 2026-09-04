# platform

Architectures, distributions and images.

[`INDEX.md`](INDEX.md) is the list. [`PROGRESS.md`](PROGRESS.md) is the work
order. Entries close **in place**, with the acceptance command actually run and
its output pasted underneath.

---

## T-002: Decide what `core` does on aarch64

**Source:** `docs/AGENTS.md` §13, from the first-ever aarch64 dispatch
(CI run [`33500081741`](https://github.com/Azathothas/alloc-bench/actions/runs/33500081741)).
**Category:** platform
**Priority:** P1
**Effort:** M
**Status:** done

### Problem

The project states its architectures are x86_64 **and aarch64**. No aarch64 cell
has ever been measured, and today a dispatch cannot produce one: every cell in
the `core` suite fails the identity gate on that architecture. A documented
capability does not work.

### Premise

 **Measured, not read**, twice and by two routes.

**In the pipeline:** all six buildable cells built, and every one was rejected
with `link kind is static but the profile asked for static-pie`. The run was
correctly refused a ranking.

 **The oracle worked exactly as intended.** It caught a plain-static binary
wearing a `static-pie-lto` label on first contact with a new architecture, rather
than publishing it. This is the single best evidence the project has that its
central safeguard does its job - which is why the fix is never to relax it.

**Minimal repro on the host**, rustc 1.94.1, the same
`-C target-feature=+crt-static -C relocation-model=pic` the `static-pie` profile
uses (the image's 1.96.0 behaves the same, per the CI run):

| target | ELF type produced |
| --- | --- |
| `x86_64-unknown-linux-musl` | `DYN` - a real static-PIE |
| `aarch64-unknown-linux-musl` | `EXEC` - plain static, **the pic flag is ignored** |

 rustc decides this at target level: it puts `-static-pie` on the x86_64 link
line and plain `-static` on the aarch64 one. Forcing `-static-pie` through
`-C link-arg` does not help - `rust-lld` rejects it, it being a GCC driver flag.

 **Whether some other linker driver could produce one was not established.**
Treat "impossible" as "not achieved here", not as proven. That distinction is the
difference between a constraint the next session can route around and a wall
somebody else built for them.

### Approach

 **Do not relax the identity check.** That publishes a non-PIE binary under a
PIE label and is the exact failure §2.2 of `docs/AGENTS.md` exists to prevent.

Two honest options, and a third worth one hour before choosing:

1. **Mark `static-pie*` on aarch64/musl `unsupported` with this reason.** The §5
   convention, the smaller change, and it makes the limitation a published row
   rather than a run that fails. Seam: `crates/alloc-bench/src/plan.rs`, beside
   the existing `effective_distro` / `libc_for` logic that already emits
   unsupported cells with reasons.
2. **Give `core` a non-PIE profile on aarch64.** Seam:
   `benchmarks/matrix.toml`, the `core` suite's `profiles` key, made
   arch-dependent.  This costs the cross-architecture comparison its
   like-for-like profile, so the report must say the two architectures are not
   running the same build.
3. **Spend one hour establishing whether `aarch64-unknown-linux-musl` can produce
   a static-PIE at all** - with `gcc` as the linker driver rather than
   `rust-lld`, via `-C linker-flavor=gcc -C link-self-contained=no`. If it can,
   both options above are unnecessary and aarch64 gets the same profile as
   x86_64.

 **What it must not do:** label an aarch64 plain-static cell `static-pie-lto`
under any circumstances, and must not silently drop aarch64 from the suite.

### Decision

**Recommendation: try (3) first, timeboxed to one hour, then (1).** (3) is cheap
and, if it works, deletes this entry rather than working around it - which is
worth more than either workaround. If it does not, (1) is correct: it publishes
the limitation with its reason, which is this project's stated convention for a
configuration that cannot exist, and it leaves aarch64 measurable on the profiles
that *do* exist there rather than not at all.

 Note that (1) alone still leaves aarch64 with **no numbers from `core`**,
because `core` declares only `static-pie-lto`. Closing this entry therefore means
(1) **plus** deciding whether `core` gains a non-PIE aarch64 profile - otherwise
the architecture stays unmeasured with a tidier explanation, which is not the
outcome anybody wants.

### Prove

```sh
./target/release/alloc-bench plan --suite core --arch aarch64
```

Exit 0, and every emitted cell either planned with a profile that exists on that
target, or `unsupported` carrying the static-PIE reason. Then, for a real number:

```sh
alloc-bench run --suite core --arch aarch64      # on ubuntu-24.04-arm
alloc-bench validate --run results/published/<date>-core-aarch64
```

Exit 0 with 0 errors and at least a control plus one candidate `ok`.  An
`identity_failed` cell means this entry is not closed.

### Done, 2026-09-02 - option (3) refuted, (1) and the profile decision shipped, and aarch64 MEASURED

####  Option (3) is refuted, and the recorded reason for the limitation was wrong

The entry proposed *"gcc as the linker driver rather than `rust-lld`"*.
 **`rust-lld` was never the driver.** Measured on this host, rustc 1.94.1, the
same flags the `static-pie` profile uses:

```
$ rustc --target aarch64-unknown-linux-musl -C target-feature=+crt-static \
        -C relocation-model=pic main.rs
error: linking with `cc` failed …
  = note: "cc" … "-static" "-no-pie" …
```

 **The driver is already `cc`.** So option (3) was already the situation, and
the difference is not the linker at all. `rustc`'s own target definition says so,
read directly:

```
$ RUSTC_BOOTSTRAP=1 rustc -Z unstable-options --print target-spec-json --target <t>
```

| target | `static-position-independent-executables` | `linker-flavor` |
| --- | --- | --- |
| `x86_64-unknown-linux-musl` | **true** | `gnu-cc` |
| `aarch64-unknown-linux-musl` | **absent** | `gnu-cc` |

 **One boolean, in rustc, decides it** - not this project's flags, not the
linker, not the driver. `-C link-arg=-static-pie` merely *appends* the flag while
rustc's own `-static -no-pie` stay on the line; `-C linker-flavor=gcc
-C link-self-contained=no` changes nothing.

 **This is "not achievable from here", not "impossible".** A custom target JSON
with the flag flipped, built with `-Z build-std`, is an untested route and is
named so nobody re-derives the wall. It means shipping a custom rustc target,
which is far beyond this entry.

 **Also not established:** whether the aarch64 musl *linker* would accept
`-static-pie` if asked. The link on this host dies earlier, on
`Relocations in generic ELF (EM: 183)` - there is no aarch64 `cc` here. What is
established is that rustc never asks.

#### What shipped

1. **`crates/alloc-bench/src/plan.rs`** - `arch == aarch64 && libc == musl &&
   profile starts with `static-pie`` is `unsupported`, with the target-spec
   evidence in the reason string, printed in every report.  The identity oracle
   is untouched.
2. **`benchmarks/matrix.toml`** - `profiles_by_arch = { aarch64 = ["static-lto"] }`
   on `core`, a new optional per-suite key (`model.rs`, `plan.rs`). Without it
   option (1) alone would have left aarch64 with **no `core` numbers at all**,
   which the entry warns is "not the outcome anybody wants".

 **The two architectures are therefore not running the same build**, and that
is stated in the suite's own `why` block, which the report prints. Ratios never
cross a profile group, so the ranking cannot make the comparison by accident.

### Prove - run, with the output

```
$ ./target/release/alloc-bench plan --suite core --arch aarch64; echo "exit=$?"
alpine-aarch64-hardened_malloc-rust-global-static-lto-distro  planned
alpine-aarch64-jemalloc-rust-global-static-lto-distro         planned
alpine-aarch64-mesh-rust-global-static-lto-distro             unsupported  Mesh exports no prefixed C API…
alpine-aarch64-mimalloc-rust-global-static-lto-distro         planned
alpine-aarch64-rpmalloc-rust-global-static-lto-distro         planned
alpine-aarch64-snmalloc-rust-global-static-lto-distro         planned
alpine-aarch64-system-baseline-static-lto-distro              planned
alpine-aarch64-tcmalloc-rust-global-static-lto-distro         unsupported  tcmalloc exports no prefixed C API…
alloc-bench plan: 8 cell(s): 6 planned, 2 unsupported
exit=0
```

 Control plus five candidates, on a profile that exists on the target. Before
this change all eight were `planned` and all six buildable ones failed the
identity gate at run time.

Across the whole matrix, `plan --suite all` moves **122 planned / 24 unsupported
→ 102 / 44**: twenty aarch64/musl static-PIE cells that used to fail at run time
are now published rows with a reason. Per suite on aarch64:

| suite | planned | unsupported |
| --- | --- | --- |
| `core` | 6 | 2 |
| `profiles` | 8 | 8 - the two PIE profiles  which is itself the finding |
| `distros` | 15 | 3 - **alpine only**; debian and arch are glibc and keep static-PIE |
| `mechanisms` | 6 | 26 |
| `preload` | 12 | 0 - `dynamic`, unaffected |

 **`distros` on aarch64 loses its musl arm.** debian and archlinuxarm still
compare, so the suite is not broken, but the alpine rows are three published
`unsupported` reasons rather than measurements. That is the honest state: Alpine
on aarch64 genuinely cannot ship a static-PIE binary built this way.

###  The measurement - the first aarch64 numbers this project has

Nothing on this x86_64 host can produce one: there is no aarch64 `cc`, and
emulated timings are excluded from ranking by rule. So the acceptance was run
where the architecture is native - `bench.yml` dispatched on `ubuntu-24.04-arm`,
run [`33582107102`](https://github.com/Azathothas/alloc-bench/actions/runs/33582107102),
job `aarch64`, **`success`**, including its independent re-validation step.

**6 measurable cells, 6 `ok`, 2 `unsupported` with reasons, 0 validator errors.**
Native, Neoverse-N2, 4 cores, docker 28.0.4, commit `31476973`. Published as
`results/published/2026-09-02-core-aarch64-ci-runner/`.

| allocator | rel time | its MAD | rel peak RSS |
| --- | --- | --- | --- |
| jemalloc | **0.765×** | 2.9% | 1.569× |
| rpmalloc | **0.787×** | 2.9% | **1.127×** |
| mimalloc | 0.923× | 2.1% | 5.075× |
| snmalloc | 0.988× | 2.5% | 1.892× |
| system *(control)* | 1.000× | 1.1% | 1.000× |
| hardened_malloc | 1.106× | 1.3% | 3.702× |

 **The project's one surviving cross-machine claim holds on a fourth machine
and a second architecture**: jemalloc and rpmalloc beat musl's allocator, here
by 21–24% and as the top two.

 **And snmalloc gives a fourth distinct answer** - 0.595×, 0.553×, 1.138×,
0.988× across four machines - and here its lead is **inside its own 2.5% MAD**,
which §9 reports as no result.  That case is what made
`scripts/report/aggregate.py` apply the MAD rule to its "beat the control every
run" claim; before that the aggregate called it a win.

 **The honest cost of option (1)+(2) is visible in the published table.** The
report's ASLR section reads **1 of 6 distinct load addresses, randomised false**
for all six cells: aarch64 is measured on a non-PIE profile, and buys no ASLR.
That is stated rather than implied, which is the whole point of not relaxing the
oracle.

 **What is still not established**, and is deliberately not this entry: whether
a custom rustc target JSON with `static-position-independent-executables` set,
built with `-Z build-std`, could produce a working aarch64 static-PIE. Untested,
and it would mean shipping a custom target.
