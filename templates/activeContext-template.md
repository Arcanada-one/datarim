# Active Context

<!--
Thin-index schema (v1.19.1+).

ONE section only — strict mirror of tasks.md § Active.
Identical lines, identical order. Validated by pre-archive-check.sh.

Active Tasks line regex (canonical):
  ^- ([A-Z]{2,10}-[0-9]{4}) · (in_progress|blocked|not_started) · P[0-3] · L[1-4] · (.{1,80}) → tasks/\1-task-description\.md$

Removed in v1.19.1:
  - `## Последние завершённые` — runtime via `/dr-status --recent N`
  - `## Last Updated` — not used by any consumer
  - `progress.md` — abolished v1.19.0
  - `backlog-archive.md` — abolished v1.19.1

Schema reference: skills/datarim-system.md § Operational File Schema.
-->

## Active Tasks

<!-- One-liner per active task, identical to tasks.md § Active. -->
