#!/usr/bin/env bash
# check-prod-merge-blocked.sh -- Pre-archive gate: for deploy-class tasks,
# refuse to archive when the prod merge verification is BLOCKED or
# unverifiable without operator confirmation.
#
# The prose rules in commands/dr-archive.md:279 (never auto-archive on
# unverifiable prod) and :386 (archive MUST NOT proceed until prod merge
# is done AND verified) are UNENFORCED. This script is the mechanical
# enforcement for both.
#
# Two-tier check (structured beats regex):
#   1. PRIMARY: archive doc frontmatter field prod_verification.
#      Values: verified | blocked-operator-approved | n-a.
#      verified or blocked-operator-approved -> pass.
#      Absent -> fall through to prose check.
#   2. FALLBACK: broad DISJUNCTIVE prose evidence. Any of these signal
#      verification was performed (vocabulary from real archive docs,
#      not rigid word-order patterns -- "probe returned HTTP 200" and
#      "version matches" are as valid as "health probe passed" and
#      "running version"):
#        - post-deploy health status (returned/HTTP/200/OK/healthy/active/passed)
#        - version or SHA confirmed (matches/confirmed/running/deployed)
#        - operator sign-off (confirmed/approved/verified/out-of-band)
#      BLOCKED without operator confirmation -> block.
#
# Usage:
#   check-prod-merge-blocked.sh --task-description <path> --archive-doc <path> [--report]
#
# Exit codes:
#   0 -- not deploy-class, OR prod-merge verification confirmed
#   1 -- deploy-class but prod-merge verification missing or blocked
#   2 -- usage error
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

# Check if deploy-class.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_CLASSIFIER="$SCRIPT_DIR/check-deploy-class.sh"

IS_DEPLOY=0
if [ -x "$DEPLOY_CLASSIFIER" ] && [ -f "$TASK_DESC" ]; then
    if "$DEPLOY_CLASSIFIER" --task-description "$TASK_DESC" >/dev/null 2>&1; then
        IS_DEPLOY=1
    fi
fi

if [ "$IS_DEPLOY" -eq 0 ] && [ -f "$TASK_DESC" ]; then
    if grep -qiE 'deploy|systemd|nginx|docker.compose|production|prod.deploy|cutover' "$TASK_DESC" 2>/dev/null; then
        IS_DEPLOY=1
    fi
fi

[ "$IS_DEPLOY" -eq 1 ] || exit 0

# Deploy-class: archive doc MUST have prod-merge verification evidence.
[ -f "$ARCHIVE_DOC" ] || {
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: deploy-class task but no archive doc found"
        echo "  Task: $TASK_DESC"
        echo "  Action: perform prod-merge verification per dr-archive.md § 0.4."
    fi
    exit 1
}

# --- TIER 1: structured frontmatter field (deterministic) ------------------
PROD_VERIFICATION=$(awk '/^---$/ {c++; next}
    c==1 && /^prod_verification:/ {
        v=$0; sub(/^prod_verification:[[:space:]]*/, "", v);
        gsub(/[[:space:]]+$/, "", v);
        print v; exit
    }
    c>=2 {exit}' "$ARCHIVE_DOC" 2>/dev/null || true)

if [ -n "$PROD_VERIFICATION" ]; then
    case "$PROD_VERIFICATION" in
        verified|blocked-operator-approved)
            exit 0 ;;
        n-a)
            exit 0 ;;
        *)
            if [ "$REPORT_MODE" -eq 1 ]; then
                echo "BLOCKED: prod_verification frontmatter is '$PROD_VERIFICATION' (expected: verified | blocked-operator-approved | n-a)"
                echo "  Archive: $ARCHIVE_DOC"
            fi
            exit 1 ;;
    esac
fi

# --- TIER 2: broad disjunctive prose fallback ------------------------------
# Each group is a DISJUNCTION: ANY match in the group counts as one evidence
# point. Vocabulary from real archive docs -- "probe returned HTTP 200" and
# "version matches" are as valid as "health probe passed" and "running version".

# Group A: any health/probe/status indicator
HEALTH_SCORE=0
if grep -qiE 'health.*(returned|HTTP|200|OK|active|passed|healthy|confirmed|running|up|live)' "$ARCHIVE_DOC" 2>/dev/null; then
    HEALTH_SCORE=1
fi
if grep -qiE '(probe|check|verified|confirmed|tested).*(returned|HTTP|200|OK|active|passed|healthy|up|live|success)' "$ARCHIVE_DOC" 2>/dev/null; then
    HEALTH_SCORE=1
fi

# Group B: any version/SHA/image match indicator
VERSION_SCORE=0
if grep -qiE 'version.*(match|confirm|OK|correct|same|deploy|running|prod|live)' "$ARCHIVE_DOC" 2>/dev/null; then
    VERSION_SCORE=1
fi
if grep -qiE '(running|deploy|prod|live|image).*(version|SHA|commit|tag|match|confirm|OK|correct)' "$ARCHIVE_DOC" 2>/dev/null; then
    VERSION_SCORE=1
fi
if grep -qiE '(build|image|container).*(running|deploy|prod|match|confirm|OK|SHA|tag|version)' "$ARCHIVE_DOC" 2>/dev/null; then
    VERSION_SCORE=1
fi

# Group C: operator sign-off
OPERATOR_SCORE=0
if grep -qiE 'operator.*(confirm|approv|verif|sign|OK|ack)' "$ARCHIVE_DOC" 2>/dev/null; then
    OPERATOR_SCORE=1
fi

TOTAL_SCORE=$((HEALTH_SCORE + VERSION_SCORE + OPERATOR_SCORE))
# Need at least 2 of 3 groups with evidence, OR 1 group + explicit PASS marker.
PASS_MARKER=0
if grep -qiE 'PASS|SHA.chain.*intact|prod.deploy.*confirmed|post.merge.*done.*verified|prod.*verified' "$ARCHIVE_DOC" 2>/dev/null; then
    PASS_MARKER=1
fi

if [ "$TOTAL_SCORE" -ge 2 ] || { [ "$TOTAL_SCORE" -ge 1 ] && [ "$PASS_MARKER" -eq 1 ]; }; then
    exit 0
fi

# --- BLOCKED check ---------------------------------------------------------
BLOCKED_PATTERN=0
if grep -qiE 'BLOCKED|unreachable|unverifiable|cannot.connect|timeout' "$ARCHIVE_DOC" 2>/dev/null; then
    BLOCKED_PATTERN=1
fi
if [ "$BLOCKED_PATTERN" -eq 1 ]; then
    if grep -qiE 'operator.*(confirm|approv|verif|sign|OK|ack)|out.of.band|manual.*verif' "$ARCHIVE_DOC" 2>/dev/null; then
        exit 0   # BLOCKED with operator confirmation is valid
    fi
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: prod verification is BLOCKED/unverifiable without operator confirmation"
        echo "  Archive: $ARCHIVE_DOC"
        echo "  Action: obtain operator out-of-band confirmation per dr-archive.md:279 and record it."
    fi
    exit 1
fi

if [ "$REPORT_MODE" -eq 1 ]; then
    echo "BLOCKED: deploy-class task lacks prod-merge verification evidence"
    echo "  Scores: health=$HEALTH_SCORE version=$VERSION_SCORE operator=$OPERATOR_SCORE (need >=2)"
    echo "  Task: $TASK_DESC"
    echo "  Archive: $ARCHIVE_DOC"
    echo "  Action: verify prod merge per dr-archive.md § 0.4 and record evidence,"
    echo "    or add 'prod_verification: verified' to archive frontmatter."
fi
exit 1
