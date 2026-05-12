#!/usr/bin/env bash
# rules_loader.sh — 3-source prompt-pattern rules merge (default → user → learned).
# TUNE-0165 M1. Read-only loader; Phase C auto-learn write path deferred.
# Output: JSON array of {match, action, confidence} on stdout, deduped by
# match-key with last-write-wins (learned beats user beats default).
#
# TUNE-0185 Phase 4: orthogonal load_fb_policy() entry point for fb-rules.yaml
# (Autonomous Agent Operating Rules policy block). Separate schema; not merged
# into the prompt-pattern stream — different consumers, different cardinality.
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_RULES_DEFAULT:=$DR_ORCH_DIR/rules/default.yaml}"
: "${DR_ORCH_RULES_USER:=$HOME/.config/dr-orchestrate/rules/user.yaml}"
: "${DR_ORCH_RULES_LEARNED:=${STATE_DIR:-$HOME/.local/share/dr-orchestrate/state}/learned-rules.yaml}"
: "${DR_ORCH_FB_RULES:=$DR_ORCH_DIR/rules/fb-rules.yaml}"

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

# load_fb_policy — emit Autonomous Agent Operating Rules policy as JSON array.
# Schema is documented in rules/fb-rules.yaml header. Consumers: subagent_resolver,
# escalation_backend, audit_sink. Empty array when file missing (fail-open by
# design — runner falls back to default escalation policy and logs a warning).
load_fb_policy() {
  local src="${1:-$DR_ORCH_FB_RULES}"
  [[ -f "$src" && -s "$src" ]] || { echo '[]'; return 0; }
  yq eval -o=json '.rules // []' "$src" 2>/dev/null || echo '[]'
}

# load_fb_hard_gates — emit hard-gated action kinds as JSON array of strings.
# Mirror of ecosystem CLAUDE.md § Hard-gated actions. Consumer compares planned
# action.kind against this list; match ⇒ refuse auto-execution unconditionally.
load_fb_hard_gates() {
  local src="${1:-$DR_ORCH_FB_RULES}"
  [[ -f "$src" && -s "$src" ]] || { echo '[]'; return 0; }
  yq eval -o=json '.hard_gated_actions // []' "$src" 2>/dev/null || echo '[]'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: rules_loader.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
