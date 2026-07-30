#!/usr/bin/env bash
# semantic_parser.sh — rule-based first-pass classifier.
# Reads merged ruleset from rules_loader.sh (default + user + learned).
# Hit  → confidence and selected trusted action with rule provenance.
# Miss → confidence 0, source=rule_phase2_miss (subagent_resolver.sh handles
# the fallback inference in TUNE-0165 M6).
# V-AC: 14 (rule-based confidence > 0 for known commands).
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=rules_loader.sh
source "$DR_ORCH_DIR/scripts/rules_loader.sh"

# parse <input> — print {command, confidence, source} JSON. Always exit 0.
parse() {
  local input="${1:-}"
  local conf=0
  local source="rule_phase2_miss" selected_action="" provenance=""

  local rules
  rules="$(load 2>/dev/null || echo '[]')"

  local match action rule_conf rule_provenance
  while IFS=$'\t' read -r match action rule_conf rule_provenance; do
    [[ -z "$match" ]] && continue
    if { [[ "$rule_provenance" == "learned" ]] && [[ "$input" == "$match" ]]; } \
      || { [[ "$rule_provenance" != "learned" ]] && [[ "$input" == *"$match"* ]]; }; then
      if awk -v a="$rule_conf" -v b="$conf" 'BEGIN{exit !(a>b)}'; then
        conf="$rule_conf"
        source="rule_phase1_stub"
        selected_action="$action"
        provenance="$rule_provenance"
      fi
    fi
  done < <(printf '%s' "$rules" | jq -r '.[] | [.match, .action, (.confidence|tostring), .provenance] | @tsv')

  jq -n -c \
    --arg cmd "$input" \
    --argjson conf "$conf" \
    --arg src "$source" \
    --arg action "$selected_action" \
    --arg provenance "$provenance" \
    '{command:$cmd, confidence:$conf, source:$src,
      action:$action, provenance:$provenance}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: semantic_parser.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
