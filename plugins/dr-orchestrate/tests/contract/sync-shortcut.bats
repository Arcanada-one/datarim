#!/usr/bin/env bats
# sync-shortcut.bats — V-AC-5/6: sync-shortcut whitelist behaviour.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HANDLER="$PLUGIN_ROOT/scripts/orchestrator-input-handler.sh"

_body() {
  local cmd="${1:-dr-status}"
  printf '{"session_id":"testsession01","command":"%s","ts":"2026-05-11T00:00:00Z"}' "$cmd"
}

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  export DR_ORCH_INBOUND_TOKEN="testtoken123"
  TMP="$(mktemp -d)"
  export DR_ORCH_INBOX_DIR="$TMP/inbox"
  mkdir -p "$TMP/inbox"
  export DR_ORCH_ESCALATION_MOCK_LOG="$TMP/escalation.jsonl"
}

teardown() {
  rm -rf "$TMP"
}

# V-AC-5: dr-status + X-Sync-Timeout 1500 → 200 (sync inline body)
@test "V-AC-5: dr-status with X-Sync-Timeout returns JSON event_type=complete" {
  run bash "$HANDLER" \
    --body "$(_body dr-status)" \
    --auth "testtoken123" \
    --sync-timeout 1500
  [ "$status" -eq 0 ]
  # output must be valid JSON with event_type complete
  run bash -c "printf '%s' '$output' | jq -e '.event_type == \"complete\"'"
  [ "$status" -eq 0 ]
}

# V-AC-5: dr-help + X-Sync-Timeout → 200 inline
@test "V-AC-5: dr-help with X-Sync-Timeout returns JSON event_type=complete" {
  run bash "$HANDLER" \
    --body "$(_body dr-help)" \
    --auth "testtoken123" \
    --sync-timeout 2000
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$output' | jq -e '.event_type == \"complete\"'"
  [ "$status" -eq 0 ]
}

# V-AC-6: non-whitelisted command + X-Sync-Timeout → 202 (header ignored, no inline body)
@test "V-AC-6: non-whitelisted command ignores X-Sync-Timeout, returns async (no JSON event)" {
  run bash "$HANDLER" \
    --body "$(_body "/dr-do TUNE-0175")" \
    --auth "testtoken123" \
    --sync-timeout 1500
  [ "$status" -eq 0 ]
  # async path: no JSON event on stdout (empty or minimal)
  # inbox file must exist
  count="$(ls "$TMP/inbox/" | wc -l | tr -d ' ')"
  [ "$count" -gt 0 ]
}

# V-AC-6: whitelisted command without X-Sync-Timeout → async path (inbox enqueue)
@test "V-AC-6: whitelisted command without sync-timeout goes async" {
  run bash "$HANDLER" \
    --body "$(_body dr-status)" \
    --auth "testtoken123"
  [ "$status" -eq 0 ]
  count="$(ls "$TMP/inbox/" | wc -l | tr -d ' ')"
  [ "$count" -gt 0 ]
}

# Sync response must include schema_version:2 and cycle_id
@test "sync response has schema_version 2 and cycle_id" {
  run bash "$HANDLER" \
    --body "$(_body dr-status)" \
    --auth "testtoken123" \
    --sync-timeout 1000
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$output' | jq -e '.schema_version == 2 and (.cycle_id | length) > 0'"
  [ "$status" -eq 0 ]
}

# Sync response must include session_id echo
@test "sync response echoes session_id" {
  run bash "$HANDLER" \
    --body "$(_body dr-status)" \
    --auth "testtoken123" \
    --sync-timeout 1000
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$output' | jq -e '.session_id == \"testsession01\"'"
  [ "$status" -eq 0 ]
}
