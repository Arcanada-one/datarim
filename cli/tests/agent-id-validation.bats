#!/usr/bin/env bats
# V-AC-23 — DATARIM_CLI_AGENT_ID must be UUID v7; unset/v4 → exit 22.
# Source: TUNE-0271 plan § Detailed Design 4.6.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    AGENT_LIB="$CLI_DIR/lib/agent-id.sh"
    UUID_GEN="$CLI_DIR/lib/uuid7-gen.sh"
    [ -f "$AGENT_LIB" ] || skip "agent-id.sh missing"
    [ -x "$UUID_GEN" ] || skip "uuid7-gen.sh missing"
}

run_validate() {
    # Run validate_agent_id in a subshell so env vars stay local.
    bash -c ". '$AGENT_LIB'; validate_agent_id" 2>&1
}

@test "V-AC-23: unset DATARIM_CLI_AGENT_ID → exit 22" {
    unset DATARIM_CLI_AGENT_ID
    run env -u DATARIM_CLI_AGENT_ID bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
    [[ "$output" == *"unset or empty"* ]]
}

@test "V-AC-23: empty DATARIM_CLI_AGENT_ID → exit 22" {
    DATARIM_CLI_AGENT_ID="" run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
}

@test "V-AC-23: UUID v4 → exit 22 (version nibble mismatch)" {
    # canonical v4 example (version=4)
    DATARIM_CLI_AGENT_ID="550e8400-e29b-41d4-a716-446655440000" \
        run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
    [[ "$output" == *"not a valid UUID v7"* ]]
}

@test "V-AC-23: random garbage → exit 22" {
    DATARIM_CLI_AGENT_ID="not-a-uuid" \
        run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
}

@test "V-AC-23: variant nibble outside {8,9,a,b} → exit 22" {
    # version=7 but variant=c (not 10xx)
    DATARIM_CLI_AGENT_ID="01900000-0000-7000-c000-000000000000" \
        run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
}

@test "V-AC-23: fresh uuidgen output passes" {
    # Generate using our helper.
    local id
    id="$("$UUID_GEN")"
    [ -n "$id" ]
    DATARIM_CLI_AGENT_ID="$id" \
        run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "V-AC-23: ancient timestamp (year 1970) → exit 22" {
    # 48 bits of ms = 1 → 1970-01-01.
    DATARIM_CLI_AGENT_ID="00000000-0001-7000-8000-000000000000" \
        run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
    [[ "$output" == *"out of acceptable window"* ]]
}

@test "V-AC-23: regex match but future-distant (year 9999) → exit 22" {
    # 48 bits = 0xffffffffffff ≈ year 10889 — far beyond 1h ahead.
    DATARIM_CLI_AGENT_ID="ffffffff-ffff-7fff-8fff-ffffffffffff" \
        run bash -c ". '$AGENT_LIB'; validate_agent_id"
    [ "$status" -eq 22 ]
}
