#!/usr/bin/env bash
# semantic_parser.sh — Phase 1 stub.
# Phase 2 (TUNE-0165) replaces this with a full grep+sed anchor matcher and
# subagent inference layer.
# V-AC: 14 (rule-based confidence > 0 for known commands).
set -euo pipefail

# parse <input> — print {command, confidence, source} JSON. Always exit 0.
parse() {
  local input="${1:-}"
  local conf=0
  case "$input" in
    */dr-init*|*/dr-prd*|*/dr-plan*|*/dr-do*|*/dr-qa*|*/dr-archive*)
      conf="0.95"
      ;;
    *)
      conf="0"
      ;;
  esac
  jq -n -c \
    --arg cmd "$input" \
    --argjson conf "$conf" \
    '{command:$cmd, confidence:$conf, source:"rule_phase1_stub"}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: semantic_parser.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
