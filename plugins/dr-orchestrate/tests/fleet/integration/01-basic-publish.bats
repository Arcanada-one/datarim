#!/usr/bin/env bats
# integration/01-basic-publish.bats — V-AC-8: end-to-end publish via real Redis.
# Skips (exit 77) if Redis unavailable — not a failure, just no local broker.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
BUS_ADAPTER="$PLUGIN_ROOT/scripts/bus_adapter.sh"
VALIDATOR="$PLUGIN_ROOT/bin/fleet-validate-message.sh"

REDIS_URL="${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}"

setup() {
  TMP="$(mktemp -d)"
  export DR_FLEET_BUS_BACKEND=redis
  export DR_ORCH_REDIS_URL="$REDIS_URL"
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
}

teardown() {
  rm -rf "$TMP"
  if (( REDIS_AVAILABLE )); then
    redis-cli -u "$REDIS_URL" DEL \
      "stream:fleet:task-events" \
      "stream:fleet:monitoring-alerts" \
      "stream:fleet:fleet-commands" \
      "stream:fleet:audit-log" >/dev/null 2>&1 || true
  fi
}

# ── redis ping gate ───────────────────────────────────────────────────────────

@test "V-AC-8 prereq: Redis reachable or skip" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available (redis-cli missing or broker not running) — not a failure"
  fi
  run redis-cli -u "$REDIS_URL" ping
  [ "$status" -eq 0 ]
  [[ "$output" == *"PONG"* ]]
}

# ── four topics created on first publish ─────────────────────────────────────

@test "V-AC-8: publish to fleet:task-events creates stream" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash -c "source '$BUS_ADAPTER' && bus_publish 'fleet:task-events' \
    id '550e8400-e29b-41d4-a716-446655440010' \
    ts '2026-06-09T10:00:00Z' \
    type 'lifecycle' \
    from 'test-agent' \
    to 'pm-orchestrator'"
  [ "$status" -eq 0 ]
  len=$(redis-cli -u "$REDIS_URL" XLEN "stream:fleet:task-events")
  [ "$len" -ge 1 ]
}

@test "V-AC-8: publish to fleet:monitoring-alerts creates stream" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash -c "source '$BUS_ADAPTER' && bus_publish 'fleet:monitoring-alerts' \
    id '550e8400-e29b-41d4-a716-446655440011' \
    ts '2026-06-09T10:00:01Z' \
    type 'alert' \
    from 'monitor-dev' \
    to 'pm-orchestrator'"
  [ "$status" -eq 0 ]
  len=$(redis-cli -u "$REDIS_URL" XLEN "stream:fleet:monitoring-alerts")
  [ "$len" -ge 1 ]
}

@test "V-AC-8: publish to fleet:fleet-commands creates stream" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash -c "source '$BUS_ADAPTER' && bus_publish 'fleet:fleet-commands' \
    id '550e8400-e29b-41d4-a716-446655440012' \
    ts '2026-06-09T10:00:02Z' \
    type 'command' \
    from 'pm-orchestrator' \
    to 'fleet-daemon'"
  [ "$status" -eq 0 ]
  len=$(redis-cli -u "$REDIS_URL" XLEN "stream:fleet:fleet-commands")
  [ "$len" -ge 1 ]
}

@test "V-AC-8: publish to fleet:audit-log creates stream" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash -c "source '$BUS_ADAPTER' && bus_publish 'fleet:audit-log' \
    id '550e8400-e29b-41d4-a716-446655440013' \
    ts '2026-06-09T10:00:03Z' \
    type 'audit' \
    from 'agent-1' \
    to 'audit-log'"
  [ "$status" -eq 0 ]
  len=$(redis-cli -u "$REDIS_URL" XLEN "stream:fleet:audit-log")
  [ "$len" -ge 1 ]
}

# ── message ID returned ───────────────────────────────────────────────────────

@test "V-AC-8: bus_publish returns a Redis stream message ID" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  result=$(bash -c "source '$BUS_ADAPTER' && bus_publish 'fleet:task-events' \
    id '550e8400-e29b-41d4-a716-446655440014' \
    ts '2026-06-09T10:00:04Z' \
    type 'heartbeat' \
    from 'agent-1' \
    to 'pm-orchestrator'")
  # Redis stream ID format: <ms>-<seq>
  [[ "$result" =~ ^[0-9]+-[0-9]+$ ]]
}

# ── replay retrieves published messages ──────────────────────────────────────

@test "V-AC-8: bus_replay retrieves published messages from XRANGE" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  # Publish a message
  bash -c "source '$BUS_ADAPTER' && bus_publish 'fleet:task-events' \
    id 'replay-uuid-001' ts '2026-06-09T10:00:05Z' type lifecycle from test to pm" >/dev/null
  # Replay from beginning
  run bash -c "source '$BUS_ADAPTER' && bus_replay 'fleet:task-events' '-'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"replay-uuid-001"* ]]
}

# ── validator rejects bad message before publish ──────────────────────────────

@test "V-AC-8: validate+publish rejects message with invalid type" {
  if (( ! REDIS_AVAILABLE )); then
    skip "Redis not available"
  fi
  run bash "$VALIDATOR" \
    --id "bad-type-uuid" \
    --ts "2026-06-09T10:00:00Z" \
    --type "invalid-type" \
    --from "test" \
    --to "pm"
  [ "$status" -eq 1 ]
}
