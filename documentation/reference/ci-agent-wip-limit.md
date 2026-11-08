# Agent CI WIP limit (ARC-CI-11)

Agents pushing to `Arcanada-one/datarim` must not grow the Actions queue faster
than runners can drain it. Measured before this pilot
(`documentation/reference/ci-runner-load-before-receipt.json`): queue p50 ≈ 173 s
while job run p50 ≈ 36 s, so wait dominates feedback time.

## Reversible control

- Default limit: **2** open pull requests authored by the pushing account that
  still have pending GitHub Actions checks.
- Tool: `dev-tools/check-agent-ci-wip.sh` (exit `2` when over limit; no git
  mutation; no runner purchase).
- Override: `AGENT_CI_WIP_LIMIT` or `--limit`.
- Complements workflow `concurrency.cancel-in-progress` (ARC-CI-07), which only
  cancels superseded runs on the **same** ref.

## What this does not do

- Does not change branch protection or required contexts.
- Does not assert live `ci-general` headcount (live runner enumeration remains
  `NOT_MEASURED` in `ci-runner-capacity-model.json` when the API returns empty).
- Does not claim a percentage speedup from a single run.

Reverse by raising the limit or deleting the advisory script call from agent
briefs; workflow concurrency changes remain independently reversible.
