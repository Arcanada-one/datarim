---
name: routing-invariants
description: Single source of truth for canonical pipeline routing per complexity level (L1-L4) and the literal grep tokens each derived runtime file MUST contain. Loaded by scripts/check-routing-drift.sh.
---

# Pipeline Routing Invariants

Canonical L1–L4 routing sequences and the literal substrings each derived
runtime file MUST contain to be considered in sync. This file is the single
source of truth; `scripts/check-routing-drift.sh` parses the two fenced blocks
below to detect drift between sibling files describing the same routing.

Add a new transition or change a stage? Update **this file first**, then
propagate to every derived file listed in the `mapping` block. The drift
script will flag any file that fell behind.

## Canonical Sequences

The fenced block below describes the canonical happy-path sequence per
complexity level. Reflection (Step 0.5 of `/dr-archive`) is non-skippable and
intentionally NOT shown as a separate node. Optional stages at a given level
(brackets in human-facing prose) are inlined here because they are the
default routing when their preconditions are met.

```routing
L1: /dr-init → /dr-do → /dr-archive
L2: /dr-init → /dr-prd → /dr-plan → /dr-do → /dr-qa → /dr-archive
L3: /dr-init → /dr-prd → /dr-plan → /dr-design → /dr-do → /dr-qa → /dr-compliance → /dr-archive
L4: /dr-init → /dr-prd → /dr-plan → /dr-design → /dr-do → /dr-qa → /dr-compliance → /dr-archive
```

## Mapping

The fenced `mapping` block below is the machine-readable contract consumed by
`scripts/check-routing-drift.sh`. Each non-comment line is TAB-separated:

```
<derived-file-path>\t<level-label>\t<transition-label>\t<literal-token>
```

`<derived-file-path>` is repo-relative. `<literal-token>` MUST appear in the
file as an exact substring (`grep -F`). Tokens are intentionally chosen to
encode the (level, transition) pair so that removing any single transition
fails detection. Comment lines start with `#` and are ignored.

```mapping
# backlog-and-routing.md — Mode Transitions table
skills/datarim-system/backlog-and-routing.md	L3-4	plan→design	`/dr-plan` | L3-4 | `/dr-design
skills/datarim-system/backlog-and-routing.md	L1-2	plan→do	`/dr-plan` | L1-2 | `/dr-do
skills/datarim-system/backlog-and-routing.md	L3-4	design→do	`/dr-design` | L3-4 | `/dr-do
skills/datarim-system/backlog-and-routing.md	L3-4	do→qa	`/dr-do` | L3-4 | `/dr-qa
skills/datarim-system/backlog-and-routing.md	L1-2	do→archive	`/dr-do` | L1-2 | `/dr-archive
skills/datarim-system/backlog-and-routing.md	L3-4	qa→compliance	`/dr-qa` PASS / CONDITIONAL_PASS | L3-4 | `/dr-compliance
skills/datarim-system/backlog-and-routing.md	L1-2	qa→archive	`/dr-qa` PASS / CONDITIONAL_PASS | L1-2 | `/dr-archive
skills/datarim-system/backlog-and-routing.md	L3-4	compliance→archive	`/dr-compliance` COMPLIANT* | L3-4 | `/dr-archive
# pipeline-routing.md — Mermaid graph edges
skills/visual-maps/pipeline-routing.md	L1	do→archive	Do1 --> Archive1
skills/visual-maps/pipeline-routing.md	L2	plan→do	Plan2 --> Do2
skills/visual-maps/pipeline-routing.md	L2	do→qa	Do2 --> QA2
skills/visual-maps/pipeline-routing.md	L2	qa→archive	QA2 --> Archive2
skills/visual-maps/pipeline-routing.md	L3	plan→design	Plan3 --> Design3
skills/visual-maps/pipeline-routing.md	L3	design→do	Design3 --> Do3
skills/visual-maps/pipeline-routing.md	L3	do→qa	Do3 --> QA3
skills/visual-maps/pipeline-routing.md	L3	qa→compliance	QA3 --> Compliance3
skills/visual-maps/pipeline-routing.md	L3	compliance→archive	Compliance3 --> Archive3
skills/visual-maps/pipeline-routing.md	L4	plan→design	Plan4 --> Design4
skills/visual-maps/pipeline-routing.md	L4	design→do	Design4 --> Do4
skills/visual-maps/pipeline-routing.md	L4	do→qa	Do4 --> QA4
skills/visual-maps/pipeline-routing.md	L4	qa→compliance	QA4 --> Comp4
skills/visual-maps/pipeline-routing.md	L4	compliance→archive	Comp4 --> Archive4
# stage-process-flows.md — stage-end → primary CTA table
skills/visual-maps/stage-process-flows.md	L3-4	plan→design	`/dr-plan` (L3-4) | `/dr-design
skills/visual-maps/stage-process-flows.md	L1-2	plan→do	`/dr-plan` (L1-2) | `/dr-do
skills/visual-maps/stage-process-flows.md	L3-4	do→qa	`/dr-do` (L3-4) | `/dr-qa
skills/visual-maps/stage-process-flows.md	L1-2	do→archive	`/dr-do` (L1-2) | `/dr-archive
skills/visual-maps/stage-process-flows.md	L3-4	qa→compliance	`/dr-qa` PASS / CONDITIONAL_PASS (L3-4) | `/dr-compliance
skills/visual-maps/stage-process-flows.md	L3-4	compliance→archive	`/dr-compliance` COMPLIANT | `/dr-archive
# dr-plan.md — CTA Routing logic
commands/dr-plan.md	L3-4	plan→design	L3-4 with creative-phase needs → primary `/dr-design
commands/dr-plan.md	L3-4	plan→do	L3-4 without creative-phase needs → primary `/dr-do
commands/dr-plan.md	L1-2	plan→do	L1-2 → primary `/dr-do
# dr-qa.md — CTA Routing logic
commands/dr-qa.md	L3-4	qa→compliance	ALL_PASS or CONDITIONAL_PASS at L3-4 → primary `/dr-compliance
commands/dr-qa.md	L1-2	qa→archive	ALL_PASS or CONDITIONAL_PASS at L1-2 → primary `/dr-archive
# dr-do.md — CTA Routing logic
commands/dr-do.md	L3-4	do→qa	All checks pass, L3-4 → primary `/dr-qa
commands/dr-do.md	L1-2	do→archive	All checks pass, L1-2 → primary `/dr-archive
```

## Adding a New Derived File

1. Append rows to the `mapping` block above for every (level, transition)
   pair the file describes. One row per pair.
2. Run `scripts/check-routing-drift.sh` locally — exit 0 confirms the new
   file is in sync.
3. If a transition exists in canonical but a derived view intentionally
   omits it (e.g. an L1-only quick reference), do not add a row for that
   pair; the drift script only flags rows that exist in mapping.

## Non-Goals

- The script does not auto-fix drift. Operator must manually reconcile.
- The script does not validate Mermaid syntax or table well-formedness —
  only literal-token presence.
- Class B routing changes (new stages, new layers) require updating this
  file plus all derived views; not a content-addition.
