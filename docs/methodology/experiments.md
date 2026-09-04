# Experiments

Use `experiments/` for a bounded question that is cheaper to answer outside the
main runner.

Each experiment must state:

- the question and expected observation;
- required host, architecture, image, and tool versions;
- the exact commands or an executable script;
- the result and limits;
- the current project behavior affected by the result.

Commit deterministic output under `experiments/out/` when it supports a lasting
rule. Do not treat one host or one run as a general performance result. Promote
reusable checks into tests or the main gate; archive the investigation under
`docs/history/` when only its provenance remains useful.
