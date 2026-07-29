#!/usr/bin/env bash
# check-raw-sql-smoke-test.sh — Pre-archive gate: when a change introduces
# raw-SQL paths, verify the QA report carries a live smoke-test result.
#
# The prose rule in commands/dr-qa.md:306-308 says raw SQL usage REQUIRES a
# live smoke test against the actual target datasource. This script is the
# mechanical enforcement: it greps the diff for raw-SQL patterns and, when
# any are found, checks the QA report for a § 4d smoke-test section with a
# result.
#
# Usage:
#   check-raw-sql-smoke-test.sh --diff <git-diff-output-file> --qa-report <path> [--report]
#
# Exit codes:
#   0 — no raw SQL found, OR raw SQL found with smoke-test evidence present
#   1 — raw SQL found but no smoke-test evidence in QA report
#   2 — usage error
#
# Called by /dr-archive Step 0.x (pre-archive gate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $0 --diff <path> --qa-report <path> [--report]"
    exit 2
}

DIFF_FILE=""
QA_REPORT=""
REPORT_MODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --diff) DIFF_FILE="$2"; shift 2 ;;
        --qa-report) QA_REPORT="$2"; shift 2 ;;
        --report) REPORT_MODE=1; shift ;;
        --help|-h) usage ;;
        *) usage ;;
    esac
done

[ -n "$DIFF_FILE" ] && [ -n "$QA_REPORT" ] || usage
[ -f "$DIFF_FILE" ] || exit 0   # no diff = no raw SQL concern

# Patterns that indicate raw SQL bypassing the ORM type-checker.
# These are the patterns listed in dr-qa.md:306.
RAW_SQL_FOUND=0
if grep -qE '\$queryRaw|\.raw\(|sequelize\.query\(|prisma\.\$queryRaw|\.executeRaw\(|\.queryRaw\(' "$DIFF_FILE" 2>/dev/null; then
    RAW_SQL_FOUND=1
fi

[ "$RAW_SQL_FOUND" -eq 1 ] || exit 0   # no raw SQL → skip

# Raw SQL found — must have smoke-test evidence in the QA report.
[ -f "$QA_REPORT" ] || {
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: raw SQL detected in diff but no QA report found"
        echo "  Diff: $DIFF_FILE"
        echo "  Action: run /dr-qa with a live smoke test per dr-qa.md § 4d."
    fi
    exit 1
}

# Check for a § 4d smoke-test section with a result (not just the prose rule).
# Look for 4d. or ### 4d, followed by evidence of an actual test (a command
# block with output, or a result line like "row count" / "expected empty" /
# "error" per the mandate).
SMOKE_EVIDENCE=0
if grep -qzP '(?s)(####?\s*4d|###\s*4d\.).*?(```|row count|expected empty|error|smoke.test.*result|live smoke)' "$QA_REPORT" 2>/dev/null; then
    SMOKE_EVIDENCE=1
fi

# Fallback: grep for explicit smoke-test RESULT markers (not just prose mention).
# The QA report must contain evidence of an actual test, not just the prose rule
# restated. Look for: a command inside a code fence immediately after a smoke-test
# section, or an explicit result annotation.
if [ "$SMOKE_EVIDENCE" -eq 0 ]; then
    if grep -qiE 'row count|expected empty|exit code.*0|smoke.test.*passed|live.test.*passed|live.smoke.*result|smoke.test.*result|live.run.*result' "$QA_REPORT" 2>/dev/null; then
        SMOKE_EVIDENCE=1
    fi
fi

if [ "$SMOKE_EVIDENCE" -eq 0 ]; then
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: raw SQL detected in diff but no smoke-test evidence in QA report"
        echo "  QA report: $QA_REPORT"
        echo "  Action: add a live smoke test per dr-qa.md § 4d and re-run /dr-qa."
    fi
    exit 1
fi

exit 0
