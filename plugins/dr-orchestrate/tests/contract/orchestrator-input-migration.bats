#!/usr/bin/env bats
# orchestrator-input-migration.bats — TUNE-0295 Phase C V-AC-6
# Verifies handler supports BOTH legacy signature (named-arg + positional)
# AND new uniform 4-arg signature (<method> <path> <body-file> <headers-file>).
# Mode detection: $1 starts with '-' → named, '[A-Z]' → uniform, else → positional.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HANDLER="$PLUGIN_ROOT/scripts/orchestrator-input-handler.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  export DR_ORCH_INBOUND_TOKEN="testtoken123"
  TMP="$(mktemp -d)"
  export DR_ORCH_INBOX_DIR="$TMP/inbox"
  mkdir -p "$DR_ORCH_INBOX_DIR"
  export DR_ORCH_ESCALATION_MOCK_LOG="$TMP/escalation.jsonl"
}

teardown() {
  rm -rf "$TMP"
}

_body() {
  local cmd="${1:-dr-status}"
  printf '{"session_id":"testsession01","command":"%s","ts":"2026-05-24T00:00:00Z"}' "$cmd"
}

@test "V-AC-6 §legacy named-arg: --body --auth --sync-timeout still works" {
  run bash "$HANDLER" --body "$(_body dr-status)" --auth "testtoken123" --sync-timeout 1500
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$output' | jq -e '.event_type==\"complete\"'"
  [ "$status" -eq 0 ]
}

@test "V-AC-6 §uniform: POST /hooks/orchestrator-input <body-file> emits handler-protocol envelope" {
  local bf hf
  bf="$TMP/body"
  hf="$TMP/hdrs"
  _body dr-status >"$bf"
  printf 'Content-Type: application/json\r\nX-Sync-Timeout: 1500\r\n' >"$hf"
  run bash "$HANDLER" POST /hooks/orchestrator-input "$bf" "$hf"
  [ "$status" -eq 0 ]
  # Handler protocol: <status>\r\n<headers>\r\n\r\n<body>
  [[ "$output" == "200"* ]]
  [[ "$output" == *"Content-Type: application/json"* ]]
  [[ "$output" == *'"event_type":"complete"'* ]]
}

@test "V-AC-6 §uniform: invalid JSON body → 400 in handler-protocol" {
  local bf hf
  bf="$TMP/body"; hf="$TMP/hdrs"
  printf 'not-json' >"$bf"
  printf '' >"$hf"
  run bash "$HANDLER" POST /hooks/orchestrator-input "$bf" "$hf"
  [ "$status" -eq 0 ]
  [[ "$output" == "400"* ]]
}

@test "V-AC-6 §uniform: async path (no X-Sync-Timeout header) → 202 + inbox file" {
  local bf hf
  bf="$TMP/body"; hf="$TMP/hdrs"
  _body dr-run >"$bf"
  printf 'Content-Type: application/json\r\n' >"$hf"  # no X-Sync-Timeout
  run bash "$HANDLER" POST /hooks/orchestrator-input "$bf" "$hf"
  [ "$status" -eq 0 ]
  [[ "$output" == "202"* ]]
  # inbox file written
  [ "$(ls -1 "$DR_ORCH_INBOX_DIR" | wc -l | tr -d ' ')" -ge 1 ]
}

@test "V-AC-6 §legacy positional: <raw_body> [timeout] still consumed (adnanh compat shim)" {
  # adnanh-style: positional body + timeout. In uniform mode signal absent
  # (first arg not [A-Z] and not '--'). Auth bypassed (preauthd).
  run bash "$HANDLER" "$(_body dr-help)" 1500
  [ "$status" -eq 0 ]
  run bash -c "printf '%s' '$output' | jq -e '.event_type==\"complete\"'"
  [ "$status" -eq 0 ]
}
