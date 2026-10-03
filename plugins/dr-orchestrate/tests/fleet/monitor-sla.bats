#!/usr/bin/env bats
# monitor-sla.bats — V-AC-4: monitoring consumer SLA timing + idempotent filter.
# Contract tests run without Redis. Integration tests skip when Redis absent.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
MONITOR="$PLUGIN_ROOT/scripts/fleet_monitor_consumer.sh"

REDIS_URL="${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}"

setup() {
  TMP="$(mktemp -d)"
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

# ── executable + help ─────────────────────────────────────────────────────────

@test "V-AC-4: fleet_monitor_consumer.sh is executable" {
  [ -x "$MONITOR" ]
}

@test "V-AC-4: fleet_monitor_consumer.sh --help exits 0" {
  run bash "$MONITOR" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]]
}

# ── check mode — no Redis needed ──────────────────────────────────────────────

@test "V-AC-4: --check mode prints config and exits 0" {
  run bash "$MONITOR" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"group"* ]]
}

# ── SLA threshold configuration ───────────────────────────────────────────────

@test "V-AC-4: SLA threshold env vars accepted" {
  DR_FLEET_MONITOR_SLA_WARN=60 \
  DR_FLEET_MONITOR_SLA_CRIT=300 \
  run bash "$MONITOR" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"sla_warn"* ]]
}

# ── idempotent filter: no duplicate alerts ────────────────────────────────────

@test "V-AC-4: idempotent_check function exists" {
  run bash -c "source '$MONITOR' && declare -f idempotent_check"
  [ "$status" -eq 0 ]
}

@test "V-AC-4: idempotent_check returns 0 for new alert key" {
  run bash -c "
    export DR_FLEET_MONITOR_ALERT_STATE_DIR='$TMP/state'
    source '$MONITOR'
    idempotent_check 'test-alert-key-001'
  "
  [ "$status" -eq 0 ]
}

@test "V-AC-4: idempotent_check returns 1 for already-seen key" {
  run bash -c "
    export DR_FLEET_MONITOR_ALERT_STATE_DIR='$TMP/state'
    source '$MONITOR'
    idempotent_check 'test-alert-key-002'
    idempotent_check 'test-alert-key-002'
  "
  [ "$status" -eq 1 ]
}

# ── consumer groups ───────────────────────────────────────────────────────────

@test "V-AC-4: --check shows monitor-dev consumer group" {
  run bash "$MONITOR" --check --branch dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"monitor-dev"* ]]
}

@test "V-AC-4: --check shows monitor-main consumer group" {
  run bash "$MONITOR" --check --branch main
  [ "$status" -eq 0 ]
  [[ "$output" == *"monitor-main"* ]]
}

# ── Redis integration: single pass ───────────────────────────────────────────

@test "V-AC-4: --once mode processes one batch and exits 0" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash "$MONITOR" --once --branch dev
  [ "$status" -eq 0 ]
}
