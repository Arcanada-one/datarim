---
task_id: TUNE-0516
artifact: expectations
schema_version: 2
captured_at: 2026-07-26
captured_by: /dr-init
status: canonical
agent: planner
parent_init_task: TUNE-0516-init-task.md
---

# TUNE-0516 - Operator expectations

## Expectations

- **1. Parallel orchestration is the documented default.**
  - wish_id: parallel-orchestration-default
  - Что хочу проверить: Each task uses an isolated session, worktree, and branch, while only same-branch or same-file overlap requires coordination.
  - Как проверить (success criterion): The rule and cross-links exist in the three specified shipped files without routing changes.
  - Связанный AC из PRD: -
  - evidence_type: static
  - #### История статусов
    - 2026-07-26T08:52:00Z / 2026-07-26 08:52 UTC · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
  - #### Текущий статус
    - pending

- **2. Status changes are persisted immediately and shipped safely.**
  - wish_id: immediate-status-persistence
  - Что хочу проверить: Tracked operational status flips are committed and pushed promptly, with a clear distinction from ordinary work-in-progress code.
  - Как проверить (success criterion): The advisory rule, regression test, marker correction, hygiene greps, full gates, signed commits, pushed branch, and archive all pass.
  - Связанный AC из PRD: -
  - evidence_type: empirical
  - #### История статусов
    - 2026-07-26T08:52:00Z / 2026-07-26 08:52 UTC · /dr-init · pending → pending · reason: пункт создан при инициализации задачи
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(empty at creation)_
