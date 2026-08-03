# Backlog

<!--
Pending-work ledger schema.

Each task remains on one machine-parseable line. A pending-work description may
remain inline until the task is promoted. Full active-task plans, ACs, and
constraints live in datarim/tasks/{TASK-ID}-task-description.md.

Canonical source: scripts/lib/schema-regex.sh BACKLOG_ITEM_RE.
Statuses include pending, blocked-pending, cancelled, superseded, absorbed,
deferred, and active states. Priority is P0-P4; complexity is L1-L4.

Pointer: optional for backlog entries. When present, use → (U+2192) and the
same task ID. Inline descriptions must be nonempty and single-line.

Examples:
  - <TASK-ID-A> · pending · P2 · L2 · <Inline pending-work description>
  - <TASK-ID-B> · blocked · P3 · L2 · <Title> → tasks/<TASK-ID-B>-task-description.md

Validation: scripts/datarim-doctor.sh / pre-archive-check.sh. Self-heal: /dr-doctor --fix.
Schema reference: skills/datarim-system/SKILL.md § Operational File Schema.
-->

## Pending

<!-- No pending items yet -->

## Blocked-Pending

<!-- Items waiting on external prerequisites -->

## Cancelled

<!-- Recently cancelled tasks (transient — full archive in
     documentation/archive/cancelled/archive-{ID}.md). backlog-archive.md is
     retired. -->
