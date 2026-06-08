#!/usr/bin/env bats
# bus-adapter-contract.bats — V-AC-1: bus adapter exposes publish/subscribe/ack/replay
# port functions. Runs with DR_FLEET_BUS_BACKEND=mock (no Redis required).

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
BUS_ADAPTER="$PLUGIN_ROOT/scripts/bus_adapter.sh"

setup() {
  export DR_FLEET_BUS_BACKEND=mock
  export DR_ORCH_REDIS_URL="redis://127.0.0.1:6379"
  TMP="$(mktemp -d)"
  export DR_FLEET_MOCK_LOG="$TMP/mock.log"
  export DR_FLEET_MOCK_XADD_ID="1700000000000-0"
}

teardown() {
  rm -rf "$TMP"
}

# ── function existence ────────────────────────────────────────────────────────

@test "V-AC-1: bus_publish function exists" {
  run bash -c "source '$BUS_ADAPTER' && declare -f bus_publish"
  [ "$status" -eq 0 ]
}

@test "V-AC-1: bus_subscribe function exists" {
  run bash -c "source '$BUS_ADAPTER' && declare -f bus_subscribe"
  [ "$status" -eq 0 ]
}

@test "V-AC-1: bus_ack function exists" {
  run bash -c "source '$BUS_ADAPTER' && declare -f bus_ack"
  [ "$status" -eq 0 ]
}

@test "V-AC-1: bus_replay function exists" {
  run bash -c "source '$BUS_ADAPTER' && declare -f bus_replay"
  [ "$status" -eq 0 ]
}

# ── mock backend: bus_publish logs XADD command ──────────────────────────────

@test "V-AC-1 mock: bus_publish writes XADD record to mock log" {
  run bash -c "
    source '$BUS_ADAPTER'
    bus_publish 'fleet:task-events' id uuid-1 ts 2026-06-09T00:00:00Z type lifecycle
  "
  [ "$status" -eq 0 ]
  [ -f "$DR_FLEET_MOCK_LOG" ]
  grep -q 'XADD' "$DR_FLEET_MOCK_LOG"
}

@test "V-AC-1 mock: bus_publish echoes the stream key in mock log" {
  run bash -c "
    source '$BUS_ADAPTER'
    bus_publish 'fleet:task-events' id uuid-2 ts 2026-06-09T00:00:01Z type lifecycle
  "
  [ "$status" -eq 0 ]
  grep -q 'fleet:task-events' "$DR_FLEET_MOCK_LOG"
}

@test "V-AC-1 mock: bus_publish returns mock message ID" {
  run bash -c "
    source '$BUS_ADAPTER'
    bus_publish 'fleet:task-events' id uuid-3 ts 2026-06-09T00:00:02Z type lifecycle
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"1700000000000-0"* ]]
}

@test "V-AC-1 mock: bus_ack logs XACK command to mock log" {
  run bash -c "
    source '$BUS_ADAPTER'
    bus_ack 'fleet:task-events' 'obs' '1700000000000-0'
  "
  [ "$status" -eq 0 ]
  grep -q 'XACK' "$DR_FLEET_MOCK_LOG"
}

@test "V-AC-1 mock: bus_replay logs XRANGE command to mock log" {
  run bash -c "
    source '$BUS_ADAPTER'
    bus_replay 'fleet:audit-log' '-'
  "
  [ "$status" -eq 0 ]
  grep -q 'XRANGE' "$DR_FLEET_MOCK_LOG"
}

@test "V-AC-1 mock: bus_subscribe logs XREADGROUP command to mock log" {
  run bash -c "
    source '$BUS_ADAPTER'
    bus_subscribe 'fleet:task-events' 'obs' 'consumer-1' 100
  "
  [ "$status" -eq 0 ]
  grep -q 'XREADGROUP' "$DR_FLEET_MOCK_LOG"
}

# ── topic names ──────────────────────────────────────────────────────────────

@test "V-AC-1: four topic constants defined" {
  run bash -c "
    source '$BUS_ADAPTER'
    echo \"\$FLEET_TOPIC_TASK_EVENTS\"
    echo \"\$FLEET_TOPIC_MONITORING_ALERTS\"
    echo \"\$FLEET_TOPIC_FLEET_COMMANDS\"
    echo \"\$FLEET_TOPIC_AUDIT_LOG\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"fleet:task-events"* ]]
  [[ "$output" == *"fleet:monitoring-alerts"* ]]
  [[ "$output" == *"fleet:fleet-commands"* ]]
  [[ "$output" == *"fleet:audit-log"* ]]
}

# ── backend guard ─────────────────────────────────────────────────────────────

@test "V-AC-1: unknown backend exits non-zero" {
  run bash -c "
    export DR_FLEET_BUS_BACKEND=unknown
    source '$BUS_ADAPTER' 2>/dev/null || true
    bus_publish 'fleet:task-events' id x ts y type lifecycle 2>&1
  "
  [ "$status" -ne 0 ]
}
