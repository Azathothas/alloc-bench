# `profiles` on alpine/x86_64 - the suite's first run, and the first PIC=0 cells this project has

The `profiles` suite has existed since the matrix was written and had **never
been run**. `docs/static-linking.md` described five profiles and the measured
consequences of four of them were unknown.

16 cells, four profiles × three allocators + the control, 10 samples.
**16 `ok`, 0 `build_failed`, 0 validator errors.**

##  Running it for the first time found a build that could not work

Every `PIC=0` cell - `static` and `static-lto` - was unbuildable for jemalloc on
x86_64, and had been for as long as the suite went unrun.
`allocators/lib.sh`'s `pic_cflags` emitted `-fno-PIC` and nothing else; Alpine's
gcc is `--enable-default-pie`, so the objects were non-PIC while the link was
still PIE:

```
relocation R_X86_64_32 against `.rodata.str1.1' can not be used
when making a PIE object; recompile with -fPIE
```

 **autoconf reports that as *"cannot run C compiled programs"*, rc=77**, which
names neither PIE nor the relocation. The linker's own sentence is in
`.build/config.log`.

 **It bit jemalloc alone, and only on x86_64**, which is why neither of the
obvious probes would have found it: mimalloc, snmalloc and the control built
fine at `PIC=0` on **two** machines (`bench` run
[`33582311135`](https://github.com/Azathothas/alloc-bench/actions/runs/33582311135)),
and the same `-fno-PIC` built jemalloc on **aarch64**, which reaches `.rodata`
through ADRP/ADD.  A trivial `int main(void){return 0;}` links fine with
`-fno-PIC` too - it has no string constant to relocate.

The fix is `-fno-PIC -fno-PIE` on the compile and `-no-pie` on the link, applied
**only where a recipe links** (jemalloc's `configure`).  Deliberately not added
to mimalloc's or snmalloc's cmake: a flag a working build does not need would
change the very archive this suite exists to compare.

## Conditions

| | |
| --- | --- |
| run id | `20260902-024610`, started 2026-09-02T02:46:10Z |
| `git_commit` | `13bd3dc…` |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
|  host quiescence | **no cell was measured under contention** - the one `gate.sh` run of this session's tail finished at 02:47:16 and the first measurement file was written at 02:49:28, so the overlap was with the image build only |

## What the profile does to the ordering

`literal`, each allocator against **the control in its own profile**:

| allocator | `static` | `static-lto` | `static-pie` | `static-pie-lto` |
| --- | --- | --- | --- | --- |
| snmalloc | **0.527×** | 0.661× | 0.606× | **0.539×** |
| mimalloc | 0.600× | 0.719× | **0.599×** | 0.557× |
| jemalloc | 0.617× | **0.657×** | 0.611× | 0.688× |
| *within-run MAD* | *0.7–4.8%* | *3.9–9.6%* | *1.8–3.4%* | *2.0–3.7%* |

```
static          snmalloc < mimalloc < jemalloc
static-lto      jemalloc < snmalloc < mimalloc
static-pie      mimalloc < snmalloc < jemalloc
static-pie-lto  snmalloc < mimalloc < jemalloc
```

 **Three different orderings across four profiles of the same three
allocators, on one machine in one run.** The profile changes the answer, which
is what the suite was written to ask.

 **And in three of the four, this project cannot name a winner at all.** §9's
rule is that a lead smaller than the run's own MAD is no result:

| profile | top two | gap | their MADs | verdict |
| --- | --- | --- | --- | --- |
| `static` | snmalloc / mimalloc | **14%** | 2.0% / 0.7% |  snmalloc, clearly |
| `static-lto` | jemalloc / snmalloc | 0.5% | 8.7% / 9.6% |  no result |
| `static-pie` | mimalloc / snmalloc / jemalloc | 1.1%, 0.8% | 2.9% / 3.4% / 2.3% |  no result, all three |
| `static-pie-lto` | snmalloc / mimalloc | 3.5% | 2.0% / 3.7% |  no result |

 **What does survive all four:** every one of the three candidates beat the
control in every profile, by 28–47%. That is the claim this run supports.

## What static-PIE costs for the ASLR it buys

Absolute median `literal` time for the **control**, which is the only row where
a cross-profile comparison is like-for-like:

| | plain | +PIE | ratio |
| --- | --- | --- | --- |
| no LTO | `static` 0.0771 s (3.4%) | `static-pie` 0.0783 s (1.8%) | **1.016** |
| LTO | `static-lto` 0.0652 s (4.6%) | `static-pie-lto` 0.0725 s (3.5%) | **1.113** |

 **The two estimates disagree by more than either cell's MAD, so the cost of
static-PIE is NOT established by this run.** One says 1.6% - inside the noise,
no result - and the other says 11.3%, outside it.  Do not quote either as *the*
ASLR cost; run it again before anyone plans around it.

 **LTO's effect on the control is the cleaner signal**, and it is in the same
direction both ways: `static-lto ÷ static` = **0.845**, `static-pie-lto ÷
static-pie` = **0.926** - 7–16% faster, both outside the MADs. Binary size falls
with it: 7.79 → 6.35 MiB plain, 8.15 → 6.63 MiB PIE.

##  ASLR, observed rather than inferred - 16 of 16 cells agree with the label

The acceptance this suite was written for:

| profile | link kind | distinct load addresses | randomised |
| --- | --- | --- | --- |
| `static`, `static-lto` | `static` | **1 of 6** | false |
| `static-pie`, `static-pie-lto` | `static-pie` | **6 of 6** | true |

No exceptions, for every allocator and the control.  Read from
`/proc/<pid>/maps` while each binary ran, not from the ELF type - which is what
makes `docs/static-linking.md`'s profile table a measurement rather than an
assertion.

 **28 validator warnings, all `noisy`**, and they are worth reading rather than
dismissing: `static-lto` reported 3.9–9.6% MADs against `static-pie`'s 1.8–3.4%
on the same host in the same run. That spread is why two of the four profiles
can support no ordering.
