---
task_id: {TASK-ID}
artifact: expectations
schema_version: 4
captured_at: {YYYY-MM-DD}
captured_by: {/dr-init | /dr-prd | /dr-plan}
status: canonical
agent: {planner | architect}
parent_init_task: {TASK-ID}-init-task.md
parent_prd: ../prd/PRD-{TASK-ID}.md
---

# {TASK-ID} — Operator expectations

> Each bullet is one verifiable expectation in the resolved artifact language.
> Keep machine fields and enums unchanged. `partial` or `missed` without a
> legitimate `override:` (at least 10 characters) blocks the pipeline and
> returns to `/dr-do` with the affected `wish_id` values. An override is a
> sibling wish field indented exactly two spaces, never nested under status.
> Contract: `skills/expectations-checklist/SKILL.md`.
> Validator: `"${DATARIM_RUNTIME:?}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID}`.
> Translate presentation headings with semantic markers intact; legacy files
> are read through compatibility aliases and are never silently rewritten.

## Expectations <!-- datarim:expectations -->

- **1. {First expectation title in ordinary words, ending with a period.}**
  - wish_id: {stable ASCII kebab-slug; preserve existing legacy IDs}
  - wish: {one or two sentences}
  - success_criterion: {concrete signal: file, command output or visible behavior}
  - linked_ac: {V-AC-N or the no-link dash}
  - customer_derived: true
  - requirement_id: {req-NNNN}
  - surface_class: {VISITOR_VISIBLE | ENABLING}
  - visitor_visible: {true | false}
  - delivery_receipt: {datarim/receipts/{TASK-ID}-customer-delivery.yaml}
  - evidence_type: {empirical | static | measurement}
  - #### status_history
    - {ISO 8601} / {local-time} · {/dr-init | /dr-prd | /dr-plan} · pending → pending · reason: wish captured when expectations were created
  - #### current_status
    - pending

- **2. {Second expectation title.}**
  - wish_id: {kebab-slug}
  - wish: {one or two sentences}
  - success_criterion: {concrete observable signal}
  - linked_ac: {V-AC-N or the no-link dash}
  - customer_derived: true
  - requirement_id: {req-NNNN}
  - surface_class: {VISITOR_VISIBLE | ENABLING}
  - visitor_visible: {true | false}
  - delivery_receipt: {datarim/receipts/{TASK-ID}-customer-delivery.yaml}
  - evidence_type: {empirical | static | measurement}
  - #### status_history
    - {ISO 8601} / {local-time} · {/dr-init | /dr-prd | /dr-plan} · pending → pending · reason: wish captured when expectations were created
  - #### current_status
    - pending

<!-- Append new wishes at the bottom, preserving this structure and all existing
     identifiers/history. Optional v3/v4 fields:
  - verification_mode: reproducible          # one-off | reproducible
  - evidence_artifact: tests/my-suite.bats    # path, test-id or CI-job-name
     Reproducible verification requires resolvable evidence; missing evidence
     remains advisory at QA and a hard compliance error. -->

## Append-log (operator amendments)

> Append amendments chronologically under `### <ISO timestamp> — amendment by <author>`.

_(empty at creation)_
