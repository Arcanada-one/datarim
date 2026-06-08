#!/usr/bin/env bats
# test_fleet_spawn.bats — interactive tmux spawn for fleet agents (3a).

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export STATE_DIR="$(mktemp -d)"
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux not installed"
    fi
    SESSION="fleetspawn-$$-$RANDOM"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
}

teardown() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -rf "$STATE_DIR"
}

@test "V-AC-2: session_spawn_interactive launches a live interactive shell (no --print)" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    # Launch an interactive shell as the 'agent' stand-in (a real REPL).
    session_spawn_interactive "$SESSION" "bash --norc -i"
    tmux has-session -t "$SESSION"
    # The pane runs a live shell, not a one-shot exited command.
    run tmux list-panes -t "$SESSION" -F '#{pane_dead}'
    [ "$output" = "0" ]
}

@test "V-AC-2: send brief then targeted-capture reads the agent response suffix" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    pane_send "$SESSION" "echo FLEET_MARKER_OK"
    sleep 1
    run pane_capture_tail "$SESSION" 5
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "FLEET_MARKER_OK"
    # targeted capture returns a bounded suffix, not the whole scrollback
    [ "$(echo "$output" | wc -l | tr -d ' ')" -le 6 ]
}

@test "V-AC-11: pane_idle_check reports idle when buffer is unchanged past timeout" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    sleep 1
    # Idle window 1s, deadline 10s — an idle prompt should report idle (rc 0).
    run pane_idle_check "$SESSION" 1 10
    [ "$status" -eq 0 ]
}

@test "V-AC-11: pane_idle_check reports NOT-idle while output is actively changing" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    # Start a slow but LIVE producer — must NOT be misjudged as hung. Driven via
    # raw tmux (not pane_send) — the loop syntax is intentionally outside the
    # agent-input whitelist; this is a test fixture, not untrusted agent input.
    tmux send-keys -t "$SESSION" 'while true; do date +%s%N; sleep 0.2; done' Enter
    sleep 1
    run pane_idle_check "$SESSION" 1 3
    # Active producer within the idle window → not-idle (non-zero rc).
    [ "$status" -ne 0 ]
}

@test "session_close removes the fleet session" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    session_close "$SESSION"
    ! tmux has-session -t "$SESSION" 2>/dev/null
}
