#!/usr/bin/env bats
# test_plugin_register.bats — V-AC 1, 13, 15

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export DR_ORCH_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export AUDIT_DIR="$BATS_TEST_TMPDIR/audit"
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

@test "V-AC-28: get_autonomy returns 4 for Phase 3" {
    run bash "$DR_ORCH_DIR/scripts/plugin.sh" get_autonomy
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "V-AC-16: dispatch on_unknown_prompt routes to cmd_run.sh" {
    # cmd_run.sh requires bash 4+ — skip on macOS system bash (3.2) hosts.
    [[ "${BASH_VERSINFO[0]}" -ge 4 ]] || skip "bash 4+ required (have $BASH_VERSION)"
    export STATE_DIR="$(mktemp -d)"
    export AUDIT_DIR="$(mktemp -d)"
    export DR_ORCH_SUBAGENT_CHAIN="absent-1 absent-2"
    run bash "$DR_ORCH_DIR/scripts/plugin.sh" dispatch on_unknown_prompt --pane "%9" --unknown-prompt "ambiguous pane text"
    [ "$status" -eq 0 ]
    n=$(find "$AUDIT_DIR" -name 'audit-*.jsonl' -exec cat {} \; | wc -l | tr -d ' ')
    [ "$n" -ge 1 ]
    rm -rf "$STATE_DIR" "$AUDIT_DIR"
}

@test "V-AC-16: dispatch on_unknown_prompt is wired in plugin.sh" {
    # Structural check independent of bash version: the dispatch case exists.
    run grep -E '^[[:space:]]*on_unknown_prompt\)' "$DR_ORCH_DIR/scripts/plugin.sh"
    [ "$status" -eq 0 ]
}

@test "V-AC-28: transport-neutral callback hook is wired to learned lifecycle" {
    run grep -E '^[[:space:]]*on_callback\)' "$DR_ORCH_DIR/scripts/plugin.sh"
    [ "$status" -eq 0 ]
    grep -qF 'learned_rules.sh" consume_callback' "$DR_ORCH_DIR/scripts/plugin.sh"
}
