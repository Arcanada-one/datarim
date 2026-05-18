#!/usr/bin/env bats
# outbound-redis.bats — V-AC-9: Redis PUBLISH backend.
# Requires redis-cli in PATH. Skip if not available.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
REDIS_SCRIPT="$PLUGIN_ROOT/scripts/outbound-redis-publish.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  export DR_ORCH_OUTBOUND_REDIS_URL="redis://127.0.0.1:6379"
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 && redis-cli -u "$DR_ORCH_OUTBOUND_REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
}

teardown() {
  rm -rf "$TMP"
}

_payload() {
  printf '%s' '{"schema_version":2,"event_type":"escalation","cycle_id":"01926f00-0000-7000-8000-000000000001","session_id":"testsession01","text":"test"}'
}

# publish_event function must exist
@test "V-AC-9: publish_event function exists in script" {
  run bash -c "source '$REDIS_SCRIPT' && declare -f publish_event"
  [ "$status" -eq 0 ]
}

# Channel name format: orchestrator-out:<session_id>
@test "V-AC-9: channel name format is orchestrator-out:<session_id>" {
  local ch
  ch="$(bash "$REDIS_SCRIPT" channel_name "mysessionid01")"
  [ "$ch" = "orchestrator-out:mysessionid01" ]
}

# Redis unavailable → exits 0 (graceful skip) or exits non-zero with clear ERR
@test "V-AC-9: publish_event without redis-cli exits gracefully" {
  if (( REDIS_AVAILABLE )); then
    skip "redis available — testing live path only"
  fi
  DR_ORCH_OUTBOUND_REDIS_URL="redis://127.0.0.1:16379" \
    run bash "$REDIS_SCRIPT" publish_event "testsession01" "$(_payload)"
  # Should exit non-zero with ERR message (redis unavailable)
  [ "$status" -ne 0 ]
}

# Live test: subscribe and publish, check receipt
@test "V-AC-9: publish_event publishes to correct channel (live)" {
  if (( REDIS_AVAILABLE == 0 )); then
    skip "redis-cli not available or Redis not running"
  fi
  SESSION_ID="testsession01"
  CHANNEL="orchestrator-out:${SESSION_ID}"
  PAYLOAD="$(_payload)"
  RECV="$TMP/received.txt"
  # Background subscriber
  redis-cli subscribe "$CHANNEL" >"$RECV" 2>&1 &
  SUB_PID=$!
  sleep 0.3
  bash "$REDIS_SCRIPT" publish_event "$SESSION_ID" "$PAYLOAD"
  sleep 0.3
  kill "$SUB_PID" 2>/dev/null || true
  grep -q "escalation" "$RECV"
}
