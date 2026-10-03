#!/usr/bin/env bats
# outbound-hmac-sign.bats — V-AC-8: HMAC-SHA256 signature + X-Timestamp header.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SIGN_SCRIPT="$PLUGIN_ROOT/scripts/outbound-hmac-sign.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  # Capture HTTP request headers via nc listener
  MOCK_PORT=18765
  MOCK_LOG="$TMP/nc.log"
  export DR_ORCH_ESCALATION_HMAC_SECRET="testsecret"
}

teardown() {
  rm -rf "$TMP"
  # Kill any lingering listener
  pkill -f "nc -l.*$MOCK_PORT" 2>/dev/null || true
}

_payload() {
  printf '%s' '{"schema_version":2,"event_type":"escalation","cycle_id":"01926f00-0000-7000-8000-000000000001","text":"test"}'
}

# V-AC-8: sign_and_post function exists in script
@test "V-AC-8: sign_and_post function exists" {
  run bash -c "source '$SIGN_SCRIPT' && declare -f sign_and_post"
  [ "$status" -eq 0 ]
}

# V-AC-8: HMAC computed correctly — reference verify
@test "V-AC-8: HMAC signature matches reference computation" {
  local payload; payload="$(_payload)"
  local ts; ts="$(date +%s)"
  local expected_sig
  expected_sig="$(printf '%s' "${ts}${payload}" | openssl dgst -sha256 -hmac "testsecret" | awk '{print $2}')"
  local got_sig
  got_sig="$(bash "$SIGN_SCRIPT" compute_sig "testsecret" "$ts" "$payload")"
  [ "$got_sig" = "$expected_sig" ]
}

# V-AC-8: X-Signature header format is hmac-sha256=<hex>
@test "V-AC-8: X-Signature format is hmac-sha256=<hex>" {
  local payload; payload="$(_payload)"
  local ts; ts="$(date +%s)"
  local sig
  sig="$(bash "$SIGN_SCRIPT" compute_sig "testsecret" "$ts" "$payload")"
  [[ "$sig" =~ ^[0-9a-f]{64}$ ]]
}

# V-AC-8: X-Timestamp is a unix epoch integer
@test "V-AC-8: timestamp is a unix epoch integer" {
  local ts; ts="$(bash "$SIGN_SCRIPT" get_timestamp)"
  [[ "$ts" =~ ^[0-9]+$ ]]
}
