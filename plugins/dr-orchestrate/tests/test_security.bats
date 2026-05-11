#!/usr/bin/env bats
# test_security.bats — V-AC 6, 7, 8

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export STATE_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$STATE_DIR"
}

@test "V-AC-6: byte 0x1b blocked by check_escape" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    payload="$(printf 'safe\x1bdanger')"
    run check_escape "$payload"
    [ "$status" -eq 1 ]
}

@test "V-AC-6: clean ascii passes check_escape" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    run check_escape "/dr-plan TUNE-0164"
    [ "$status" -eq 0 ]
}

@test "V-AC-7: micro-cooldown gates back-to-back sends" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    run check_cooldown pane_test micro
    [ "$status" -eq 0 ]
    run check_cooldown pane_test micro
    [ "$status" -eq 1 ]
}

@test "V-AC-8: 5 violations within an hour block the pane" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    for _ in 1 2 3 4 5; do
        record_violation pane_block_test micro
    done
    run is_pane_blocked pane_block_test
    [ "$status" -eq 0 ]
}

@test "V-AC-8: 4 violations are not enough to block" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    for _ in 1 2 3 4; do
        record_violation pane_under_threshold micro
    done
    run is_pane_blocked pane_under_threshold
    [ "$status" -eq 1 ]
}

@test "M4: decision-kind 60s cooldown gates back-to-back autonomous decisions" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    run check_cooldown decision_pane_test decision
    [ "$status" -eq 0 ]
    run check_cooldown decision_pane_test decision
    [ "$status" -eq 1 ]
}

@test "M4: unknown cooldown kind returns exit 2" {
    source "$DR_ORCH_DIR/scripts/security.sh"
    run check_cooldown some_pane bogus
    [ "$status" -eq 2 ]
}
