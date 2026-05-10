#!/usr/bin/env bats
# test_plugin_register.bats — V-AC 1, 13, 15

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
}

@test "V-AC-1: plugin.yaml registers id dr-orchestrate" {
    run grep -E '^id:[[:space:]]+dr-orchestrate$' "$DR_ORCH_DIR/plugin.yaml"
    [ "$status" -eq 0 ]
}

@test "V-AC-1: plugin.sh is executable and runs help router" {
    [ -x "$DR_ORCH_DIR/scripts/plugin.sh" ]
    run bash "$DR_ORCH_DIR/scripts/plugin.sh"
    [ "$status" -eq 2 ]
}

@test "V-AC-13: dispatch on_cycle --dry-run exits 0" {
    run bash "$DR_ORCH_DIR/scripts/plugin.sh" dispatch on_cycle --dry-run
    [ "$status" -eq 0 ]
}

@test "V-AC-13: dispatch on_tune_complete exits 0" {
    run bash "$DR_ORCH_DIR/scripts/plugin.sh" dispatch on_tune_complete
    [ "$status" -eq 0 ]
}

@test "V-AC-15: get_autonomy returns 1" {
    run bash "$DR_ORCH_DIR/scripts/plugin.sh" get_autonomy
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}
