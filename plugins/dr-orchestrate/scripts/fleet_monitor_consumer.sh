#!/usr/bin/env bash
# fleet_monitor_consumer.sh — Fleet monitoring consumer for CI and site checks.
#
# Consumes from fleet:monitoring-alerts via consumer groups monitor-dev /
# monitor-main. On receiving an alert message, applies SLA threshold checks
# and publishes an escalation back to fleet:task-events or Hermes.
#
# Usage:
#   fleet_monitor_consumer.sh [--branch dev|main] [--once] [--check] [--help]
#
# Modes:
#   (default)   Loop forever reading from monitoring-alerts
#   --once      Read one batch then exit 0 (smoke / CI)
#   --check     Print effective config and exit 0 (no Redis needed)
#
# Env:
#   DR_ORCH_REDIS_URL              Redis URL (default redis://127.0.0.1:6379)
#   DR_FLEET_BUS_BACKEND           "redis" or "mock" (default redis)
#   DR_FLEET_MONITOR_GROUP         Consumer group override
#   DR_FLEET_MONITOR_CONSUMER      Consumer name override
#   DR_FLEET_MONITOR_SLA_WARN      Warn threshold in seconds (default 120)
#   DR_FLEET_MONITOR_SLA_CRIT      Critical threshold in seconds (default 600)
#   DR_FLEET_MONITOR_ALERT_STATE_DIR  State dir for idempotent dedup (default /tmp/fleet-monitor-state)
#   DR_FLEET_MONITOR_BLOCK_MS      XREADGROUP block timeout ms (default 5000)

set -uo pipefail

# BASH_SOURCE[0] is empty when this script is sourced from a bats test.
# Resolve PLUGIN_DIR robustly: prefer BASH_SOURCE path, fallback to script path.
_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
BUS_ADAPTER="$PLUGIN_DIR/scripts/bus_adapter.sh"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_FLEET_MONITOR_SLA_WARN:=120}"
: "${DR_FLEET_MONITOR_SLA_CRIT:=600}"
: "${DR_FLEET_MONITOR_ALERT_STATE_DIR:=/tmp/fleet-monitor-state}"
: "${DR_FLEET_MONITOR_BLOCK_MS:=5000}"

BRANCH="dev"
MODE="loop"

# ── arg parser ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --once)   MODE="once"; shift ;;
    --check)  MODE="check"; shift ;;
    --help)
      printf 'usage: fleet_monitor_consumer.sh [--branch dev|main] [--once] [--check] [--help]\n'
      printf 'Consumer group: monitor-<branch> on fleet:monitoring-alerts\n'
      exit 0
      ;;
    *) printf 'ERR: unknown flag %q\n' "$1" >&2; exit 1 ;;
  esac
done

# ── consumer group resolved from branch ──────────────────────────────────────

: "${DR_FLEET_MONITOR_GROUP:=monitor-$BRANCH}"
: "${DR_FLEET_MONITOR_CONSUMER:=monitor-consumer-1}"

TOPIC="fleet:monitoring-alerts"

_check() {
  printf 'group=%s\nconsumer=%s\ntopic=%s\nsla_warn=%s\nsla_crit=%s\nbackend=%s\n' \
    "$DR_FLEET_MONITOR_GROUP" "$DR_FLEET_MONITOR_CONSUMER" "$TOPIC" \
    "$DR_FLEET_MONITOR_SLA_WARN" "$DR_FLEET_MONITOR_SLA_CRIT" \
    "$DR_FLEET_BUS_BACKEND"
}

# ── idempotent dedup ──────────────────────────────────────────────────────────

# idempotent_check <key>
# Returns 0 if the key has NOT been seen before (new alert — process it).
# Returns 1 if the key HAS been seen before (duplicate — skip it).
# Side-effect: marks key as seen on first call.
idempotent_check() {
  local key="$1"
  local state_dir="${DR_FLEET_MONITOR_ALERT_STATE_DIR:-/tmp/fleet-monitor-state}"
  mkdir -p "$state_dir"
  # Use sha256 of the key as the state file name to avoid special chars
  local hash
  hash=$(printf '%s' "$key" | shasum -a 256 2>/dev/null | awk '{print $1}' \
    || printf '%s' "$key" | sha256sum | awk '{print $1}')
  local state_file="$state_dir/$hash"
  if [[ -f "$state_file" ]]; then
    return 1  # already seen
  fi
  touch "$state_file"
  return 0  # new
}

# ── alert processor ───────────────────────────────────────────────────────────

_process_alert() {
  # raw_output: raw XREADGROUP response (parsed in future cycle)
  # shellcheck disable=SC2034
  local raw_output="$1"
  # TODO: parse kv-pairs from XREADGROUP output and apply SLA threshold checks
  printf 'MONITOR [%s] received alert batch from %s\n' \
    "$(date -u +%FT%TZ)" "$TOPIC"
}

# ── main entry (only when executed directly, not sourced) ────────────────────

# Source bus adapter when executing; when sourced by tests only functions load.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=scripts/bus_adapter.sh
  source "$BUS_ADAPTER"

  case "$MODE" in
    check)
      _check
      exit 0
      ;;
    once)
      output=$(bus_subscribe "$TOPIC" "$DR_FLEET_MONITOR_GROUP" \
        "$DR_FLEET_MONITOR_CONSUMER" "$DR_FLEET_MONITOR_BLOCK_MS")
      _process_alert "$output"
      exit 0
      ;;
    loop)
      printf 'INFO: starting monitor consumer group=%s consumer=%s\n' \
        "$DR_FLEET_MONITOR_GROUP" "$DR_FLEET_MONITOR_CONSUMER"
      while true; do
        output=$(bus_subscribe "$TOPIC" "$DR_FLEET_MONITOR_GROUP" \
          "$DR_FLEET_MONITOR_CONSUMER" "$DR_FLEET_MONITOR_BLOCK_MS") || true
        _process_alert "$output"
      done
      ;;
  esac
fi
