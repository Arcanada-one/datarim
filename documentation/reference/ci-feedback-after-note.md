# ARC-CI batch 1 - "after" measurement note

Same script as the baseline: `dev-tools/measure-ci-feedback.py` (new `--since`, `--until`, `--event`, `--compare`).

- Baseline: `ci-feedback-baseline-receipt.json` (10 successful `bats.yml` runs, before PR #606).
- After: `ci-feedback-after-receipt.json` = `--since 2026-11-08T00:53:43Z --limit 10` (the 10 newest successful `bats.yml` runs created after the PR #606 merge commit `22371f7`).
- Diff: `ci-feedback-compare.json` (`CiFeedbackCompare/v1`; a delta exists only when both samples are >= 10).

## What the numbers say (p50 unless noted; n = 10 vs 10)

| Metric | Before | After |
|---|---|---|
| Feedback time p50 / p95 (s) | 435 / 570 | 459.5 / 639 |
| Job queue p50 (s) | 173 | 23.5 |
| Runner-seconds per successful check p50 | 5713 | 4007.5 |
| customer-delivery Linux jobs p50 | 100 | 20 |
| Bats shard longest/median p50 | 2.018 | 1.185 |

- Queue time, runner-seconds, job count and shard balance moved in the intended direction; the shard ratio is below the 1.5 experiment target in this sample.
- **End-to-end feedback time did not improve** in this sample (p50 +24.5 s, p95 +69 s). No speedup is claimed.
- Not separated here: runner capacity vs. other workloads on the shared pool, run-to-run variance, and the effect of PR #619 (reusable workflow steps restored) inside the "after" window. The sample is two windows of 10 runs, not a controlled experiment.
- `setup_python_job_seconds` reads 0 on both sides; it counts jobs by name, so it does not separate the effect of the change.
