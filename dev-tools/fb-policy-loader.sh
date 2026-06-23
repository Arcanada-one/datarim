#!/usr/bin/env bash
# fb-policy-loader.sh — Core loader for the FB-policy data block.
# Exposes four read-only accessors that mirror the contracts originally defined
# in plugins/dr-orchestrate/scripts/rules_loader.sh. Extracted here so the
# core resolver (dev-tools/lib/space-autonomy.sh) can read the hard-gated
# floor and the action-autonomy map without requiring the dr-orchestrate plugin.
#
# Transport-NEUTRAL: this file MUST NOT contain transport-specific terms
# (runner, broker, or outbound-channel terms). Those belong exclusively in
# the plugin. Checked by: scripts/stack-agnostic-gate.sh + manual grep.
#
# Default source: ${DR_AUTONOMY_RULES:-${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml}
# Override: set DR_AUTONOMY_RULES to any absolute path before sourcing.
#
# Usage (sourced or CLI):
#   source dev-tools/fb-policy-loader.sh
#   load_always_gated_floor              # exits 2 if floor is missing/empty
#   load_action_autonomy_map             # exits 2 if map is missing/empty
#   load_fb_policy                       # exits 0, emits [] on missing file
#   load_fb_hard_gates                   # exits 0, emits [] on missing file
#
#   bash dev-tools/fb-policy-loader.sh load_always_gated_floor
#   bash dev-tools/fb-policy-loader.sh load_fb_policy /custom/path/fb-rules.yaml

set -euo pipefail

: "${DATARIM_RUNTIME:=$HOME/.claude}"
: "${DR_AUTONOMY_RULES:=$DATARIM_RUNTIME/dev-tools/rules/fb-rules.yaml}"

# _fb_src — resolve the source path for accessors; $1 overrides DR_AUTONOMY_RULES.
_fb_src() {
  local src="${1:-$DR_AUTONOMY_RULES}"
  printf '%s\n' "$src"
}

# load_fb_policy — emit FB-1..FB-8 policy as a JSON array.
# Returns [] when the file is missing (fail-open — callers fall back to
# default escalation policy). Schema: rules/fb-rules.yaml header.
load_fb_policy() {
  local src
  src="$(_fb_src "${1:-}")"
  [[ -f "$src" && -s "$src" ]] || { printf '%s\n' '[]'; return 0; }
  yq eval -o=json '.rules // []' "$src" 2>/dev/null || printf '%s\n' '[]'
}

# load_fb_hard_gates — emit hard-gated action kinds as a JSON array of strings.
# Returns [] when the file is missing (fail-open — callers treat an empty list
# as "no extra hard gates beyond the always_gated_floor").
load_fb_hard_gates() {
  local src
  src="$(_fb_src "${1:-}")"
  [[ -f "$src" && -s "$src" ]] || { printf '%s\n' '[]'; return 0; }
  yq eval -o=json '.hard_gated_actions // []' "$src" 2>/dev/null || printf '%s\n' '[]'
}

# load_always_gated_floor — emit the immutable Supreme-Directive floor as JSON.
# FAIL-CLOSED: returns exit 2 when the floor is absent or empty. Callers MUST
# treat exit 2 as a hard block; they MUST NOT auto-execute any gated action when
# the floor cannot be read.
load_always_gated_floor() {
  local src
  src="$(_fb_src "${1:-}")"
  [[ -f "$src" && -s "$src" ]] || return 2
  yq eval -e -o=json \
    '.always_gated_floor | select(type == "!!seq" and length > 0)' \
    "$src" 2>/dev/null || return 2
}

# load_action_autonomy_map — emit the action-kind → space-policy-key map as JSON.
# FAIL-CLOSED: returns exit 2 when the map is absent or empty. Callers MUST
# treat exit 2 as invalid_rules (route everything to operator escalation).
load_action_autonomy_map() {
  local src
  src="$(_fb_src "${1:-}")"
  [[ -f "$src" && -s "$src" ]] || return 2
  yq eval -e -o=json \
    '.action_autonomy_map | select(type == "!!map" and length > 0)' \
    "$src" 2>/dev/null || return 2
}

# Self-exec dispatch — allows CLI invocation:
#   bash dev-tools/fb-policy-loader.sh <fn> [args]
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"
  shift || true
  [[ -n "$fn" ]] || {
    printf 'usage: fb-policy-loader.sh <fn> [src]\n' >&2
    printf 'functions: load_fb_policy load_fb_hard_gates load_always_gated_floor load_action_autonomy_map\n' >&2
    exit 2
  }
  "$fn" "$@"
fi
