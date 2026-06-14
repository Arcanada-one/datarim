#!/usr/bin/env bash
# bus_adapter.sh — Fleet event bus port: publish/subscribe/ack/replay over
# Redis Streams (or mock backend for testing).
#
# Public functions:
#   bus_publish  <topic> <field> <val> [<field> <val> ...]  → stream-id
#   bus_subscribe <topic> <group> <consumer> <block_ms>     → raw XREADGROUP output
#   bus_ack       <topic> <group> <message_id>              → 0|1
#   bus_replay    <topic> <from_id>                         → XRANGE output
#
# Topic constants (use these — do not hardcode strings):
#   FLEET_TOPIC_TASK_EVENTS        fleet:task-events
#   FLEET_TOPIC_MONITORING_ALERTS  fleet:monitoring-alerts
#   FLEET_TOPIC_FLEET_COMMANDS     fleet:fleet-commands
#   FLEET_TOPIC_AUDIT_LOG          fleet:audit-log
#
# Env:
#   DR_FLEET_BUS_BACKEND  — "redis" (default) or "mock"
#   DR_ORCH_REDIS_URL     — Redis URL, default redis://127.0.0.1:6379
#   DR_FLEET_MOCK_LOG     — path for mock backend log (default /tmp/fleet-mock.log)
#   DR_FLEET_MOCK_XADD_ID — mock XADD return ID (default timestamp-0)
set -uo pipefail

# ── topic constants ───────────────────────────────────────────────────────────
# Exported for sourcing scripts — shellcheck cannot see cross-file usage.
# shellcheck disable=SC2034
readonly FLEET_TOPIC_TASK_EVENTS="fleet:task-events"
# shellcheck disable=SC2034
readonly FLEET_TOPIC_MONITORING_ALERTS="fleet:monitoring-alerts"
# shellcheck disable=SC2034
readonly FLEET_TOPIC_FLEET_COMMANDS="fleet:fleet-commands"
# shellcheck disable=SC2034
readonly FLEET_TOPIC_AUDIT_LOG="fleet:audit-log"

# Stream key prefix — Redis key = "stream:<topic>"
_stream_key() { printf 'stream:%s' "$1"; }

# ── env defaults ──────────────────────────────────────────────────────────────

: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_MOCK_LOG:=/tmp/fleet-mock.log}"
: "${DR_FLEET_MOCK_XADD_ID:=$(date +%s%3N)-0}"

# ── Redis helpers ─────────────────────────────────────────────────────────────

_redis_require() {
  if ! command -v redis-cli >/dev/null 2>&1; then
    printf 'ERR: redis-cli not found in PATH\n' >&2
    return 1
  fi
}

_redis() {
  redis-cli -u "$DR_ORCH_REDIS_URL" "$@"
}

# ── mock backend ──────────────────────────────────────────────────────────────

_mock_log() {
  mkdir -p "$(dirname "$DR_FLEET_MOCK_LOG")"
  printf '%s\n' "$*" >> "$DR_FLEET_MOCK_LOG"
}

_mock_publish() {
  local topic="$1"; shift
  local key; key="$(_stream_key "$topic")"
  _mock_log "XADD $key * $*"
  printf '%s\n' "$DR_FLEET_MOCK_XADD_ID"
}

_mock_subscribe() {
  local topic="$1" group="$2" consumer="$3" block_ms="$4"
  local key; key="$(_stream_key "$topic")"
  _mock_log "XREADGROUP GROUP $group $consumer BLOCK $block_ms STREAMS $key >"
  printf '(empty)\n'
}

_mock_ack() {
  local topic="$1" group="$2" msg_id="$3"
  local key; key="$(_stream_key "$topic")"
  _mock_log "XACK $key $group $msg_id"
  printf '1\n'
}

_mock_replay() {
  local topic="$1" from_id="$2"
  local key; key="$(_stream_key "$topic")"
  _mock_log "XRANGE $key $from_id +"
  printf '(empty)\n'
}

# ── backend guard ─────────────────────────────────────────────────────────────

_validate_backend() {
  case "$DR_FLEET_BUS_BACKEND" in
    redis|mock) ;;
    *)
      printf 'ERR: unknown DR_FLEET_BUS_BACKEND=%q (valid: redis, mock)\n' \
        "$DR_FLEET_BUS_BACKEND" >&2
      return 1
      ;;
  esac
}

# Validate on source — abort if backend is unknown
_validate_backend

# ── public functions ──────────────────────────────────────────────────────────

# bus_publish <topic> <field> <val> [<field> <val> ...]
# Publishes message fields to the given topic stream. Returns the stream entry ID.
bus_publish() {
  local topic="$1"; shift
  case "$DR_FLEET_BUS_BACKEND" in
    mock)  _mock_publish "$topic" "$@" ;;
    redis)
      _redis_require || return 1
      local key; key="$(_stream_key "$topic")"
      _redis XADD "$key" '*' "$@"
      ;;
    *)
      printf 'ERR: unknown DR_FLEET_BUS_BACKEND=%q (valid: redis, mock)\n' \
        "$DR_FLEET_BUS_BACKEND" >&2
      return 1
      ;;
  esac
}

# bus_subscribe <topic> <group> <consumer> <block_ms>
# Reads pending messages for the consumer group. Creates the group if absent.
# Returns raw XREADGROUP output (or mock placeholder).
bus_subscribe() {
  local topic="$1" group="$2" consumer="$3"
  local block_ms="${4:-0}"
  case "$DR_FLEET_BUS_BACKEND" in
    mock)  _mock_subscribe "$topic" "$group" "$consumer" "$block_ms" ;;
    redis)
      _redis_require || return 1
      local key; key="$(_stream_key "$topic")"
      # Create consumer group if it does not exist (MKSTREAM = create stream too)
      _redis XGROUP CREATE "$key" "$group" '$' MKSTREAM 2>/dev/null || true
      _redis XREADGROUP GROUP "$group" "$consumer" \
        BLOCK "$block_ms" STREAMS "$key" '>'
      ;;
  esac
}

# bus_ack <topic> <group> <message_id>
# Acknowledges a message so it is removed from the pending entries list.
bus_ack() {
  local topic="$1" group="$2" msg_id="$3"
  case "$DR_FLEET_BUS_BACKEND" in
    mock)  _mock_ack "$topic" "$group" "$msg_id" ;;
    redis)
      _redis_require || return 1
      local key; key="$(_stream_key "$topic")"
      _redis XACK "$key" "$group" "$msg_id"
      ;;
  esac
}

# bus_replay <topic> <from_id>
# Replays messages from from_id to the end of the stream (XRANGE).
# Use '-' as from_id to replay all messages.
bus_replay() {
  local topic="$1" from_id="${2:--}"
  case "$DR_FLEET_BUS_BACKEND" in
    mock)  _mock_replay "$topic" "$from_id" ;;
    redis)
      _redis_require || return 1
      local key; key="$(_stream_key "$topic")"
      _redis XRANGE "$key" "$from_id" '+'
      ;;
  esac
}

# ── CLI dispatch ──────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { printf 'usage: bus_adapter.sh <fn> [args]\n' >&2; exit 2; }
  "$fn" "$@"
fi
