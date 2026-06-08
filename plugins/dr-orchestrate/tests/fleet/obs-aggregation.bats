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
  export DR_ORCH_REDIS_URL="$REDIS_URL"
  export DR_FLEET_BUS_BACKEND=mock
  export DR_FLEET_MOCK_LOG="$TMP/mock.log"
  export DR_FLEET_MOCK_XADD_ID="1700000000000-0"
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
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
