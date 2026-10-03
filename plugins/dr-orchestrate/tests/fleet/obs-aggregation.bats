#!/usr/bin/env bats
# obs-aggregation.bats — V-AC-6: observability aggregator + dashboard reachable.
# V-AC-7: dashboard binds tailnet IP (not 0.0.0.0).

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
OBS="$PLUGIN_ROOT/scripts/fleet_obs_aggregator.sh"
DASHBOARD="$PLUGIN_ROOT/scripts/fleet_dashboard_server.sh"

REDIS_URL="${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}"

setup() {
  TMP="$(mktemp -d)"
  export DR_FLEET_METRICS_DIR="$TMP/metrics"
  export DR_FLEET_COMPLIANCE_DIR="$TMP/compliance"
  export DR_ORCH_REDIS_URL="$REDIS_URL"
  export DR_FLEET_BUS_BACKEND=mock
  export DR_FLEET_MOCK_LOG="$TMP/mock.log"
  export DR_FLEET_MOCK_XADD_ID="1700000000000-0"
  export BUS_ADAPTER_SH="$PLUGIN_ROOT/scripts/bus_adapter.sh"
  export AUDIT_SINK_SH="$PLUGIN_ROOT/scripts/audit_sink.sh"
  export AUDIT_CONSUMER_SH="$PLUGIN_ROOT/scripts/fleet_audit_consumer.sh"
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
}

# Call _process_entry in an isolated shell with the bus + sink deps sourced.
# Passes the raw flattened XREADGROUP blob as $1 to the sourced function.
# `set --` clears positional args before sourcing the consumer so its top-level
# arg parser (a no-op path when sourced) does not see the harness arguments.
_run_process_entry() {
  run bash -c '
    RAW="$1"
    source "$BUS_ADAPTER_SH"
    source "$AUDIT_SINK_SH"
    set --
    source "$AUDIT_CONSUMER_SH"
    _process_entry "$RAW"
  ' _ "$1"
}

# A canonical flattened XREADGROUP blob (redis-cli non-tty form): stream key,
# entry id, then alternating field / value lines — mirrors fleet event shape.
_sample_audit_blob() {
  printf '%s\n' \
    "stream:fleet:audit-log" \
    "1700000000000-5" \
    "id"      "status-evt-42" \
    "ts"      "2026-07-21T10:00:00Z" \
    "type"    "lifecycle" \
    "task_id" "TUNE-0385" \
    "reason"  "${1:-plain reason text}"
}

teardown() {
  rm -rf "$TMP"
}

# ── obs aggregator executable + help ─────────────────────────────────────────

@test "V-AC-6: fleet_obs_aggregator.sh is executable" {
  [ -x "$OBS" ]
}

@test "V-AC-6: fleet_obs_aggregator.sh --help exits 0" {
  run bash "$OBS" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "V-AC-6: --check mode prints metrics dir and exits 0" {
  run bash "$OBS" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"metrics_dir"* ]]
}

# ── snapshot file creation ────────────────────────────────────────────────────

@test "V-AC-6: --snapshot creates fleet-graph.json" {
  run bash "$OBS" --snapshot
  [ "$status" -eq 0 ]
  [ -f "$DR_FLEET_METRICS_DIR/fleet-graph.json" ]
}

@test "V-AC-6: fleet-graph.json contains nodes and edges keys" {
  bash "$OBS" --snapshot
  local snap="$DR_FLEET_METRICS_DIR/fleet-graph.json"
  grep -q '"nodes"' "$snap"
  grep -q '"edges"' "$snap"
}

@test "V-AC-6: fleet-graph.json contains metrics key" {
  bash "$OBS" --snapshot
  local snap="$DR_FLEET_METRICS_DIR/fleet-graph.json"
  grep -q '"metrics"' "$snap"
}

# ── dashboard server ──────────────────────────────────────────────────────────

@test "V-AC-7: fleet_dashboard_server.sh is executable" {
  [ -x "$DASHBOARD" ]
}

@test "V-AC-7: fleet_dashboard_server.sh --help exits 0" {
  run bash "$DASHBOARD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "V-AC-7: --check mode prints bind address and exits 0" {
  run bash "$DASHBOARD" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"bind"* ]]
}

# ── network-exposure: dashboard MUST NOT bind 0.0.0.0 ────────────────────────

