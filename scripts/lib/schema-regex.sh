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

# ---------------------------------------------------------------------------
# Spec-traceability regexes (the D-REQ addressing layer + Covers binding).
#
# Single source of truth for the spec-graph validators (dr-spec-lint.sh,
# dr-trace.sh, dr-lint.sh). Consumers source these constants; they do NOT
# redefine them. The D-REQ machine id is ALWAYS two digits (`D-REQ-NN`) so the
# format check is unambiguous — a human-readable description may follow the id
# on the heading line, but the id token itself is fixed-width.
#
#   - D_REQ_ID_RE   : a D-REQ-NN declaration. TWO canonical forms are accepted —
#                     the `#### D-REQ-NN: <desc>` heading form AND the
#                     `- **D-REQ-NN** — <desc>` bold-list form the /dr-prd
#                     Requirements section emits. (DEV-1547 / DEV-1552-FU both
#                     declared D-REQs as a bullet list and tripped a false grade-F.)
#   - COVERS_LINE_RE : a `Covers: D-REQ-NN[, D-REQ-NN ...]` binding on a V-AC. The
#                      binding may be inline (e.g. trailing a bullet) — leading
#                      text/markup before `Covers:` is tolerated.
#   - VERIFIES_LINE_RE : a `Verifies: V-AC-N[, V-AC-N ...]` plan-step binding. The
#                        /dr-plan template emits this inline+italic at the end of a
#                        numbered step (`… *Verifies: V-AC-1, V-AC-4*`), so leading
#                        text and `*`/`_` emphasis markers before `Verifies:` are
#                        tolerated.
#   - D_REQ_REF_RE  : a bare `D-REQ-NN` reference token (used to scan Covers values).
# ---------------------------------------------------------------------------

D_REQ_ID_RE='(^#### D-REQ-[0-9]{2}: .+$)|(^[[:space:]]*[-*][[:space:]]+\*\*D-REQ-[0-9]{2}\*\*)'
COVERS_LINE_RE='Covers:[[:space:]]*D-REQ-[0-9]{2}([[:space:]]*,[[:space:]]*D-REQ-[0-9]{2})*[[:space:]]*$'
D_REQ_REF_RE='D-REQ-[0-9]{2}'
VERIFIES_LINE_RE='Verifies:[[:space:]]*\**[[:space:]]*V-AC-[A-Z]?[0-9]+(\.[0-9]+)?([[:space:]]*,[[:space:]]*V-AC-[A-Z]?[0-9]+(\.[0-9]+)?)*'
EVIDENCE_LINE_RE='^[[:space:]]*(-[[:space:]]*)?Evidence:[[:space:]]*V-AC-[A-Z]?[0-9]+(\.[0-9]+)?[[:space:]]+.+$'
# V_AC_REF_RE — a bare V-AC reference token. Tolerates an OPTIONAL single
# uppercase-letter axis prefix on the numeric core (V-AC-A1), the form the
# v-ac-axis-split pattern emits when an L4 V-AC group is split across a
# deterministic/statistical axis. Remains a strict superset of the historical
# numeric-only id (V-AC-1, V-AC-12, V-AC-1.2), so every previously-matching
# token still matches. Source: TUNE-0473 (letter-prefixed V-AC in an
# expectations wish->V-AC cite was silently dropped, yielding a false grade-F).
V_AC_REF_RE='V-AC-[A-Z]?[0-9]+(\.[0-9]+)?'
