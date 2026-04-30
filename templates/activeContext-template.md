# Active Context

<!--
TUNE-0071 thin-index schema (v1.19.0+).

Three sections, all index-style. NO task content here — full body lives in
datarim/tasks/{TASK-ID}-task-description.md.

Active Tasks line regex (canonical):
  ^- ([A-Z]{2,10}-[0-9]{4}) · (in_progress|blocked|not_started) · P[0-3] · L[1-4] · (.{1,80}) → tasks/\1-task-description\.md$

Last Completed line regex:
  ^- ([0-9]{4}-[0-9]{2}-[0-9]{2}) · ([A-Z]{2,10}-[0-9]{4}) · (.{1,80}) → \.\./documentation/archive/[a-z]+/archive-\2\.md$

`## Последние завершённые` capped at 20 entries (older entries remain in archive/).
`progress.md` is abolished as of v1.19.0; this section is the single completion log.

Schema reference: skills/datarim-system.md § Operational File Schema.
-->

## Active Tasks

<!-- One-liner per active task. Append on /dr-init, remove on /dr-archive. -->

## Last Updated

YYYY-MM-DD HH:MM · {TASK-ID} — short summary

## Последние завершённые

<!-- Prepended on /dr-archive. Cap: 20 entries. -->
