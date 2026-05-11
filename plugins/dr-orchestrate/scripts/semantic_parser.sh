#!/usr/bin/env bash
# semantic_parser.sh — rule-based first-pass classifier.
# Hit → confidence ≥ 0.95, source=rule_phase1_stub.
# Miss → confidence 0, source=rule_phase2_miss (subagent_resolver.sh handles
# the fallback inference in TUNE-0165 M6).
# V-AC: 14 (rule-based confidence > 0 for known commands).
set -euo pipefail

# parse <input> — print {command, confidence, source} JSON. Always exit 0.
parse() {
  local input="${1:-}"
  local conf=0
  local source="rule_phase2_miss"
  case "$input" in
    */dr-init*|*/dr-prd*|*/dr-plan*|*/dr-do*|*/dr-qa*|*/dr-archive*)
      conf="0.95"
      source="rule_phase1_stub"
      ;;
  esac
  jq -n -c \
    --arg cmd "$input" \
    --argjson conf "$conf" \
    --arg src "$source" \
    '{command:$cmd, confidence:$conf, source:$src}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: semantic_parser.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
