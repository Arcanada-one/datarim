#!/usr/bin/env bats
# validate-message-contract.bats — V-AC-2: fleet-validate-message.sh rejects
# malformed messages and accepts valid ones. No Redis required.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VALIDATOR="$PLUGIN_ROOT/bin/fleet-validate-message.sh"

# ── valid messages ────────────────────────────────────────────────────────────

@test "V-AC-2: valid lifecycle message exits 0" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440000" \
    --ts "2026-06-09T12:00:00Z" \
    --type "lifecycle" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 0 ]
}

@test "V-AC-2: valid alert message exits 0" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440001" \
    --ts "2026-06-09T12:00:00Z" \
    --type "alert" \
    --from "monitor-dev" \
    --to "pm-orchestrator"
  [ "$status" -eq 0 ]
}

@test "V-AC-2: valid command message exits 0" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440002" \
    --ts "2026-06-09T12:00:00Z" \
    --type "command" \
    --from "pm-orchestrator" \
    --to "fleet-daemon"
  [ "$status" -eq 0 ]
}

@test "V-AC-2: valid audit message exits 0" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440003" \
    --ts "2026-06-09T12:00:00Z" \
    --type "audit" \
    --from "agent-1" \
    --to "audit-log"
  [ "$status" -eq 0 ]
}

@test "V-AC-2: valid heartbeat message exits 0" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440004" \
    --ts "2026-06-09T12:00:00Z" \
    --type "heartbeat" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 0 ]
}

# ── missing required fields ───────────────────────────────────────────────────

@test "V-AC-2: missing --id exits 1 with error message" {
  run bash "$VALIDATOR" \
    --ts "2026-06-09T12:00:00Z" \
    --type "lifecycle" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 1 ]
  [[ "$output" == *"id"* ]]
}

@test "V-AC-2: missing --ts exits 1" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440000" \
    --type "lifecycle" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 1 ]
}

@test "V-AC-2: missing --type exits 1" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440000" \
    --ts "2026-06-09T12:00:00Z" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 1 ]
}

# ── invalid field values ──────────────────────────────────────────────────────

@test "V-AC-2: invalid type (not in enum) exits 1" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440000" \
    --ts "2026-06-09T12:00:00Z" \
    --type "unknown-type" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 1 ]
  [[ "$output" == *"type"* ]]
}

@test "V-AC-2: invalid timestamp (non-ISO-8601) exits 1" {
  run bash "$VALIDATOR" \
    --id "550e8400-e29b-41d4-a716-446655440000" \
    --ts "not-a-date" \
    --type "lifecycle" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ts"* ]]
}

@test "V-AC-2: empty id exits 1" {
  run bash "$VALIDATOR" \
    --id "" \
    --ts "2026-06-09T12:00:00Z" \
    --type "lifecycle" \
    --from "agent-1" \
    --to "pm-orchestrator"
  [ "$status" -eq 1 ]
}
