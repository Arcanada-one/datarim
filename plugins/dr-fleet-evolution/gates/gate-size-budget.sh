#!/usr/bin/env bash
# gates/gate-size-budget.sh — per-candidate token-budget gate.
#
# argv[1] = candidate file (SKILL.md), argv[2] = skill level (optional; only
# used in messages — the budget is read from the candidate's own frontmatter).
# exit 0 = within budget, exit 1 = over budget, exit 2 = usage / no budget.
#
# Token estimate = chars / 4 (same divisor convention as
# dev-tools/measure-skill-token-cost.sh). The budget is the candidate's
# metadata.context_budget_tokens frontmatter field.

set -o pipefail

usage() { echo "Usage: $(basename "$0") <candidate-file> [skill-level]" >&2; }

main() {
    local candidate=${1:-}
    local level=${2:-?}
    [ -n "$candidate" ] || { usage; exit 2; }
    [ -f "$candidate" ] || { echo "gate-size-budget: file not found: $candidate" >&2; exit 2; }

    local budget
    budget=$(sed -n '/^---$/,/^---$/p' "$candidate" \
        | grep -E '^[[:space:]]*context_budget_tokens:' \
        | head -n1 \
        | sed -E 's/^[[:space:]]*context_budget_tokens:[[:space:]]*//; s/[[:space:]]+$//')

    if ! [[ "$budget" =~ ^[0-9]+$ ]]; then
        echo "gate-size-budget: candidate missing numeric context_budget_tokens (level $level)" >&2
        exit 2
    fi

    local chars tokens
    chars=$(wc -c < "$candidate")
    tokens=$(( chars / 4 ))

    if [ "$tokens" -gt "$budget" ]; then
        echo "gate-size-budget: candidate ~${tokens} tokens exceeds budget ${budget} (level $level)" >&2
        exit 1
    fi
    exit 0
}

main "$@"
