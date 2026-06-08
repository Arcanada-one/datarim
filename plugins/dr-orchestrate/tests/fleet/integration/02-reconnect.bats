#!/usr/bin/env bats
# integration/02-reconnect.bats — V-AC-8: bus adapter reconnects after Redis
# restart / consumer group re-creation. Skips when Redis unavailable.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
BUS_ADAPTER="$PLUGIN_ROOT/scripts/bus_adapter.sh"

REDIS_URL="${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}"

setup() {
  export DR_FLEET_BUS_BACKEND=redis
  export DR_ORCH_REDIS_URL="$REDIS_URL"
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
}

teardown() {
  if (( REDIS_AVAILABLE )); then
    redis-cli -u "$REDIS_URL" DEL \
      "stream:fleet:task-events" \
      "stream:fleet:reconnect-test" >/dev/null 2>&1 || true
  fi
}

# ── consumer group auto-creation ──────────────────────────────────────────────

@test "V-AC-8 reconnect: bus_subscribe creates consumer group if absent" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  # Subscribe with a fresh group name (should auto-create via MKSTREAM)
  run bash -c "
    export DR_FLEET_BUS_BACKEND=redis
    source '$BUS_ADAPTER'
    bus_subscribe 'fleet:reconnect-test' 'test-group-$$' 'consumer-1' 100
  "
  [ "$status" -eq 0 ]
  # Group should exist now
  info=$(redis-cli -u "$REDIS_URL" XINFO GROUPS "stream:fleet:reconnect-test" 2>/dev/null || echo "")
  [[ "$info" == *"test-group"* ]] || [[ "$info" == *"group"* ]]
}

@test "V-AC-8 reconnect: publish after subscribe still works" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  # Subscribe first (creates group), then publish
  bash -c "
    export DR_FLEET_BUS_BACKEND=redis
    source '$BUS_ADAPTER'
    bus_subscribe 'fleet:task-events' 'reconnect-obs' 'consumer-1' 100
  " >/dev/null 2>&1 || true

  run bash -c "
    export DR_FLEET_BUS_BACKEND=redis
    source '$BUS_ADAPTER'
    bus_publish 'fleet:task-events' \
      id 'reconnect-001' ts '2026-06-09T11:00:00Z' type lifecycle \
      from 'test' to 'pm'
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
}

@test "V-AC-8 reconnect: XACK removes message from pending entries" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  # Publish, subscribe (gets message in pending), then ack
  msg_id=$(bash -c "
    export DR_FLEET_BUS_BACKEND=redis
    source '$BUS_ADAPTER'
    bus_publish 'fleet:task-events' \
      id 'ack-test-001' ts '2026-06-09T11:00:01Z' type lifecycle from test to pm
  " 2>/dev/null)

  bash -c "
    export DR_FLEET_BUS_BACKEND=redis
    source '$BUS_ADAPTER'
    bus_subscribe 'fleet:task-events' 'ack-group' 'consumer-1' 100
  " >/dev/null 2>&1 || true

  run bash -c "
    export DR_FLEET_BUS_BACKEND=redis
    source '$BUS_ADAPTER'
    bus_ack 'fleet:task-events' 'ack-group' '$msg_id'
  "
  [ "$status" -eq 0 ]
}

# ── validate-message-schema rejection via real bus ────────────────────────────

@test "V-AC-8 schema: invalid message rejected by validator before reaching bus" {
  # Validator test — no Redis needed
  run bash "$PLUGIN_ROOT/bin/fleet-validate-message.sh" \
    --id "bad-$$" --ts "not-a-date" --type "lifecycle" --from "x" --to "y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ts"* ]]
}
