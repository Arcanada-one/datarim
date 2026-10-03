#!/usr/bin/env bats
# V-AC-6 — HALT sentinel → every subcommand exits 17, no bypass.
# Source: TUNE-0271 plan § Detailed Design 4.3.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    KS_LIB="$CLI_DIR/lib/kill-switch.sh"
    DATARIM_BIN="$CLI_DIR/datarim"
    UUID_GEN="$CLI_DIR/lib/uuid7-gen.sh"
    [ -x "$DATARIM_BIN" ] || skip "datarim binary missing"

    # Per-test sentinel path — isolate from operator's real ~/.config.
    TMP_DIR="$(mktemp -d)"
    export DATARIM_CLI_HALT_PATH="$TMP_DIR/HALT"
    export DATARIM_CLI_AGENT_ID
    DATARIM_CLI_AGENT_ID="$("$UUID_GEN")"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" || true
}

@test "V-AC-6: HALT absent → datarim version exits 0" {
    run "$DATARIM_BIN" version
    [ "$status" -eq 0 ]
}

@test "V-AC-6: HALT present → datarim version exits 17" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" version
    [ "$status" -eq 17 ]
    [[ "$output" == *"halted by"* ]]
}

@test "V-AC-6: HALT present → datarim help exits 17 (no read-only bypass)" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" help
    [ "$status" -eq 17 ]
}

@test "V-AC-6: HALT present → datarim run exits 17 BEFORE agent-id check" {
    : > "$DATARIM_CLI_HALT_PATH"
    # Even with invalid agent ID, HALT fires first (exit 17, not 22).
    DATARIM_CLI_AGENT_ID="garbage" \
        run "$DATARIM_BIN" run /dr-status
    [ "$status" -eq 17 ]
}

@test "V-AC-6: HALT present → datarim audit exits 17" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" audit log
    [ "$status" -eq 17 ]
}

@test "V-AC-6: HALT present → unknown subcommand still exits 17" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" totally-fake-cmd
    [ "$status" -eq 17 ]
}

@test "V-AC-6: kill_switch_engage creates sentinel + idempotent" {
    bash -c ". '$KS_LIB'; kill_switch_engage"
    [ -e "$DATARIM_CLI_HALT_PATH" ]
    # Second engage is no-op (still present, no error).
    run bash -c ". '$KS_LIB'; kill_switch_engage"
    [ "$status" -eq 0 ]
}

@test "V-AC-6: kill_switch_disengage removes sentinel; idempotent if absent" {
    : > "$DATARIM_CLI_HALT_PATH"
    bash -c ". '$KS_LIB'; kill_switch_disengage"
    [ ! -e "$DATARIM_CLI_HALT_PATH" ]
    # Disengage on absent file is no-op.
    run bash -c ". '$KS_LIB'; kill_switch_disengage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already disengaged"* ]]
}
