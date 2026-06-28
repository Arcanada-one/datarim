#!/usr/bin/env bash
# rules_loader.sh — 3-source prompt-pattern rules merge (default → user → learned).
# Read-only loader; Phase C auto-learn write path deferred.
# Output: JSON array of {match, action, confidence} on stdout, deduped by
# match-key with last-write-wins (learned beats user beats default).
#
# The four load_fb_* functions are thin shims that delegate to the core
# loader (dev-tools/fb-policy-loader.sh). The prompt-pattern load() stream
# stays in this file — it is plugin-specific and not part of the core surface.
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_RULES_DEFAULT:=$DR_ORCH_DIR/rules/default.yaml}"
: "${DR_ORCH_RULES_USER:=$HOME/.config/dr-orchestrate/rules/user.yaml}"
: "${DR_ORCH_RULES_LEARNED:=${STATE_DIR:-$HOME/.local/share/dr-orchestrate/state}/learned-rules.yaml}"

# Resolve the core policy loader. Prefer the core path; fall back to a local
# copy (deprecation shim) when the core path is absent (e.g. copy-mode installs
# that have not yet synced the core tree). This one-cycle fallback window is
# documented in documentation/how-to/evolution-log.md.
_CORE_FB_LOADER="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/fb-policy-loader.sh"
_LOCAL_FB_LOADER="$DR_ORCH_DIR/../../dev-tools/fb-policy-loader.sh"
if [[ -x "$_CORE_FB_LOADER" ]]; then
  _FB_LOADER="$_CORE_FB_LOADER"
elif [[ -x "$_LOCAL_FB_LOADER" ]]; then
  _FB_LOADER="$_LOCAL_FB_LOADER"
else
  _FB_LOADER=""
fi

# Resolve the fb-rules.yaml source for accessors that accept an explicit src.
# Prefer the core canonical; fall back to the local plugin copy during the
# deprecation window (one minor cycle).
_CORE_FB_RULES="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml"
_LOCAL_FB_RULES="$DR_ORCH_DIR/rules/fb-rules.yaml"
if [[ -n "${DR_ORCH_FB_RULES:-}" ]]; then
  # Honour explicit caller override (e.g. test fixtures) unchanged.
  :
elif [[ -f "$_CORE_FB_RULES" ]]; then
  DR_ORCH_FB_RULES="$_CORE_FB_RULES"
else
  DR_ORCH_FB_RULES="$_LOCAL_FB_RULES"
fi

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

# load_fb_* shims — delegate to the core loader when available; otherwise
# fall back to inline implementations that read DR_ORCH_FB_RULES directly.
# This preserves backward compatibility for callers that set DR_ORCH_FB_RULES
# to a fixture path, while preferring the core loader in production.

load_fb_policy() {
  local src="${1:-$DR_ORCH_FB_RULES}"
  if [[ -n "$_FB_LOADER" && -z "${1:-}" ]]; then
    DR_AUTONOMY_RULES="$src" bash "$_FB_LOADER" load_fb_policy
  else
    [[ -f "$src" && -s "$src" ]] || { echo '[]'; return 0; }
    yq eval -o=json '.rules // []' "$src" 2>/dev/null || echo '[]'
  fi
}

load_fb_hard_gates() {
  local src="${1:-$DR_ORCH_FB_RULES}"
  if [[ -n "$_FB_LOADER" && -z "${1:-}" ]]; then
    DR_AUTONOMY_RULES="$src" bash "$_FB_LOADER" load_fb_hard_gates
  else
    [[ -f "$src" && -s "$src" ]] || { echo '[]'; return 0; }
    yq eval -o=json '.hard_gated_actions // []' "$src" 2>/dev/null || echo '[]'
  fi
}

load_always_gated_floor() {
  local src="${1:-$DR_ORCH_FB_RULES}"
  if [[ -n "$_FB_LOADER" && -z "${1:-}" ]]; then
    DR_AUTONOMY_RULES="$src" bash "$_FB_LOADER" load_always_gated_floor
  else
    [[ -f "$src" && -s "$src" ]] || return 2
    yq eval -e -o=json '.always_gated_floor | select(type == "!!seq" and length > 0)' \
      "$src" 2>/dev/null || return 2
  fi
}

load_action_autonomy_map() {
  local src="${1:-$DR_ORCH_FB_RULES}"
  if [[ -n "$_FB_LOADER" && -z "${1:-}" ]]; then
    DR_AUTONOMY_RULES="$src" bash "$_FB_LOADER" load_action_autonomy_map
  else
    [[ -f "$src" && -s "$src" ]] || return 2
    yq eval -e -o=json '.action_autonomy_map | select(type == "!!map" and length > 0)' \
      "$src" 2>/dev/null || return 2
  fi
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
