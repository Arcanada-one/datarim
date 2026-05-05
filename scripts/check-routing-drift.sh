#!/usr/bin/env bash
# check-routing-drift.sh — pipeline routing drift detector.
#
# Reads skills/datarim-system/routing-invariants.md (single source of truth
# for canonical L1-L4 sequences and per-derived-file required tokens) and
# greps each derived file for its required substrings. Reports any missing
# token as a routing-drift finding.
#
# Usage:
#   ./scripts/check-routing-drift.sh           # human-readable output
#   ./scripts/check-routing-drift.sh --quiet   # suppress per-line output; exit code only
#
# Environment:
#   DATARIM_REPO_DIR   override repo root (default: parent of this script's dir)
#
# Exit codes:
#   0  routing in sync — every derived file contains every required token
#   1  drift detected (per-row diff to stdout)
#   2  error (missing invariants file, missing derived file, parse error)
#
# Read-only. No writes anywhere. Designed to be called by datarim-doctor.sh
# as a non-fatal advisory pass and from CI as a regression gate.

set -euo pipefail

REPO_DIR="${DATARIM_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
INVARIANTS_REL="skills/datarim-system/routing-invariants.md"
INVARIANTS="$REPO_DIR/$INVARIANTS_REL"
QUIET=false

if [ "${1:-}" = "--quiet" ]; then
    QUIET=true
fi

if [ ! -f "$INVARIANTS" ]; then
    echo "ERROR: routing invariants file missing: $INVARIANTS" >&2
    exit 2
fi

$QUIET || echo "Datarim Routing Drift Check"
$QUIET || echo "==========================="
$QUIET || echo "Repo:       $REPO_DIR"
$QUIET || echo "Invariants: $INVARIANTS_REL"
$QUIET || echo ""

FAILURES=0
ROW_COUNT=0
in_mapping=false

while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = '```mapping' ]; then
        in_mapping=true
        continue
    fi
    if $in_mapping && [ "$line" = '```' ]; then
        in_mapping=false
        continue
    fi
    $in_mapping || continue
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    IFS=$'\t' read -r path level label token <<< "$line"
    if [ -z "${path:-}" ] || [ -z "${level:-}" ] || [ -z "${label:-}" ] || [ -z "${token:-}" ]; then
        echo "ERROR: malformed mapping row (need 4 TAB-separated fields): $line" >&2
        exit 2
    fi
    ROW_COUNT=$((ROW_COUNT + 1))
    target="$REPO_DIR/$path"
    if [ ! -f "$target" ]; then
        $QUIET || echo "$path:$level: derived file missing ($label)"
        FAILURES=$((FAILURES + 1))
        continue
    fi
    if ! grep -qF -- "$token" "$target"; then
        $QUIET || echo "$path:$level: missing token \"$token\" ($label)"
        FAILURES=$((FAILURES + 1))
    fi
done < "$INVARIANTS"

if [ "$ROW_COUNT" -eq 0 ]; then
    echo "ERROR: no mapping rows found in $INVARIANTS_REL (looking for fenced \`\`\`mapping block)" >&2
    exit 2
fi

$QUIET || echo ""

if [ "$FAILURES" -gt 0 ]; then
    $QUIET || echo "RESULT: $FAILURES routing-drift item(s) found (of $ROW_COUNT checked)"
    exit 1
fi

$QUIET || echo "RESULT: all $ROW_COUNT routing tokens in sync"
exit 0
