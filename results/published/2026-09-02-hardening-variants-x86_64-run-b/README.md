# `hardening-variants`, run B - the repeat, and the claim it removed

The second run of the same three cells, **same commit, same host, six minutes
after run A**. Published because it disagrees with run A about one thing, and a
disagreement that is not published is a magnitude nobody knows is unstable.

Run A, the full account of what `light` changes, and upstream's config diff:
[`../2026-09-02-hardening-variants-x86_64/`](../2026-09-02-hardening-variants-x86_64/).

3 cells, **3 `ok`, 0 validator errors**, 3 `noisy` warnings, 10 samples.

| row | time (s) | `rel` | MAD | peak RSS | `rel` RSS |
| --- | --- | --- | --- | --- | --- |
| hardened_malloc **`light`** | 0.0510 | **0.665×** | 4.0% | 5.38 MiB | **1.178×** |
| system *(control)* | 0.0768 | 1.000× | 1.0% | 4.57 MiB | 1.000× |
| hardened_malloc | 0.0770 | **1.003×** | 2.1% | 13.13 MiB | **2.875×** |

##  The one claim this run removes

Run A put hardened_malloc's **default** at **1.084×** - 8.4% slower than musl's
allocator, against MADs of 1.2% and 4.1%, which §9 accepts as a result.

This run puts it at **1.003×**: level with the control, and well inside its own
2.1% and 1.0% MADs, which §9 reports as **no result**.

 **So "hardened_malloc's default configuration is slower than musl" is not
established by this suite**, and the disagreement is larger than either run's
own spread.  The `core` suite does not settle it either - 1.075×, 0.890× and
1.225× on three machines.

##  What it confirms instead

| | run A | run B |
| --- | --- | --- |
| `light` faster than `default` | +48.7% | **+50.9%** |
| `light` against the control | 0.729× | **0.665×** |
| `light` peak RSS | 1.178× | **1.178×** |
| `default` peak RSS | 2.875× | **2.875×** |

 **Peak RSS reproduced to three decimal places** on both variants. That is the
finding of this suite: `light` costs **1.178×** the control's peak RSS where the
default costs **2.875×**, a **2.44×** reduction, and it does not move between
runs the way the timings do.

 **This host was slower during this run** - the control alone went 0.0605 s in
run A to 0.0768 s here, a 27% shift with nothing changed but the clock. It is
the reason the ratios are quoted and the absolute times are not, and a concrete
instance of the project's standing rule that a within-run MAD is a floor on the
uncertainty rather than a bound.

## Conditions

| | |
| --- | --- |
| run id | `20260902-074405`, started 2026-09-02T07:44:05Z |
| `git_commit` | `3ce29e999b9d02093ca68aec67806df636d80b5d` - **the same commit as run A**, reachable from `main` |
| `git_dirty` | **false** |
| host | `Intel(R) Xeon(R) Processor @ 2.80GHz`, 4 cores, kernel `Linux 6.18.44-fc-v22` |
| runtime | docker 29.3.1 |
| samples | 10 per workload |
