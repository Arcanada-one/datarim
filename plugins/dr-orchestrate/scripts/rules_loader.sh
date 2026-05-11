#!/usr/bin/env bash
# rules_loader.sh — 3-source rules merge (default → user → learned).
# TUNE-0165 M1. Read-only loader; Phase C auto-learn write path deferred.
# Output: JSON array of {match, action, confidence} on stdout, deduped by
# match-key with last-write-wins (learned beats user beats default).
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_RULES_DEFAULT:=$DR_ORCH_DIR/rules/default.yaml}"
: "${DR_ORCH_RULES_USER:=$HOME/.config/dr-orchestrate/rules/user.yaml}"
: "${DR_ORCH_RULES_LEARNED:=${STATE_DIR:-$HOME/.local/share/dr-orchestrate/state}/learned-rules.yaml}"

_extract() {
  local src="$1"
  [[ -f "$src" && -s "$src" ]] || { echo '[]'; return 0; }
  yq eval -o=json '.patterns // []' "$src" 2>/dev/null || echo '[]'
}

load() {
  local d u l
  d="$(_extract "$DR_ORCH_RULES_DEFAULT")"
  u="$(_extract "$DR_ORCH_RULES_USER")"
  l="$(_extract "$DR_ORCH_RULES_LEARNED")"
  jq -c -s '
    .[0] + .[1] + .[2]
    | reduce .[] as $x ({}; .[$x.match] = $x)
    | [.[]]
  ' <(echo "$d") <(echo "$u") <(echo "$l")
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: rules_loader.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
