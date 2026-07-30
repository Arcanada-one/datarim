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
#   DR_FLEET_METRICS_DIR    Obs metrics sink dir (default <plugin>/var/metrics)
#   DR_FLEET_COMPLIANCE_DIR Compliance sink dir (default <plugin>/var/compliance)

set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
BUS_ADAPTER="$PLUGIN_DIR/scripts/bus_adapter.sh"
AUDIT_SINK="$PLUGIN_DIR/scripts/audit_sink.sh"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_FLEET_AUDIT_GROUP:=obs}"
: "${DR_FLEET_AUDIT_CONSUMER:=audit-consumer-1}"
: "${DR_FLEET_BLOCK_MS:=5000}"
: "${DR_FLEET_METRICS_DIR:=$PLUGIN_DIR/var/metrics}"
: "${DR_FLEET_COMPLIANCE_DIR:=$PLUGIN_DIR/var/compliance}"

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
  # Parse one audit-log entry and forward it as a typed schema-v2 event to the
  # obs metrics sink and the compliance sink, then acknowledge it via XACK.
  #
  # `raw` is the flattened XREADGROUP output from bus_subscribe: redis-cli in
  # non-tty mode emits one token per line — the stream key, the stream entry id
  # (\d+-\d+), then alternating field / value lines (id, ts, type, task_id,
  # reason, …). Reason material is redacted before persistence (PRD § Security).
  local raw="$1"

  # Empty read (no pending entry) or mock placeholder — nothing to forward.
  if [[ -z "$raw" || "$raw" == "(empty)" ]]; then
    return 0
  fi

  # Field-by-field kv extraction via a small state machine (no arithmetic, so
  # it stays correct under `set -e` inherited from audit_sink.sh).
  local entry_id="" f_id="" f_ts="" f_type="" f_task_id="" f_reason=""
  local state="seek" key=""
  local line
  while IFS= read -r line; do
    case "$state" in
      seek)
        # First \d+-\d+ line is the Redis stream entry id (used for XACK).
        if [[ "$line" =~ ^[0-9]+-[0-9]+$ ]]; then
          entry_id="$line"; state="key"
        fi
        ;;
      key)
        # A second entry-id line marks the next entry — process one at a time.
        if [[ "$line" =~ ^[0-9]+-[0-9]+$ ]]; then
          break
        fi
        key="$line"; state="val"
        ;;
      val)
        case "$key" in
          id)      f_id="$line" ;;
          ts)      f_ts="$line" ;;
          type)    f_type="$line" ;;
          task_id) f_task_id="$line" ;;
          reason)  f_reason="$line" ;;
        esac
        state="key"
        ;;
    esac
  done <<< "$raw"

  # No stream entry id parsed — malformed or empty batch, skip.
  if [[ -z "$entry_id" ]]; then
    return 0
  fi

  # Build the canonical schema-v2 envelope (make_event_v2 redacts `reason`),
  # then enrich with the source provenance so the parsed id/ts/task_id survive.
  local event
  event="$(make_event_v2 "" "audit-forward" 0 0 "$f_task_id" 0 "" \
             "$DR_FLEET_AUDIT_GROUP" "" "$f_type" "forwarded" "$f_reason")"
  event="$(printf '%s' "$event" | jq -c \
    --arg sid "$f_id" --arg sts "$f_ts" --arg tid "$f_task_id" \
    '. + {source_id: $sid, source_ts: $sts, task_id: $tid}')"

  local day; day="$(date -u +%Y-%m-%d)"
  emit "$DR_FLEET_METRICS_DIR/audit-consumer-$day.jsonl" "$event"
  emit "$DR_FLEET_COMPLIANCE_DIR/audit-compliance-$day.jsonl" "$event"

  # Compliance ACK — remove the message from the pending entries list.
  bus_ack "$TOPIC" "$DR_FLEET_AUDIT_GROUP" "$entry_id" >/dev/null 2>&1 || true

  printf 'AUDIT [%s] group=%s entry=%s forwarded to obs+compliance sinks\n' \
    "$(date -u +%FT%TZ)" "$DR_FLEET_AUDIT_GROUP" "$entry_id"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=scripts/bus_adapter.sh
  source "$BUS_ADAPTER"
  # shellcheck source=scripts/audit_sink.sh
  source "$AUDIT_SINK"

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
