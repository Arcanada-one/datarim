#!/usr/bin/env bash
# fleet_audit_consumer.sh — Consumer for fleet:audit-log stream.
#
# Subscribes to fleet:audit-log via consumer groups "obs" and "compliance".
# Forwards entries to the obs aggregator and compliance sink.
#
# Usage:
#   fleet_audit_consumer.sh [--group obs|compliance] [--once] [--check] [--help]
#
# Env:
#   DR_ORCH_REDIS_URL       Redis URL (default redis://127.0.0.1:6379)
#   DR_FLEET_BUS_BACKEND    "redis" or "mock" (default redis)
#   DR_FLEET_AUDIT_GROUP    Consumer group (default obs)
#   DR_FLEET_AUDIT_CONSUMER Consumer name (default audit-consumer-1)
#   DR_FLEET_BLOCK_MS       XREADGROUP block timeout ms (default 5000)

set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
BUS_ADAPTER="$PLUGIN_DIR/scripts/bus_adapter.sh"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_FLEET_AUDIT_GROUP:=obs}"
: "${DR_FLEET_AUDIT_CONSUMER:=audit-consumer-1}"
: "${DR_FLEET_BLOCK_MS:=5000}"

MODE="loop"

# ── arg parser ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --group)   DR_FLEET_AUDIT_GROUP="$2"; shift 2 ;;
    --once)    MODE="once"; shift ;;
    --check)   MODE="check"; shift ;;
    --help)
      printf 'usage: fleet_audit_consumer.sh [--group obs|compliance] [--once] [--check] [--help]\n'
      exit 0
      ;;
    *) printf 'ERR: unknown flag %q\n' "$1" >&2; exit 1 ;;
  esac
done

TOPIC="fleet:audit-log"

_check() {
  printf 'group=%s\nconsumer=%s\ntopic=%s\nbackend=%s\n' \
    "$DR_FLEET_AUDIT_GROUP" "$DR_FLEET_AUDIT_CONSUMER" "$TOPIC" "$DR_FLEET_BUS_BACKEND"
}

_process_entry() {
  # raw: XREADGROUP response; full kv parsing is a future cycle enhancement
  # shellcheck disable=SC2034
  local raw="$1"
  # TODO: forward to obs aggregator metrics and compliance sink
  printf 'AUDIT [%s] group=%s received entry\n' \
    "$(date -u +%FT%TZ)" "$DR_FLEET_AUDIT_GROUP"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=scripts/bus_adapter.sh
  source "$BUS_ADAPTER"

  case "$MODE" in
    check) _check; exit 0 ;;
    once)
      out=$(bus_subscribe "$TOPIC" "$DR_FLEET_AUDIT_GROUP" \
        "$DR_FLEET_AUDIT_CONSUMER" "$DR_FLEET_BLOCK_MS") || true
      _process_entry "$out"
      exit 0
      ;;
    loop)
      printf 'INFO: audit consumer group=%s starting\n' "$DR_FLEET_AUDIT_GROUP"
      while true; do
        out=$(bus_subscribe "$TOPIC" "$DR_FLEET_AUDIT_GROUP" \
          "$DR_FLEET_AUDIT_CONSUMER" "$DR_FLEET_BLOCK_MS") || true
        _process_entry "$out"
      done
      ;;
  esac
fi
