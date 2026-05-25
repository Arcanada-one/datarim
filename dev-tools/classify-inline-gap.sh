#!/usr/bin/env bash
# classify-inline-gap.sh — L1 Inline Resolution Rule classifier
#
# Inputs (via --flags, all required):
#   --files <int>       Number of files touched by the gap fix
#   --loc <int>         Total LoC delta (absolute)
#   --contract <bool>   true|false — does fix change API/schema/contract?
#   --hard-gated <bool> true|false — does fix match autonomous-agents.md:30-32 hard-gated list?
#
# Output (stdout, exit 0):
#   L1-A   — single file, ≤50 LoC, no contract change, not hard-gated → fix inline
#   L2+/B  — multi-file OR >50 LoC OR contract change → backlog item
#   HARD   — hard-gated action → operator-escalate (overrides scope check)
#
# Exit codes:
#   0 — classification produced
#   2 — usage error

set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: classify-inline-gap.sh --files <int> --loc <int> --contract <true|false> --hard-gated <true|false>

Classifies a discovered gap per skills/autonomous-mode.md § L1 Inline Resolution Rule.
EOF
    exit 2
}

FILES=""
LOC=""
CONTRACT=""
HARD_GATED=""

while [ $# -gt 0 ]; do
    case "$1" in
        --files)       FILES="$2";       shift 2 ;;
        --loc)         LOC="$2";         shift 2 ;;
        --contract)    CONTRACT="$2";    shift 2 ;;
        --hard-gated)  HARD_GATED="$2";  shift 2 ;;
        -h|--help)     usage ;;
        *) echo "ERROR: unknown flag: $1" >&2; usage ;;
    esac
done

# Input validation
[ -z "$FILES" ] || [ -z "$LOC" ] || [ -z "$CONTRACT" ] || [ -z "$HARD_GATED" ] && usage

if ! [[ "$FILES" =~ ^[0-9]+$ ]] || ! [[ "$LOC" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --files and --loc MUST be non-negative integers" >&2
    exit 2
fi

if [ "$CONTRACT" != "true" ] && [ "$CONTRACT" != "false" ]; then
    echo "ERROR: --contract MUST be true|false" >&2
    exit 2
fi

if [ "$HARD_GATED" != "true" ] && [ "$HARD_GATED" != "false" ]; then
    echo "ERROR: --hard-gated MUST be true|false" >&2
    exit 2
fi

# Classification (hard-gated takes precedence over scope check)
if [ "$HARD_GATED" = "true" ]; then
    echo "HARD"
    exit 0
fi

if [ "$FILES" -le 1 ] && [ "$LOC" -le 50 ] && [ "$CONTRACT" = "false" ]; then
    echo "L1-A"
else
    echo "L2+/B"
fi
