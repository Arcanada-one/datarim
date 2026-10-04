#!/usr/bin/env bash
# check-archive-sha-chain.sh — Pre-archive gate: when a task claims
# production deployment (requires_runtime_probe: true), verify the
# archive document carries SHA-chain evidence.
#
# The prose rule in commands/dr-archive.md:227-269 says three SHAs MUST agree
# for a "PROD-deployed" claim. This script is the mechanical enforcement.
#
# Two-tier check (structured beats regex):
#   1. PRIMARY: archive doc frontmatter field prod_verification.
#      verified | blocked-operator-approved -> pass.
#      Absent -> fall through to prose.
#   2. FALLBACK: broad disjunctive evidence markers (any vocabulary).
#
# This gate does NOT perform the live probe (requires SSH to prod).
# It verifies the probe's OUTPUT is recorded in the archive doc.
#
# Usage:
#   check-archive-sha-chain.sh --task-description <path> --archive-doc <path> [--report]
#
# Exit codes:
#   0 — task does not claim PROD deployment, OR evidence present
#   1 — task claims PROD deployment but evidence missing
#   2 — usage error
#
# Called by /dr-archive Step 0.2.5 (post-probe self-check) and Step 2
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

# Check if task claims prod deployment.
CLAIMS_PROD=0
if [ -f "$TASK_DESC" ]; then
    if grep -q 'requires_runtime_probe:[[:space:]]*true' "$TASK_DESC" 2>/dev/null; then
        CLAIMS_PROD=1
    fi
fi
[ "$CLAIMS_PROD" -eq 1 ] || exit 0

[ -f "$ARCHIVE_DOC" ] || {
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: task claims PROD deployment but no archive doc found"
        echo "  Task: $TASK_DESC"
        echo "  Action: perform the SHA-chain probe per dr-archive.md § 0.2.5."
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
SHA_EVIDENCE=0

# Group A: SHA hex strings (40-char) in proximity — at least 2 suggests a chain.
SHA_COUNT=$(grep -oE '\b[0-9a-fA-F]{40}\b' "$ARCHIVE_DOC" 2>/dev/null | sort -u | wc -l || true)
if [ "${SHA_COUNT:-0}" -ge 2 ]; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

# Group B: any verification/SHA-chain/prod-deployed language (broad disjunction).
if grep -qiE '(SHA|commit|hash|chain).*(intact|verified|match|agree|confirmed|OK|correct|same)' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
elif grep -qiE '(prod|production|deploy).*(verified|confirmed|deployed|running|live|checked|probed|OK)' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
elif grep -qiE '(origin|local|HEAD).*(match|agree|verified|confirmed|same|OK|intact|==)' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

# Group C: explicit Verification section with any content.
if grep -qiE '##\s*(Verification|SHA.chain|Runtime.probe|Prod.*(deploy|verif|check))' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

# Group D: explicit PASS marker.
if grep -qiE 'PASS|SHA.chain.*intact|local.*==.*origin.*==.*PROD|prod.*deployed.*confirmed' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

if [ "$SHA_EVIDENCE" -ge 2 ]; then
    exit 0
fi

# --- BLOCKED with operator confirmation ------------------------------------
if grep -qiE 'BLOCKED|unreachable|unverifiable|cannot.connect|timeout' "$ARCHIVE_DOC" 2>/dev/null; then
    if grep -qiE 'operator.*(confirm|approv|verif|sign|OK|ack)|out.of.band|manual.*verif' "$ARCHIVE_DOC" 2>/dev/null; then
        exit 0
    fi
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: production verification is BLOCKED without operator confirmation"
        echo "  Archive: $ARCHIVE_DOC"
        echo "  Action: obtain operator out-of-band confirmation per dr-archive.md:279."
    fi
    exit 1
fi

if [ "$REPORT_MODE" -eq 1 ]; then
    echo "BLOCKED: task claims PROD deployment but SHA-chain evidence insufficient ($SHA_EVIDENCE of 2 groups)"
    echo "  Task: $TASK_DESC"
    echo "  Archive: $ARCHIVE_DOC"
    echo "  Action: perform the three-SHA probe per dr-archive.md § 0.2.5 and record results,"
    echo "    or add 'prod_verification: verified' to archive frontmatter."
fi
exit 1
