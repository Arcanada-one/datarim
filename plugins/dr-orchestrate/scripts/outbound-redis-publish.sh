#!/usr/bin/env bash
# outbound-redis-publish.sh — Redis PUBLISH backend for outbound events.
#
# Public functions:
#   channel_name <session_id>                       → prints channel string
#   publish_event <session_id> <json_payload>       → PUBLISH and exit
#
# Channel: orchestrator-out:<session_id>
# Requires redis-cli in PATH and DR_ORCH_OUTBOUND_REDIS_URL env var.
set -euo pipefail

: "${DR_ORCH_OUTBOUND_REDIS_URL:=redis://127.0.0.1:6379}"

channel_name() {
  local session_id="$1"
  printf 'orchestrator-out:%s' "$session_id"
}

# publish_event <session_id> <payload>
# Requires redis-cli. Exits non-zero if redis-cli missing or connection fails.
publish_event() {
  local session_id="$1"; local payload="$2"
  if ! command -v redis-cli >/dev/null 2>&1; then
    printf 'ERR: redis-cli not found in PATH\n' >&2
    return 1
  fi
  local channel
  channel="$(channel_name "$session_id")"
  redis-cli -u "$DR_ORCH_OUTBOUND_REDIS_URL" PUBLISH "$channel" "$payload" >/dev/null
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { printf 'usage: outbound-redis-publish.sh <fn> [args]\n' >&2; exit 2; }
  "$fn" "$@"
fi
