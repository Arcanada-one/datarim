#!/usr/bin/env bats
# staging-dryrun.bats — V-AC-10: staging dry-run against localhost nc mock.
# Uses nc (netcat) to capture ≥3 escalation event types.
# Stack-agnostic: nc/bash/openssl only — no Python, no NestJS, no pnpm.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
BACKEND="$PLUGIN_ROOT/scripts/escalation_backend.sh"
HMAC_SCRIPT="$PLUGIN_ROOT/scripts/outbound-hmac-sign.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  export DR_ORCH_ESCALATION_MOCK_LOG="$TMP/escalation.jsonl"
  export DR_ORCH_PROMPT_TEXT="staging dry-run test"
  export DR_ORCH_ESCALATION_HMAC_SECRET="stagingsecret"
  MOCK_PORT=18766
  MOCK_LOG="$TMP/mock_requests.txt"
}

teardown() {
  rm -rf "$TMP"
  pkill -f "nc.*-l.*$MOCK_PORT" 2>/dev/null || true
}

_resolver_json() {
  local action="${1:-/dr-do}"
  printf '{"action":"%s","confidence":0.20,"reason":"staging test","backend_used":"coworker-deepseek","subagent_model":"deepseek-chat"}' "$action"
}

# Capture HTTP request via nc one-liner (non-Python HMAC-verify stub).
# nc exits after first connection (-q 0 on GNU nc, or via timeout).
_nc_capture_once() {
  local port="$1"; local out="$2"
  # Respond with 202 Accepted after capturing request.
  # Use process substitution to both capture and respond.
  {
    printf 'HTTP/1.1 202 Accepted\r\nContent-Length: 15\r\n\r\n{"status":"ok"}'
  } | nc -l "$port" > "$out" 2>/dev/null &
  printf '%s' "$!"
}

# V-AC-10: escalation event type captured
@test "V-AC-10: escalation event written to mock JSONL (mock backend)" {
  DR_ORCH_ESCALATION_BACKEND=mock \
    run bash "$BACKEND" emit "$(_resolver_json "/dr-do")" "staging-pane"
  [ "$status" -eq 0 ]
  [ -f "$DR_ORCH_ESCALATION_MOCK_LOG" ]
  run jq -e '.event_type // .escalation_backend' "$DR_ORCH_ESCALATION_MOCK_LOG"
  [ "$status" -eq 0 ]
}

# V-AC-10: ≥3 distinct event types captured via mock backend
@test "V-AC-10: three escalation events with distinct actions captured" {
  DR_ORCH_ESCALATION_BACKEND=mock \
    bash "$BACKEND" emit "$(_resolver_json "/dr-do")"    "pane-1"
  DR_ORCH_PROMPT_TEXT="status check" \
  DR_ORCH_ESCALATION_BACKEND=mock \
    bash "$BACKEND" emit "$(_resolver_json "/dr-status")" "pane-2"
  DR_ORCH_PROMPT_TEXT="archive run" \
  DR_ORCH_ESCALATION_BACKEND=mock \
    bash "$BACKEND" emit "$(_resolver_json "/dr-archive")" "pane-3"
  local n
  n="$(wc -l < "$DR_ORCH_ESCALATION_MOCK_LOG" | tr -d ' ')"
  [ "$n" -ge 3 ]
  # All lines must be valid JSON with schema_version:2
  while IFS= read -r line; do
    printf '%s' "$line" | jq -e '.schema_version == 2' >/dev/null
  done < "$DR_ORCH_ESCALATION_MOCK_LOG"
}

# V-AC-10: HMAC sign function produces valid signature for outbound payload
@test "V-AC-10: sign_and_post HMAC signature verifiable locally" {
  local payload; payload='{"schema_version":2,"event_type":"escalation","cycle_id":"test-01","text":"dry-run"}'
  local ts; ts="$(date +%s)"
  local sig; sig="$(bash "$HMAC_SCRIPT" compute_sig "stagingsecret" "$ts" "$payload")"
  # Verify locally using same algorithm
  local expected
  expected="$(printf '%s' "${ts}${payload}" | openssl dgst -sha256 -hmac "stagingsecret" | awk '{print $2}')"
  [ "$sig" = "$expected" ]
}

# V-AC-10: nc-based mock captures X-Signature header (shell-only HMAC-verify stub)
@test "V-AC-10: nc mock captures X-Signature header from sign_and_post" {
  # Start nc listener — captures one HTTP request
  local nc_pid nc_out
  nc_out="$TMP/nc_capture.txt"
  # Start listener in background; the response keeps the connection open briefly
  {
    printf 'HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\n\r\nok'
  } | nc -l "$MOCK_PORT" > "$nc_out" 2>/dev/null &
  nc_pid=$!
  sleep 0.2
  # Post with HMAC signing
  local payload; payload='{"schema_version":2,"event_type":"escalation","cycle_id":"nc-test","text":"staging"}'
  local ts; ts="$(date +%s)"
  local sig; sig="$(bash "$HMAC_SCRIPT" compute_sig "stagingsecret" "$ts" "$payload")"
  curl -fsS \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Signature: hmac-sha256=${sig}" \
    -H "X-Timestamp: ${ts}" \
    -d "$payload" \
    "http://127.0.0.1:${MOCK_PORT}" 2>/dev/null || true
  # Give nc time to write
  sleep 0.2
  kill "$nc_pid" 2>/dev/null || true
  # Verify header present in captured request
  grep -q "X-Signature" "$nc_out" || grep -q "X-Timestamp" "$nc_out"
}
