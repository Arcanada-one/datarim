#!/usr/bin/env bash
# rules_loader.sh — 3-source prompt-pattern rules merge (default → user → learned).
# Output: JSON array of rules on stdout, deduped by
# match-key with last-write-wins (learned beats user beats default).
#
# The four load_fb_* functions are thin shims that delegate to the core
# loader (dev-tools/fb-policy-loader.sh). The prompt-pattern load() stream
# stays in this file — it is plugin-specific and not part of the core surface.
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_RULES_DEFAULT:=$DR_ORCH_DIR/rules/default.yaml}"
: "${DR_ORCH_RULES_USER:=$HOME/.config/dr-orchestrate/rules/user.yaml}"
: "${DR_ORCH_STATE_DIR:=${STATE_DIR:-$HOME/.local/share/dr-orchestrate/state}}"
: "${DR_ORCH_RULES_LEARNED:=$DR_ORCH_STATE_DIR/learned-rules.yaml}"

# Resolve the core policy loader (dev-tools/fb-policy-loader.sh). CORE-ONLY:
# the one-cycle deprecation fallback to a plugin-local fb-rules copy was
# removed after consumers resynced to the core path (see
# documentation/how-to/evolution-log.md). Resolution order: runtime install
# ($DATARIM_RUNTIME) first, then the repo-relative core path (the plugin
# lives inside the framework repo). Both point at the same canonical file.
_RUNTIME_FB_LOADER="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/fb-policy-loader.sh"
_REPO_FB_LOADER="$DR_ORCH_DIR/../../dev-tools/fb-policy-loader.sh"
if [[ -f "$_RUNTIME_FB_LOADER" ]]; then
  _FB_LOADER="$_RUNTIME_FB_LOADER"
elif [[ -f "$_REPO_FB_LOADER" ]]; then
  _FB_LOADER="$_REPO_FB_LOADER"
else
  _FB_LOADER=""
fi

# Resolve the fb-rules.yaml source for accessors. Core canonical only —
# prefer the runtime install, else the repo-relative core path. An explicit
# DR_ORCH_FB_RULES (e.g. a test fixture) is honoured unchanged.
_RUNTIME_FB_RULES="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml"
_REPO_FB_RULES="$DR_ORCH_DIR/../../dev-tools/rules/fb-rules.yaml"
if [[ -n "${DR_ORCH_FB_RULES:-}" ]]; then
  # Honour explicit caller override (e.g. test fixtures) unchanged.
  :
elif [[ -f "$_RUNTIME_FB_RULES" ]]; then
  DR_ORCH_FB_RULES="$_RUNTIME_FB_RULES"
else
  DR_ORCH_FB_RULES="$_REPO_FB_RULES"
fi

_extract() {
  local src="$1" provenance="$2"
  [[ -f "$src" && -s "$src" ]] || { echo '[]'; return 0; }
  yq eval -o=json '.patterns // []' "$src" 2>/dev/null \
    | jq -c --arg provenance "$provenance" 'map(. + {provenance:$provenance})' \
    || echo '[]'
}

_extract_learned() {
  [[ -f "$DR_ORCH_RULES_LEARNED" && -s "$DR_ORCH_RULES_LEARNED" ]] \
    || { echo '[]'; return 0; }
  local now="${DR_ORCH_NOW_EPOCH:-$(date +%s)}"
  [[ "$now" =~ ^[0-9]+$ ]] || { echo '[]'; return 0; }
  yq eval -o=json '.patterns // []' "$DR_ORCH_RULES_LEARNED" 2>/dev/null \
    | jq -c --argjson now "$now" '
        def epoch: type=="number" and floor==. and .>=0 and .<=253402300799;
        map(select(
          (.match|type)=="string" and (.match|utf8bytelength)>=1 and (.match|utf8bytelength)<=256 and
          (.match|startswith("-")|not) and (.match|test("[[:cntrl:]]")|not) and
          (.match|contains("\t")|not) and (.match|startswith(" ")|not) and (.match|endswith(" ")|not) and
          (.match|contains("  ")|not) and (.match|contains("..")|not) and
          (.match|test("[/\\\\;&|<>$`(){}*?!]|\\[|\\]")|not) and
          (.action|type)=="string" and (.action|length)>0 and
          (.confidence|type)=="number" and .confidence>=0 and .confidence<=1 and
          (.created_at|epoch) and (.last_validated_at|epoch) and (.expires_at|epoch) and
          .last_validated_at>=.created_at and .last_validated_at<=.expires_at and
          .expires_at==(.created_at + 604800) and
          (.proposal_hash|type)=="string" and (.proposal_hash|test("^[0-9a-f]{64}$")) and
          (.generation|type)=="string" and (.generation|test("^[0-9a-f]{64}$")) and
          $now < .expires_at and $now < (.last_validated_at + 86400)
        )) | map(. + {provenance:"learned"})' \
    || echo '[]'
}

