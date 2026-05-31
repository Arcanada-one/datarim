# shellcheck shell=bash
# shellcheck disable=SC2034  # constants are sourced by datarim-doctor.sh / pre-archive-check.sh; shellcheck cannot see the consumers.
# schema-regex.sh — single source of truth for the Datarim thin-index schema regexes.
#
# Sourced by scripts/datarim-doctor.sh and scripts/pre-archive-check.sh;
# tests/datarim-doctor.bats asserts T13 against the sourced ONELINER_RE.
# This fragment is the ONLY place the literal patterns live — consumers source
# it, they do not redefine the constants. Extracting it here is what makes the
# historical three-way drift (doctor / pre-archive / bats encoded the regex
# independently and diverged) structurally impossible.
#
# Four separate named constants by design — they are NOT all interchangeable:
#   - ONELINER_RE     : doctor's strict thin-index form for tasks.md /
#                       activeContext.md (priority P[0-3]).
#   - BACKLOG_ITEM_RE : doctor's backlog.md form — pointer OPTIONAL, wider status
#                       vocab (+superseded|absorbed|deferred), priority P[0-4],
#                       optional **bold** wrapping.
#   - SCHEMA_TASKS_RE : the pre-archive gate's tasks form — same status set as
#                       ONELINER_RE but priority P[0-4] (bold-tolerant). The
#                       P[0-3] vs P[0-4] divergence between this and ONELINER_RE
#                       is intentional and preserved (not reconciled here).
#   - SCHEMA_BACKLOG_RE: the pre-archive gate's backlog form. Semantically the
#                       same 9-status set as BACKLOG_ITEM_RE but the alternation
#                       order differs, so it is kept as its own literal (aliasing
#                       would silently change the byte content of this constant).

ONELINER_RE='^- [A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)* · (in_progress|blocked|not_started|pending|blocked-pending|cancelled) · P[0-3] · L[1-4] · .+ → tasks/[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*-(task-description|init-task)\.md$'
BACKLOG_ITEM_RE='^- [A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)* · (in_progress|blocked|not_started|pending|blocked-pending|cancelled|superseded|absorbed|deferred) · [*]{0,2}P[0-4][*]{0,2} · [*]{0,2}L[1-4][*]{0,2} · .+$'
SCHEMA_TASKS_RE='^- [A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)* · (in_progress|blocked|not_started|pending|blocked-pending|cancelled) · [*]{0,2}P[0-4][*]{0,2} · [*]{0,2}L[1-4][*]{0,2} · .+ → tasks/[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*-(task-description|init-task)\.md$'
SCHEMA_BACKLOG_RE='^- [A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)* · (pending|blocked-pending|cancelled|superseded|absorbed|deferred|in_progress|blocked|not_started) · [*]{0,2}P[0-4][*]{0,2} · [*]{0,2}L[1-4][*]{0,2} · .+$'