@test "V-AC-7: dashboard refuses 0.0.0.0 bind without explicit allow" {
  run bash "$DASHBOARD" --check \
    --bind 0.0.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERR"* ]] || [[ "$output" == *"FATAL"* ]]
}

@test "V-AC-7: dashboard accepts tailnet IP bind" {
  run bash "$DASHBOARD" --check \
    --bind 100.64.0.1
  [ "$status" -eq 0 ]
}

@test "V-AC-7: dashboard accepts loopback bind" {
  run bash "$DASHBOARD" --check \
    --bind 127.0.0.1
  [ "$status" -eq 0 ]
}

# ── obs consumer ─────────────────────────────────────────────────────────────

@test "V-AC-6: index.html contains force-graph token (V-AC-6 success criterion)" {
  local html="$PLUGIN_ROOT/web/fleet-dashboard/index.html"
  [ -f "$html" ]
  grep -q 'force-graph' "$html"
}

@test "V-AC-6: fleet_audit_consumer.sh is executable" {
  [ -x "$PLUGIN_ROOT/scripts/fleet_audit_consumer.sh" ]
}

@test "V-AC-6: fleet_audit_consumer.sh --check exits 0" {
  run bash "$PLUGIN_ROOT/scripts/fleet_audit_consumer.sh" --check
  [ "$status" -eq 0 ]
}

# ── audit consumer: typed kv forward to obs + compliance sinks ────────────────

@test "audit-consumer: parses kv fields into a schema-v2 obs event" {
  local blob; blob="$(_sample_audit_blob)"
  _run_process_entry "$blob"
  [ "$status" -eq 0 ]
  local day; day="$(date -u +%Y-%m-%d)"
  local obs="$DR_FLEET_METRICS_DIR/audit-consumer-$day.jsonl"
  [ -f "$obs" ]
  run jq -e '.schema_version == 2
             and .task_id == "TUNE-0385"
             and .source_id == "status-evt-42"
             and .source_ts == "2026-07-21T10:00:00Z"
             and .stage == "lifecycle"' "$obs"
  [ "$status" -eq 0 ]
}

@test "audit-consumer: forwards the same event to the compliance sink" {
  local blob; blob="$(_sample_audit_blob)"
  _run_process_entry "$blob"
  [ "$status" -eq 0 ]
  local day; day="$(date -u +%Y-%m-%d)"
  local comp="$DR_FLEET_COMPLIANCE_DIR/audit-compliance-$day.jsonl"
  [ -f "$comp" ]
  run jq -e '.schema_version == 2 and .task_id == "TUNE-0385"' "$comp"
  [ "$status" -eq 0 ]
}

@test "audit-consumer: acknowledges the stream entry via XACK" {
  local blob; blob="$(_sample_audit_blob)"
  _run_process_entry "$blob"
  [ "$status" -eq 0 ]
  run grep -F 'XACK stream:fleet:audit-log obs 1700000000000-5' "$DR_FLEET_MOCK_LOG"
  [ "$status" -eq 0 ]
}

@test "audit-consumer: redacts credential material in the reason field" {
  local blob; blob="$(_sample_audit_blob 'blocked because token=hunter2')"
  _run_process_entry "$blob"
  [ "$status" -eq 0 ]
  local day; day="$(date -u +%Y-%m-%d)"
  local obs="$DR_FLEET_METRICS_DIR/audit-consumer-$day.jsonl"
  run grep -F 'hunter2' "$obs"
  [ "$status" -ne 0 ]
  run grep -F '<REDACTED>' "$obs"
  [ "$status" -eq 0 ]
}

@test "audit-consumer: empty subscribe result is a no-op (no sink, no ACK)" {
  _run_process_entry ""
  [ "$status" -eq 0 ]
  _run_process_entry "(empty)"
  [ "$status" -eq 0 ]
  local day; day="$(date -u +%Y-%m-%d)"
  [ ! -f "$DR_FLEET_METRICS_DIR/audit-consumer-$day.jsonl" ]
  [ ! -f "$DR_FLEET_COMPLIANCE_DIR/audit-compliance-$day.jsonl" ]
  run grep -F 'XACK' "$DR_FLEET_MOCK_LOG"
  [ "$status" -ne 0 ]
}

@test "audit-consumer: source drops the deferred 'pending full sink wiring' marker" {
  run grep -F 'pending full sink wiring' "$AUDIT_CONSUMER_SH"
  [ "$status" -ne 0 ]
}
