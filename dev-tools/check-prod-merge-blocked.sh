#!/usr/bin/env bash
# check-prod-merge-blocked.sh — Pre-archive gate: for deploy-class tasks,
# refuse to archive when the prod merge verification is BLOCKED or
# unverifiable without operator confirmation.
#
# The prose rules in commands/dr-archive.md:279 (never auto-archive on
# unverifiable prod) and :386 (archive MUST NOT proceed until prod merge
# is done AND verified) are UNENFORCED. This script is the mechanical
# enforcement for both.
#
# It checks two things:
#   1. Is the task deploy-class? (via check-deploy-class.sh)
#   2. Does the archive doc carry prod-merge verification evidence?
#      (a post-merge health/log probe, a version match, or an operator
#       confirmation on BLOCKED)
#
# Usage:
#   check-prod-merge-blocked.sh --task-description <path> --archive-doc <path> [--report]
#
# Exit codes:
#   0 — not deploy-class, OR prod-merge verification evidence present
#   1 — deploy-class but prod-merge verification missing or BLOCKED without
#        operator confirmation
#   2 — usage error
#
# Called by /dr-archive Step 0.4 (post-probe self-check) and Step 2
# (pre-finalize gate).
set -euo pipefail

usage() {
    echo "Usage: $0 --task-description <path> --archive-doc <path> [--report]"
    exit 2
}

TASK_DESC=""
ARCHIVE_DOC=""
REPORT_MODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --task-description) TASK_DESC="$2"; shift 2 ;;
        --archive-doc) ARCHIVE_DOC="$2"; shift 2 ;;
        --report) REPORT_MODE=1; shift ;;
        --help|-h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$TASK_DESC" ] || [ -z "$ARCHIVE_DOC" ]; then
    usage
fi

# Check if deploy-class. Use the existing classifier script if available;
# otherwise, grep for deploy-surface markers directly.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_CLASSIFIER="$SCRIPT_DIR/check-deploy-class.sh"

IS_DEPLOY=0
if [ -x "$DEPLOY_CLASSIFIER" ] && [ -f "$TASK_DESC" ]; then
    if "$DEPLOY_CLASSIFIER" --task-description "$TASK_DESC" >/dev/null 2>&1; then
        IS_DEPLOY=1
    fi
fi

# Fallback: grep the task description for deploy-surface markers.
if [ "$IS_DEPLOY" -eq 0 ] && [ -f "$TASK_DESC" ]; then
    if grep -qiE 'deploy|systemd|nginx|docker.compose|production|prod.deploy|cutover' "$TASK_DESC" 2>/dev/null; then
        IS_DEPLOY=1
    fi
fi

[ "$IS_DEPLOY" -eq 1 ] || exit 0   # not deploy-class → skip

# Deploy-class: archive doc MUST have prod-merge verification evidence.
[ -f "$ARCHIVE_DOC" ] || {
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: deploy-class task but no archive doc found"
        echo "  Task: $TASK_DESC"
        echo "  Action: perform prod-merge verification per dr-archive.md § 0.4."
    fi
    exit 1
}

# Evidence markers for prod-merge verification:
VERIFY=0

# Marker 1: explicit post-merge / prod-verification language
if grep -qiE 'prod.merge.*verified|post.merge.*verif|prod.deploy.*confirmed|deploy.*class.*verified|production.*merge.*done' "$ARCHIVE_DOC" 2>/dev/null; then
    VERIFY=$((VERIFY + 1))
fi

# Marker 2: version or build-SHA confirmed running on prod
if grep -qiE 'running.*version|version.*running|build.SHA.*prod|deployed.*SHA|image.*running|container.*version|systemctl.*status.*active' "$ARCHIVE_DOC" 2>/dev/null; then
    VERIFY=$((VERIFY + 1))
fi

# Marker 3: health/log probe evidence after deploy
if grep -qiE 'health.*probe.*passed|log.probe.*confirmed|post.deploy.*healthy|prod.*ready|readiness.*probe' "$ARCHIVE_DOC" 2>/dev/null; then
    VERIFY=$((VERIFY + 1))
fi

# At least 2 markers needed.
if [ "$VERIFY" -ge 2 ]; then
    exit 0
fi

# One more check: BLOCKED/unverifiable with operator confirmation is valid
BLOCKED_PATTERN=0
if grep -qiE 'BLOCKED.*prod|prod.*unreachable|unverifiable.*prod|prod.*BLOCKED' "$ARCHIVE_DOC" 2>/dev/null; then
    BLOCKED_PATTERN=1
fi
if [ "$BLOCKED_PATTERN" -eq 1 ]; then
    if grep -qiE 'operator.*confirmed|operator.*approved|out.of.band.*verif|explicit.*operator' "$ARCHIVE_DOC" 2>/dev/null; then
        exit 0   # BLOCKED with operator confirmation is valid
    fi
    # BLOCKED without operator confirmation → error
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: prod verification is BLOCKED/unverifiable without operator confirmation"
        echo "  Archive: $ARCHIVE_DOC"
        echo "  Action: obtain operator out-of-band confirmation per dr-archive.md:279 and record it."
    fi
    exit 1
fi

if [ "$REPORT_MODE" -eq 1 ]; then
    echo "BLOCKED: deploy-class task lacks prod-merge verification evidence ($VERIFY of 2 markers)"
    echo "  Task: $TASK_DESC"
    echo "  Archive: $ARCHIVE_DOC"
    echo "  Action: verify prod merge per dr-archive.md § 0.4 and record evidence."
fi
exit 1
