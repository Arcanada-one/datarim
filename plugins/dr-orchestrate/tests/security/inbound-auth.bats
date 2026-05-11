#!/usr/bin/env bats
# inbound-auth.bats — V-AC-3/4: Bearer auth guard for orchestrator-input handler.
# Tests the auth logic embedded in orchestrator-input-handler.sh.
# RED phase: handler does not exist yet.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HANDLER="$PLUGIN_ROOT/scripts/orchestrator-input-handler.sh"

# Minimal valid OrchestratorInput payload
_valid_body() {
  printf '%s' '{"session_id":"testsession01","command":"dr-status","ts":"2026-05-11T00:00:00Z"}'
}

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  export DR_ORCH_INBOUND_TOKEN="testtoken123"
  TMP="$(mktemp -d)"
  export DR_ORCH_ESCALATION_MOCK_LOG="$TMP/escalation.jsonl"
  INBOX_DIR="$TMP/inbox"
  mkdir -p "$INBOX_DIR"
  export DR_ORCH_INBOX_DIR="$INBOX_DIR"
}

teardown() {
  rm -rf "$TMP"
}

# V-AC-3: missing Authorization → exits 1 (http 401 equivalent at shell level)
@test "V-AC-3: missing auth token exits non-zero" {
  run bash "$HANDLER" \
    --body "$(_valid_body)" \
    --auth ""
  [ "$status" -ne 0 ]
}

# V-AC-3: wrong token → exits non-zero
@test "V-AC-3: wrong auth token exits non-zero" {
  run bash "$HANDLER" \
    --body "$(_valid_body)" \
    --auth "wrongtoken"
  [ "$status" -ne 0 ]
}

# V-AC-4: valid token → exits 0 (async 202 path)
@test "V-AC-4: valid auth token exits 0 (async queued)" {
  run bash "$HANDLER" \
    --body "$(_valid_body)" \
    --auth "testtoken123"
  [ "$status" -eq 0 ]
}

# V-AC-4: valid token + whitelisted command + sync timeout → exits 0 with output
@test "V-AC-4: valid token dr-status exits 0" {
  run bash "$HANDLER" \
    --body "$(_valid_body)" \
    --auth "testtoken123" \
    --sync-timeout 1500
  [ "$status" -eq 0 ]
}

# Guard: invalid JSON body → exits non-zero
@test "guard: invalid JSON body exits non-zero" {
  run bash "$HANDLER" \
    --body "not-json" \
    --auth "testtoken123"
  [ "$status" -ne 0 ]
}

# Guard: missing session_id in body → exits non-zero
@test "guard: missing session_id exits non-zero" {
  run bash "$HANDLER" \
    --body '{"command":"dr-status","ts":"2026-05-11T00:00:00Z"}' \
    --auth "testtoken123"
  [ "$status" -ne 0 ]
}
