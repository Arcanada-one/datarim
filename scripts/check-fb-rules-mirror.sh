#!/usr/bin/env bash
# check-fb-rules-mirror.sh — FB-rules consumer-mirror rollout tracker.
#
# Every Datarim consumer that enables the `dr-orchestrate` plugin MUST first
# mirror the canonical Autonomous Agent Operating Rules (FB-1..FB-8) into its
# own ecosystem `CLAUDE.md` at rank-1 mandate level. The framework ships the
# machine-readable contract surface (dev-tools/rules/fb-rules.yaml); the
# operator-readable rule text is ecosystem-owned and audit-tagged per consumer.
#
# This checker verifies a consumer `CLAUDE.md` mirrors that canonical text by
# asserting two invariants against the canonical policy YAML:
#   1. Anchor present  — the section heading string "Autonomous Agent Operating
#      Rules" appears (case-sensitive) in the consumer CLAUDE.md.
#   2. Rule coverage   — every `rule_id` in the canonical policy YAML is cited
#      verbatim (FB-1 .. FB-8, exact case) in the consumer CLAUDE.md.
#
# It is stack-agnostic and ecosystem-agnostic: no consumer repo path, IP, or
# hostname is hard-coded. The consumer CLAUDE.md is supplied by the caller
# (positional arg or env), the canonical YAML is resolved inside this repo.
#
# Usage:
#   ./scripts/check-fb-rules-mirror.sh <consumer-CLAUDE.md>
#   ./scripts/check-fb-rules-mirror.sh --quiet <consumer-CLAUDE.md>
#   FB_RULES_CONSUMER_CLAUDE=<path> ./scripts/check-fb-rules-mirror.sh
#
# Environment:
#   DATARIM_REPO_DIR            override repo root (default: parent of script dir)
#   FB_RULES_CANONICAL          override canonical policy YAML path
#   FB_RULES_CONSUMER_CLAUDE    consumer CLAUDE.md (alternative to positional arg)
#
# Exit codes:
#   0  mirror in sync — anchor present and every canonical rule_id is cited
#   1  drift detected — anchor and/or one or more rule_ids missing
#   2  error (missing canonical YAML, missing consumer file, usage error)
#
# Read-only. No writes anywhere. Intended to be called:
#   - by `/dr-plugin enable` as a pre-flight gate (see scripts/dr-plugin.sh);
#   - from CI / datarim-doctor as a non-fatal advisory rollout audit;
#   - manually by an operator to check a new consumer before rollout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${DATARIM_REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

QUIET=false
CONSUMER=""
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        -h|--help)
            sed -n '2,45p' "$0"
            exit 0
            ;;
        --*)
            echo "ERROR: unknown option: $arg" >&2
            exit 2
            ;;
        *) CONSUMER="$arg" ;;
    esac
done

# Consumer CLAUDE.md: positional arg first, then env fallback.
if [ -z "$CONSUMER" ]; then
    CONSUMER="${FB_RULES_CONSUMER_CLAUDE:-}"
fi
if [ -z "$CONSUMER" ]; then
    echo "ERROR: consumer CLAUDE.md path required (positional arg or FB_RULES_CONSUMER_CLAUDE)." >&2
    echo "Usage: $0 [--quiet] <consumer-CLAUDE.md>" >&2
    exit 2
fi
if [ ! -f "$CONSUMER" ]; then
    echo "ERROR: consumer CLAUDE.md not found: $CONSUMER" >&2
    exit 2
fi

# Canonical policy YAML: dev-tools core path (from TUNE-0436), overridable.
CANONICAL="${FB_RULES_CANONICAL:-$REPO_DIR/dev-tools/rules/fb-rules.yaml}"
if [ ! -f "$CANONICAL" ]; then
    echo "ERROR: canonical FB-rules policy not found: $CANONICAL" >&2
    exit 2
fi

# The section-heading anchor the consumer mirror is asserted to carry.
ANCHOR="Autonomous Agent Operating Rules"

# Canonical rule ids (exact case), extracted from the policy YAML.
RULE_IDS="$(awk '
    /^[[:space:]]*-[[:space:]]*rule_id:[[:space:]]*/ {
        sub("^[[:space:]]*-[[:space:]]*rule_id:[[:space:]]*", "")
        sub("[[:space:]]*#.*$", "")
        sub("[[:space:]]+$", "")
        gsub("[\"\x27]", "")
        print
    }
' "$CANONICAL")"

if [ -z "$RULE_IDS" ]; then
    echo "ERROR: no rule_id entries found in canonical policy: $CANONICAL" >&2
    exit 2
fi

$QUIET || {
    echo "FB-rules Consumer Mirror Check"
    echo "  canonical: $CANONICAL"
    echo "  consumer:  $CONSUMER"
    echo ""
}

drift=0

# Invariant 1 — anchor heading present.
if grep -Fq -- "$ANCHOR" "$CONSUMER"; then
    $QUIET || echo "  [ok]      anchor present: \"$ANCHOR\""
else
    drift=1
    $QUIET || echo "  [MISSING] anchor: \"$ANCHOR\""
fi

# Invariant 2 — every canonical rule_id cited verbatim.
missing_ids=""
for rid in $RULE_IDS; do
    if grep -Fq -- "$rid" "$CONSUMER"; then
        $QUIET || echo "  [ok]      rule cited: $rid"
    else
        drift=1
        missing_ids="$missing_ids $rid"
        $QUIET || echo "  [MISSING] rule not cited: $rid"
    fi
done

$QUIET || echo ""

if [ "$drift" -ne 0 ]; then
    echo "DRIFT: consumer CLAUDE.md does not fully mirror canonical FB-rules." >&2
    echo "       consumer: $CONSUMER" >&2
    [ -n "$missing_ids" ] && echo "       missing rule ids:$missing_ids" >&2
    echo "       Mirror the canonical Autonomous Agent Operating Rules (FB-1..FB-8)" >&2
    echo "       text into the consumer ecosystem CLAUDE.md at rank-1 mandate level" >&2
    echo "       before enabling the dr-orchestrate plugin." >&2
    exit 1
fi

$QUIET || echo "IN SYNC: consumer CLAUDE.md mirrors canonical FB-rules."
exit 0
