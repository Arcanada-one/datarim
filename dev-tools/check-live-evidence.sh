#!/usr/bin/env bash
# check-live-evidence.sh — Pre-archive gate: when a task's expectations
# checklist declares evidence_type: empirical items, verify the QA report
# carries live-run evidence (not just mock assertions).
#
# The prose rule in commands/dr-qa.md:316 says evidence_type: empirical
# expectations MUST be verified with a live tool-run, not mocks alone.
# This script is the mechanical enforcement: it detects empirical-expectation
# wishes and checks for live-evidence markers in the QA report.
#
# Limitations (documented as EXEMPT-partial):
#   This gate checks STRUCTURAL presence of live-evidence markers (command
#   block with stdout, exit-code annotation, tool-version annotation). It
#   cannot semantically verify that the captured output is from a real run
#   rather than a fabricated one — that remains a human judgment.
#
# Usage:
#   check-live-evidence.sh --expectations <path> --qa-report <path> [--report]
#
# Exit codes:
#   0 — no empirical-expectation items, OR all such items have live-evidence
#        markers in the QA report
#   1 — empirical-expectation items found but live-evidence markers absent
#   2 — usage error
#
# Called by /dr-qa Layer 3b (post-expectations-verification self-check) and
# /dr-archive Step 0.x (pre-archive gate).
set -euo pipefail

usage() {
    echo "Usage: $0 --expectations <path> --qa-report <path> [--report]"
    exit 2
}

EXPECTATIONS_FILE=""
QA_REPORT=""
REPORT_MODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --expectations) EXPECTATIONS_FILE="$2"; shift 2 ;;
        --qa-report) QA_REPORT="$2"; shift 2 ;;
        --report) REPORT_MODE=1; shift ;;
        --help|-h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$EXPECTATIONS_FILE" ] || [ -z "$QA_REPORT" ]; then
    usage
fi

# No expectations file → skip.
[ -f "$EXPECTATIONS_FILE" ] || exit 0

# Count empirical-expectation items in the expectations checklist.
# evidence_type: empirical appears in the wish status-history or current-status block.
EMPIRICAL_COUNT=$(grep -c 'evidence_type:[[:space:]]*empirical' "$EXPECTATIONS_FILE" 2>/dev/null || echo 0)
[ "$EMPIRICAL_COUNT" -gt 0 ] || exit 0

# Empirical wishes exist — verify the QA report has live-evidence markers.
# Live-evidence markers (structural, not semantic):
#   - A ``` (code fence) block containing a command invocation AND output
#   - Tool version annotation (--version / version:)
#   - Exit-code annotation (Exit code:)
#   - Explicit "live run" / "live test" / "real tool" wording
[ -f "$QA_REPORT" ] || {
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: $EMPIRICAL_COUNT empirical-expectation item(s) found but no QA report exists"
        echo "  Expectations: $EXPECTATIONS_FILE"
        echo "  Action: run a live tool-run per dr-qa.md:316 and record evidence in the QA report."
    fi
    exit 1
}

LIVE_MARKERS=0

# Marker 1: code fence with a command AND output (not just a command listing)
# shellcheck disable=SC2016  # PCRE pattern with literal $/backtick markers
if grep -qPz '(?s)```(bash|text|shell)?\s*\n\$?\s*\w+.*\n(.*\n){1,20}```' "$QA_REPORT" 2>/dev/null; then
    LIVE_MARKERS=$((LIVE_MARKERS + 1))
fi

# Marker 2: explicit live-evidence language
if grep -qEi 'live (run|test|smoke|tool.run|execution)|real (output|tool|run)|Command and result|Exit code:|empirical.*live|live.*empirical' "$QA_REPORT" 2>/dev/null; then
    LIVE_MARKERS=$((LIVE_MARKERS + 1))
fi

# Marker 3: tool version recorded (evidence of a real invocation)
if grep -qE 'version:|--version|\bv[0-9]+\.[0-9]+' "$QA_REPORT" 2>/dev/null; then
    LIVE_MARKERS=$((LIVE_MARKERS + 1))
fi

# Marker 4: explicit smoke-test or live-run command recorded
if grep -qE 'smoke.test|live.test|live.run|real.run|Command and result' "$QA_REPORT" 2>/dev/null; then
    LIVE_MARKERS=$((LIVE_MARKERS + 1))
fi

# At least 2 markers needed to pass (avoids false-positives from incidental
# mentions like "version:" in unrelated prose).
if [ "$LIVE_MARKERS" -ge 2 ]; then
    exit 0
fi

if [ "$REPORT_MODE" -eq 1 ]; then
    echo "BLOCKED: $EMPIRICAL_COUNT empirical-expectation item(s) found but live-evidence markers insufficient ($LIVE_MARKERS of 2 required)"
    echo "  Expectations: $EXPECTATIONS_FILE"
    echo "  QA report: $QA_REPORT"
    echo "  Action: record live tool-run evidence (Command and result block with real output, tool version, and exit code) per dr-qa.md:316."
fi
exit 1
