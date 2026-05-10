#!/usr/bin/env bats
# test_tmux_manager.bats — V-AC 2, 3, 4, 5

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export STATE_DIR="$(mktemp -d)"
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux not installed"
    fi
    SESSION="batstest-$$-$RANDOM"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
}

teardown() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -rf "$STATE_DIR"
}

@test "V-AC-2: session_init creates session idempotently" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_init "$SESSION"
    tmux has-session -t "$SESSION"
    session_init "$SESSION"
    tmux has-session -t "$SESSION"
}

@test "V-AC-3: pane_split adds a pane" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_init "$SESSION"
    pane_split "$SESSION"
    [ "$(tmux list-panes -t "$SESSION" | wc -l | tr -d ' ')" -ge 2 ]
}

@test "V-AC-4: pane_kill removes a pane" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_init "$SESSION"
    pane_split "$SESSION"
    target=$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | tail -1)
    pane_kill "$target"
    [ "$(tmux list-panes -t "$SESSION" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "V-AC-5: send-keys via security pipeline reaches pane" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_init "$SESSION"
    target=$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -1)
    run pane_send "$target" "echo orchestrate-marker"
    [ "$status" -eq 0 ]
    sleep 0.3
    run tmux capture-pane -p -t "$target"
    echo "$output" | grep -q 'orchestrate-marker'
}

@test "V-AC-5: pane_send rejects whitelist-violating text" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_init "$SESSION"
    target=$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -1)
    run pane_send "$target" 'rm -rf /; cat /etc/passwd'
    [ "$status" -eq 1 ]
}
