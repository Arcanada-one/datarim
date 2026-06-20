#!/usr/bin/env bash
# Resolve a normally gated action against the active space policy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/space-autonomy.sh
source "$SCRIPT_DIR/lib/space-autonomy.sh"

usage() {
  echo "usage: resolve-space-autonomy.sh gate --action <kind> [--payload <json>]" >&2
  exit 2
}

gate() {
  local action="" payload='{}' output rc event space_hint
  while (( $# > 0 )); do
    case "$1" in
      --action) action="${2:-}"; shift 2 ;;
      --payload) payload="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ "$action" =~ ^[a-z][a-z0-9_]*$ ]] || usage
  set +e
  output="$(autonomy_decision "$action" "$payload")"
  rc=$?
  set -e
  space_hint="${DATARIM_ACTIVE_SPACE:-${DATARIM_SPACE_NAME:-}}"
  if [[ -z "$space_hint" ]]; then
    space_hint="$(_autonomy_marker_name 2>/dev/null || true)"
  fi
  [[ "$space_hint" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || space_hint=""
  event="$(jq -c \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg actor "${DR_AUTONOMY_ACTOR:-${USER:-agent}}" \
    --arg task_id "${DATARIM_TASK_ID:-}" \
    --arg space "$space_hint" \
    '. + {timestamp:$ts,actor:$actor,task_id:$task_id}
      | if (.space // "") == "" then .space = $space else . end' <<<"$output")"
  local audit="${DR_AUTONOMY_AUDIT:-${DR_ORCH_AUTONOMY_AUDIT:-$HOME/.local/share/datarim/autonomy.jsonl}}"
  mkdir -p "$(dirname "$audit")"
  printf '%s\n' "$event" >> "$audit"
  printf '%s\n' "$event"
  return "$rc"
}

command_name="${1:-}"
shift || true
case "$command_name" in
  gate) gate "$@" ;;
  *) usage ;;
esac
