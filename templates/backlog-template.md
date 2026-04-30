# Backlog

<!--
TUNE-0071 thin-index schema (v1.19.0+).

Each line is a one-liner pointer to a description file. NO task content here.
Full task body lives in datarim/tasks/{TASK-ID}-task-description.md.

Canonical regex (single-line, anchored):
  ^- ([A-Z]{2,10}-[0-9]{4}) · (pending|blocked-pending|cancelled) · P[0-3] · L[1-4] · (.{1,80}) → tasks/\1-task-description\.md$

Separator: · (U+00B7 MIDDLE DOT). Arrow: → (U+2192). Title: 1–80 chars.

Example:
  - INFRA-0099 · pending · P2 · L2 · Vault MFA Rollout → tasks/INFRA-0099-task-description.md

Validation: scripts/datarim-doctor.sh / pre-archive-check.sh. Self-heal: /dr-doctor --fix.
Schema reference: skills/datarim-system.md § Operational File Schema.
-->

## Pending

<!-- No pending items yet -->

## Blocked-Pending

<!-- Items waiting on external prerequisites -->

## Cancelled

<!-- Recently cancelled tasks (transient — full archive in
     documentation/archive/cancelled/archive-{ID}.md). TUNE-0071 v2 (v1.19.1):
     backlog-archive.md retired. -->

