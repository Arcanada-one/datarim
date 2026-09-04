#!/usr/bin/env bash
# check-seam-integration-boundary.sh — plan-time scope-boundary advisory scanner (TUNE-0239).
#
# Detects the failure mode where a single backlog one-liner bundles TWO discrete
# crate concerns: a seam/contract concern (define a trait / interface / state
# machine / dispatcher in crate X) AND an integration/call-site concern (wire
# that seam into a CLI / call site / end-to-end path in crate Y). When both
# concern-classes co-occur in one one-liner, the work is a foundation task plus
# an integration follow-up wearing a single task ID — the integration half tends
# to surface as out-of-scope late (at /dr-qa) and get deferred.
#
# The scanner is a NARROW, DETERMINISTIC, ADVISORY heuristic. It never blocks a
# plan by default (exit 0 whether it flags or not); the /dr-plan agent makes the
# final scope call — split into two tasks (foundation + integration follow-up)
# or scope the ACs so the integration is explicitly optional/deferred. Pass
# --strict for a hard signal (exit 3 on a flag) when a caller wants one.
#
# The two signal lists are a FLOOR, not a ceiling: a one-liner may mix concerns
# in wording neither list catches, and a genuine single-concern one-liner may
# incidentally contain one word from each list (false positive). Because the
# gate is advisory, both residual errors degrade to "the planner decides",
# never to a wrong hard block.
#
# Contract:
#   exit 0  → scanned OK (flagged or clean; default advisory mode)
#   exit 3  → flagged AND --strict
#   exit 2  → usage error
#
# API:
#   check-seam-integration-boundary.sh --line "<one-liner text>" [--strict] [--report]
#   check-seam-integration-boundary.sh --task <TASK-ID> [--backlog <path>]
#       [--root <repo-root>] [--strict] [--report]
#   --line  scans the literal text.
#   --task  extracts the one-liner for <TASK-ID> from the backlog index.

set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: check-seam-integration-boundary.sh --line "<text>" [--strict] [--report]
       check-seam-integration-boundary.sh --task <TASK-ID> [--backlog <path>]
           [--root <repo-root>] [--strict] [--report]
  --line     backlog one-liner text to scan (mutually exclusive with --task)
  --task     TASK-ID (^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$); reads its one-liner from the backlog
  --backlog  backlog index path (default: <root>/datarim/backlog.md)
  --root     repo/workspace root for the default backlog path (default: .)
  --strict   exit 3 when a seam+integration mix is flagged (default: exit 0, advisory)
  --report   print the matched signal tokens per concern class
exit codes:
  0 scanned OK (flagged or clean), 3 flagged under --strict, 2 usage error
USAGE
    exit 2
}

LINE=""
TASK=""
BACKLOG=""
ROOT="."
STRICT=0
REPORT=0
HAVE_LINE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --line)     [ $# -ge 2 ] || usage; LINE="$2"; HAVE_LINE=1; shift 2 ;;
        --task)     [ $# -ge 2 ] || usage; TASK="$2"; shift 2 ;;
        --backlog)  [ $# -ge 2 ] || usage; BACKLOG="$2"; shift 2 ;;
        --root)     [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --strict)   STRICT=1; shift ;;
        --report)   REPORT=1; shift ;;
        -h|--help)  usage ;;
        *)          usage ;;
    esac
done

# Exactly one of --line / --task.
if [ "$HAVE_LINE" -eq 1 ] && [ -n "$TASK" ]; then
    echo "ERROR: --line and --task are mutually exclusive" >&2; exit 2
fi
if [ "$HAVE_LINE" -eq 0 ] && [ -z "$TASK" ]; then
    usage
fi

# --task: resolve the one-liner from the backlog.
if [ -n "$TASK" ]; then
    if ! printf '%s' "$TASK" | grep -Eq '^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$'; then
        echo "ERROR: --task must match ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ (got: $TASK)" >&2; exit 2
    fi
    : "${BACKLOG:=$ROOT/datarim/backlog.md}"
    if [ ! -f "$BACKLOG" ]; then
        echo "ERROR: backlog not found: $BACKLOG" >&2; exit 2
    fi
    # First backlog line whose bullet is this task ID.
    LINE="$(grep -m1 -E "^- ${TASK} " "$BACKLOG" || true)"
    if [ -z "$LINE" ]; then
        echo "ERROR: no backlog one-liner found for $TASK in $BACKLOG" >&2; exit 2
    fi
fi

# ---------------------------------------------------------------------------
# Signal lists (case-insensitive ERE). SEAM = "build an in-crate contract";
# INTEGRATION = "wire that contract into a call site / CLI / end-to-end path".
# ---------------------------------------------------------------------------
SEAM_RE='seam|trait|interface|contract|abstraction|abstract |protocol|state[- ]?machine|formaliz|dispatcher|(^|[^a-z])port([^a-z]|$)|api surface'
INTEG_RE='wir(e|ed|es|ing)|call[- ]?sites?|integrat|(^|[^a-z])cli([^a-z]|$)|propagat|hook (up|into)|plumb|end[- ]?to[- ]?end|(^|[^a-z])e2e([^a-z]|$)|call it from|invoke .* from'

lc_line="$(printf '%s' "$LINE" | tr '[:upper:]' '[:lower:]')"

seam_hits="$(printf '%s' "$lc_line" | grep -oE "$SEAM_RE"  2>/dev/null | sort -u | paste -sd, - || true)"
integ_hits="$(printf '%s' "$lc_line" | grep -oE "$INTEG_RE" 2>/dev/null | sort -u | paste -sd, - || true)"

flagged=0
if [ -n "$seam_hits" ] && [ -n "$integ_hits" ]; then
    flagged=1
fi

if [ "$flagged" -eq 1 ]; then
    echo "ADVISORY: seam+integration boundary — this one-liner mixes a seam/contract concern with an integration/call-site concern."
    echo "  Consider splitting into a foundation task + an integration follow-up, or scope the ACs so the integration is explicitly optional/deferred."
    echo "  See skills/seam-vs-integration-boundary/SKILL.md."
    if [ "$REPORT" -eq 1 ]; then
        echo "  seam signals: ${seam_hits}"
        echo "  integration signals: ${integ_hits}"
    fi
    [ "$STRICT" -eq 1 ] && exit 3
    exit 0
fi

echo "PASS: single concern (no seam+integration mix detected)."
if [ "$REPORT" -eq 1 ]; then
    echo "  seam signals: ${seam_hits:-<none>}"
    echo "  integration signals: ${integ_hits:-<none>}"
fi
exit 0
