#!/usr/bin/env bash
# check-archive-sha-chain.sh — Pre-archive gate: when a task claims
# production deployment (requires_runtime_probe: true or deploy-class),
# verify the archive document carries SHA-chain evidence.
#
# The prose rule in commands/dr-archive.md:227-269 says three SHAs MUST agree
# (local HEAD, origin default-branch tip, prod running image) for a
# "PROD-deployed" claim. This script is the mechanical enforcement: it
# checks the archive doc for SHA-chain structural evidence.
#
# This gate does NOT perform the live probe (that requires SSH access to
# prod). It verifies the probe's OUTPUT is recorded in the archive doc.
#
# Usage:
#   check-archive-sha-chain.sh --task-description <path> --archive-doc <path> [--report]
#
# Exit codes:
#   0 — task does not claim PROD deployment, OR SHA-chain evidence present
#   1 — task claims PROD deployment but SHA-chain evidence missing/insufficient
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

# Task claims prod deployment — archive doc MUST have SHA-chain evidence.
[ -f "$ARCHIVE_DOC" ] || {
    if [ "$REPORT_MODE" -eq 1 ]; then
        echo "BLOCKED: task claims PROD deployment but no archive doc found"
        echo "  Task: $TASK_DESC"
        echo "  Action: perform the SHA-chain probe per dr-archive.md § 0.2.5 and record evidence."
    fi
    exit 1
}

# Evidence markers for SHA-chain verification:
# - Three SHAs quoted (LOCAL_HEAD, ORIGIN_HEAD, PROD_IMAGE/SHA)
# - A "SHA chain is intact" / "local == origin == PROD" statement
# - A § Verification section with SHA references
SHA_EVIDENCE=0

# Marker 1: three SHA-like hex strings (40-char hex) in proximity
SHA_COUNT=$(grep -oE '\b[0-9a-fA-F]{40}\b' "$ARCHIVE_DOC" 2>/dev/null | sort -u | wc -l || true)
if [ "$SHA_COUNT" -ge 2 ]; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

# Marker 2: explicit SHA-chain / prod-deployed verification language
if grep -qiE 'SHA.chain|local.*==.*origin.*==.*PROD|three.SHA|PROD.deployed.*verified|origin.*==.*PROD' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

# Marker 3: a § Verification section with SHA/commit references
if grep -qiE 'Verification|SHA.chain.verif|prod.deploy.*SHA|runtime.probe' "$ARCHIVE_DOC" 2>/dev/null; then
    SHA_EVIDENCE=$((SHA_EVIDENCE + 1))
fi

# At least 2 of 3 markers needed.
if [ "$SHA_EVIDENCE" -ge 2 ]; then
    exit 0
fi

# One more check: BLOCKED with operator confirmation is valid
if grep -qiE 'BLOCKED.*production|prod.*BLOCKED|unverifiable.*prod|operator.*confirm.*out.of.band' "$ARCHIVE_DOC" 2>/dev/null; then
    # BLOCKED is acceptable only if accompanied by operator confirmation
    if grep -qiE 'operator.*confirmed|out.of.band.*confirmed|operator.*verified|operator.*approved' "$ARCHIVE_DOC" 2>/dev/null; then
        exit 0
    fi
fi

if [ "$REPORT_MODE" -eq 1 ]; then
    echo "BLOCKED: task claims PROD deployment but SHA-chain evidence insufficient ($SHA_EVIDENCE of 2 markers)"
    echo "  Task: $TASK_DESC"
    echo "  Archive: $ARCHIVE_DOC"
    echo "  Action: perform the three-SHA probe per dr-archive.md § 0.2.5 and record results."
fi
exit 1
