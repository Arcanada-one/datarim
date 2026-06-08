#!/usr/bin/env bash
# context_builder.sh — minimal context injection for fleet agents (design C2).
#
# Assembles ONLY the five allowed context components for a per-task agent and
# enforces the per-level token budget BEFORE the session is launched:
#   1. per-level starter skill   (skills/fleet/L<N>-*/SKILL.md body)
#   2. execution environment      (env reference string)
#   3. project space              (project references string)
#   4. knowledge-base reference   (a retrieval pointer, NOT a dump)
#   5. task brief                 (objective/format/tools/boundaries)
#
# Full project context, task history, and unrelated documents are NEVER loaded.
#
# The token budget is read from the level's fleet skill frontmatter via a
# frontmatter-only extraction (a full-file YAML parse breaks on the markdown
# body — the colon in prose). The guard is fail-closed: an assembled context
# over budget returns exit 3 and emits nothing usable, rather than leaking an
# oversized context into the live agent.
#
# Usage:
#   context_builder.sh build_context <level> <brief-file> <projects-ref> <env-ref>
#   context_builder.sh _read_budget  <level>
#
# Exit codes:
#   0  context assembled within budget (printed to stdout)
#   2  usage error (bad args / missing brief)
#   3  budget exceeded after reduce — fail-closed
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Framework repo root (holds skills/fleet/*). Overridable for tests.
: "${DR_FLEET_REPO:=$(cd "$DR_ORCH_DIR/../.." && pwd)}"
# Token estimator divisor: bytes-per-token approximation, consistent with the
# read-guard heuristic. Conservative (smaller divisor → higher estimate).
: "${DR_FLEET_TOKEN_DIVISOR:=4}"

# Map a complexity level (1..5) to its fleet skill directory.
_level_dir() {
    case "$1" in
        1) echo "l1-basic" ;;
        2) echo "l2-structured" ;;
        3) echo "l3-analyst" ;;
        4) echo "l4-expert" ;;
        5) echo "l5-autonomous" ;;
        *) return 2 ;;
    esac
}

# _read_budget <level> — echo the integer context_budget_tokens for the level,
# parsed from the fleet skill frontmatter ONLY (never yq on the whole file).
_read_budget() {
    local level="$1" dir skill_md budget
    dir="$(_level_dir "$level")" || { echo "ERROR: unknown level: $level" >&2; return 2; }
    skill_md="$DR_FLEET_REPO/skills/fleet/$dir/SKILL.md"
    [ -f "$skill_md" ] || { echo "ERROR: fleet skill not found: $skill_md" >&2; return 1; }
    budget="$(awk '/^---$/{c++;next} c==1' "$skill_md" \
        | grep -E '^[[:space:]]*context_budget_tokens:' \
        | head -1 | sed -E 's/.*context_budget_tokens:[[:space:]]*//')"
    [[ "$budget" =~ ^[0-9]+$ ]] || { echo "ERROR: no integer context_budget_tokens for level $level" >&2; return 1; }
    printf '%s\n' "$budget"
}

# _token_estimate <text> — crude byte-based token estimate (bytes / divisor).
_token_estimate() {
    local bytes
    bytes="$(printf '%s' "$1" | wc -c | tr -d ' ')"
    echo $(( bytes / DR_FLEET_TOKEN_DIVISOR ))
}

# _skill_body <level> — the fleet skill instruction body (after frontmatter).
_skill_body() {
    local dir skill_md
    dir="$(_level_dir "$1")" || return 2
    skill_md="$DR_FLEET_REPO/skills/fleet/$dir/SKILL.md"
    [ -f "$skill_md" ] || return 1
    awk '/^---$/{c++;next} c>=2' "$skill_md"
}

# build_context <level> <brief-file> <projects-ref> <env-ref>
build_context() {
    local level="${1:-}" brief_file="${2:-}" projects="${3:-}" env_ref="${4:-}"
    [ -n "$level" ] && [ -n "$brief_file" ] || { echo "ERROR: usage: build_context <level> <brief-file> <projects-ref> <env-ref>" >&2; return 2; }
    _level_dir "$level" >/dev/null || { echo "ERROR: unknown level: $level" >&2; return 2; }
    [ -f "$brief_file" ] || { echo "ERROR: brief file not found: $brief_file" >&2; return 2; }

    local budget skill brief assembled
    budget="$(_read_budget "$level")" || return 1
    skill="$(_skill_body "$level")" || return 1
    brief="$(cat "$brief_file")"

    # KB component is a retrieval REFERENCE, never a dump (design C2).
    local kb_ref="retrieval-on-demand via Scrutator (semantic NN); query at runtime, do not preload"

    assembled="$(cat <<CTX
=== SKILL ===
$skill
=== ENV ===
$env_ref
=== PROJECTS ===
$projects
=== KB-REF ===
$kb_ref
=== BRIEF ===
$brief
CTX
)"

    # Token-budget guard — fail-closed BEFORE returning the context.
    local est
    est="$(_token_estimate "$assembled")"
    if [ "$est" -gt "$budget" ]; then
        echo "ERROR: assembled context ${est} tokens exceeds level-${level} budget ${budget} (reduce RAG top-k / shorten brief)" >&2
        return 3
    fi

    printf '%s\n' "$assembled"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    fn="${1:-}"; shift || true
    [ -n "$fn" ] || { echo "usage: context_builder.sh <fn> [args]" >&2; exit 2; }
    "$fn" "$@"
fi
