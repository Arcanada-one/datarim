#!/usr/bin/env bash
# check-qa-verdict-blocked.sh — Pre-archive gate: refuse to archive a task
# whose QA report carries a BLOCKED or FAIL overall verdict.
#
# The prose rule in commands/dr-qa.md:383-385 says the pipeline MUST NOT
# propose merge on BLOCKED/FAIL. This script is the mechanical enforcement:
# it greps the QA report for the verdict token and exits 1 on BLOCKED/FAIL.
#
# Usage:
#   check-qa-verdict-blocked.sh --qa-report <path> [--report]
#
# Exit codes:
#   0 — verdict is PASS / CONDITIONAL_PASS / SKIP, or no report found (legacy task)
#   1 — verdict is BLOCKED or FAIL
#   2 — usage error
#
# Called by /dr-archive Step 0.x (pre-archive gate) and /dr-qa Step 7 (self-check).
set -euo pipefail

usage() {
    echo "Usage: $0 --qa-report <path> [--report]"
    exit 2
}

QA_REPORT=""
REPORT_MODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --qa-report) QA_REPORT="$2"; shift 2 ;;
        --report) REPORT_MODE=1; shift ;;
        --help|-h) usage ;;
        *) usage ;;
    esac
done

[ -n "$QA_REPORT" ] || usage

# Legacy tasks without a QA report are not blocked — exit 0.
[ -f "$QA_REPORT" ] || exit 0

# Extract the overall verdict from the QA report frontmatter.
# The verdict is in YAML frontmatter as: verdict: <value>
# We look for the verdict key in the frontmatter block (between --- and ---).
VERDICT=$(awk '/^---$/ {c++; next}
    c==1 && /^verdict:/ {
        v=$0; sub(/^verdict:[[:space:]]*/, "", v);
        # Strip trailing inline comments (YAML allows #)
        sub(/[[:space:]]*#.*$/, "", v);
        sub(/[[:space:]]+$/, "", v);
        print v; exit
    }
    c>=2 {exit}' "$QA_REPORT" 2>/dev/null || true)

[ -n "$VERDICT" ] || exit 0

case "$VERDICT" in
    BLOCKED|FAIL)
        if [ "$REPORT_MODE" -eq 1 ]; then
            echo "BLOCKED: QA report verdict is $VERDICT — archive refused per dr-qa.md § Verdict Logic"
            echo "  QA report: $QA_REPORT"
            echo "  Verdict: $VERDICT"
            echo "  Action: resolve the blocking findings and re-run /dr-qa before archiving."
        fi
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
