---
task_id: SAMPLE-0020
artifact: init-task
schema_version: 1
captured_at: 2026-06-14T00:00:00+0000
captured_by: /dr-init
operator: sample
status: canonical
source: /dr-init
---

## Operator brief (verbatim)

A documentation-only task with no networking surface. At /dr-prd and /dr-plan
the only artefact that exists is this init-task, which has no priority/type
frontmatter by schema. The gate must resolve to skip, not fail-closed hard_block.

## Append-log (operator amendments)

_(empty)_
