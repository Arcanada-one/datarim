---
name: dr-spec
description: Spec-traceability façade — lint the requirement graph, report coverage, introspect the rule registry, and read the computed grade
---

# /dr-spec — Spec-Traceability Façade

Thin operator-facing entry point over the deterministic spec-traceability layer.
It addresses requirements with `D-REQ-NN` ids (declared in the PRD), binds V-AC
items to them via a `Covers:` line, and validates the graph
`wish_id → D-REQ → V-AC → plan-step → evidence`. Read-only — it never mutates a
`datarim/` artefact.

This command is a documentation façade; the work is done by four `dev-tools/`
validators that share one library (`scripts/lib/spec-graph.sh`) and one rule
registry (`dev-tools/dr-spec-rules.yaml`):

| Action | Tool | Invocation |
|--------|------|------------|
| Lint the graph | `dr-spec-lint.sh` | `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-spec-lint.sh" --task {TASK-ID} --format json` |
| Coverage report | `dr-trace.sh` | `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-trace.sh" --task {TASK-ID}` |
| Registry / umbrella | `dr-lint.sh` | `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-lint.sh" rules` |
| Computed grade | `dr-spec-grade.sh` | `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-spec-grade.sh" --task {TASK-ID}` |

## Contract

All four obey the common validator contract (`docs/validator-contract.md`):

- `--format json` emits JSONL findings; `--format text` (default) a human table.
- Exit `0` = clean, `1` = violations (hard mode), `2` = usage/configuration error.
- A mis-configured rule set — unknown rule, empty effective set after
  `--rules`/`--ignore`, or disabling a mandatory rule — is exit `2`, **never**
  "0 violations".

`dr-spec-grade` is a **computed projection only**: it derives a letter from the
findings, is read-only, emits no routing token, and is invoked by no gate. It is
a dashboard signal, never a source of truth.

## Rollout

Advisory-first (`docs/spec-traceability-rollout.md`): L1 skipped, L2 advisory,
L3+ hard-gated after a transition window, scoped to changed artefacts
(`--scope git-diff`). Relationship to existing gates: the graph owns reference
resolution; expectations-checklist (`wish_id`) owns operator intent; V-AC owns
acceptance semantics. The graph is an addressing layer on top — it replaces
neither.

## Integration

On `/dr-verify --stage plan|all` the deterministic floor
(`dev-tools/dr-verify-floor.sh`) runs `dr-spec-lint` (advisory) and re-emits its
findings into the floor stream with `source_layer: "floor"` and
`check_name: "dr-spec-lint:<rule>"` — no new verdict enum.