load() {
  local d u l
  d="$(_extract "$DR_ORCH_RULES_DEFAULT" bundled)"
  u="$(_extract "$DR_ORCH_RULES_USER" user)"
  l="$(_extract_learned)"
  jq -c -s '
    .[0] + .[1] + .[2]
    | reduce .[] as $x ({}; .[$x.match] = $x)
    | [.[]]
  ' <(echo "$d") <(echo "$u") <(echo "$l")
}

# Trusted actions deliberately exclude learned rules. This is the capability
# registry used before every learned dispatch and proposal acceptance.
load_trusted_actions() {
  jq -c -s '[.[0][], .[1][]] | map(.action) | unique' \
    <(_extract "$DR_ORCH_RULES_DEFAULT" bundled) \
    <(_extract "$DR_ORCH_RULES_USER" user)
}

load_inactive_learned() {
  [[ -f "$DR_ORCH_RULES_LEARNED" && -s "$DR_ORCH_RULES_LEARNED" ]] \
    || { echo '[]'; return 0; }
  local now="${DR_ORCH_NOW_EPOCH:-$(date +%s)}"
  yq eval -o=json '.patterns // []' "$DR_ORCH_RULES_LEARNED" 2>/dev/null \
    | jq -c --argjson now "$now" 'map(select(
        (.last_validated_at|type)=="number" and (.expires_at|type)=="number" and
        ($now >= .expires_at or $now >= (.last_validated_at + 86400))))' \
    || echo '[]'
}

# load_fb_* shims — delegate-only to the core loader (prefer-core). The
# inline yq fallback implementations were removed with the deprecation copy;
# a missing core loader is a broken install and fails CLOSED (exit 2) rather
# than silently degrading. Callers that set DR_ORCH_FB_RULES (or pass an
# explicit src argument) still control the source file — the core loader
# reads it via DR_AUTONOMY_RULES.

_require_fb_loader() {
  if [[ -z "$_FB_LOADER" ]]; then
    echo "ERROR: core fb-policy loader not found (looked at" \
         "$_RUNTIME_FB_LOADER and $_REPO_FB_LOADER) — broken install" >&2
    return 2
  fi
}

load_fb_policy() {
  _require_fb_loader || return 2
  DR_AUTONOMY_RULES="${1:-$DR_ORCH_FB_RULES}" bash "$_FB_LOADER" load_fb_policy
}

load_fb_hard_gates() {
  _require_fb_loader || return 2
  DR_AUTONOMY_RULES="${1:-$DR_ORCH_FB_RULES}" bash "$_FB_LOADER" load_fb_hard_gates
}

load_always_gated_floor() {
  _require_fb_loader || return 2
  DR_AUTONOMY_RULES="${1:-$DR_ORCH_FB_RULES}" bash "$_FB_LOADER" load_always_gated_floor
}

load_action_autonomy_map() {
  _require_fb_loader || return 2
  DR_AUTONOMY_RULES="${1:-$DR_ORCH_FB_RULES}" bash "$_FB_LOADER" load_action_autonomy_map
}

resolve_space_autonomy() {
  local resolver="$DR_ORCH_DIR/../../dev-tools/resolve-space-autonomy.sh"
  [[ -x "$resolver" ]] || return 2
  "$resolver" gate "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: rules_loader.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
