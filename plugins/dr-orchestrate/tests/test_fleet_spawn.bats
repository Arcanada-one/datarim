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

make_bind_failure_setup() {
    local wrapper="$BATS_TEST_TMPDIR/context-bind-failure.sh"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -eu' \
        'case "${1:-}" in' \
        '  enabled) exit 0 ;;' \
        '  install)' \
        '    mkdir -p "$DR_ORCH_CONTEXT_STATE/instances"' \
        '    printf '\''{"runtime_bound":false}\n'\'' > "$DR_ORCH_CONTEXT_STATE/instances/faultinstance.meta.json"' \
        '    : > "$DR_ORCH_CONTEXT_STATE/fault-overlay"' \
        '    printf '\''instance=faultinstance\nincarnation=faultincarnation\noverlay=%s\n'\'' "$DR_ORCH_CONTEXT_STATE/fault-overlay"' \
        '    ;;' \
        '  bind-process) exit 73 ;;' \
        '  *) exit 2 ;;' \
        'esac' > "$wrapper"
    chmod +x "$wrapper"
    printf '%s\n' "$wrapper"
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

@test "wish-2: spawn with a role injects per-role starter skill + allowed-tools at session start" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    # Third arg = role → spawn pipes the role's starter_skill + allowed_tools
    # into the live pane as the first session-start message.
    session_spawn_interactive "$SESSION" "bash --norc -i" developer
    sleep 1
    run pane_capture_tail "$SESSION" 12
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'STARTER_SKILL=skills/fleet/l3-analyst'
    # Tools are space-separated in the pane injection (the send-keys whitelist
    # forbids commas); the canonical CSV form stays available via
    # fleet_role_session_init for non-pane consumers.
    echo "$output" | grep -q 'ALLOWED_TOOLS=Read Write Edit Bash Grep Glob'
}

@test "TALO-0001: designer spawn injects its exact runtime boundary" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i" designer
    sleep 1
    run pane_capture_tail "$SESSION" 16
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'AGENT=agents/designer.md'
    echo "$output" | grep -q 'DOMAIN_SKILLS=skills/frontend-design'
    echo "$output" | grep -q 'FORBIDDEN_ACTIONS=.*product-code-write'
    echo "$output" | grep -q 'ALLOWED_PATHS=datarim documentation skills agents templates config'
    echo "$output" | grep -q 'PRODUCT_CODE_ACCESS=read-only'
}

@test "TALO-0001: live session reuse replaces the effective role projection" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i" developer
    session_spawn_interactive "$SESSION" "bash --norc -i" designer
    sleep 1
    run pane_capture_tail "$SESSION" 20
    [ "$status" -eq 0 ]
    [ "$(grep -o 'AGENT=[^ ]*' <<<"$output" | tail -1)" = "AGENT=agents/designer.md" ]
    [ "$(grep -o 'PRODUCT_CODE_ACCESS=[^ ]*' <<<"$output" | tail -1)" = "PRODUCT_CODE_ACCESS=read-only" ]
}

@test "TALO-0001: dead session respawn receives the requested role projection" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    tmux send-keys -t "$SESSION" exit Enter
    for _ in $(seq 1 20); do
        [ "$(tmux display-message -p -t "$SESSION" '#{pane_dead}')" = "1" ] && break
        sleep 0.1
    done
    [ "$(tmux display-message -p -t "$SESSION" '#{pane_dead}')" = "1" ]
    session_spawn_interactive "$SESSION" "bash --norc -i" designer
    sleep 1
    run pane_capture_tail "$SESSION" 16
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'AGENT=agents/designer.md'
    echo "$output" | grep -q 'PRODUCT_CODE_ACCESS=read-only'
}

@test "TALO-0001: failed live role rebind returns nonzero and preserves prior scope" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i" designer
    run session_spawn_interactive "$SESSION" "bash --norc -i" no-such-role
    [ "$status" -ne 0 ]
    tmux has-session -t "$SESSION"
    run pane_capture_tail "$SESSION" 16
    [ "$(grep -o 'AGENT=[^ ]*' <<<"$output" | tail -1)" = "AGENT=agents/designer.md" ]
}

@test "TALO-0001: failed initial role injection removes the unscoped session" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    run session_spawn_interactive "$SESSION" "bash --norc -i" no-such-role
    [ "$status" -ne 0 ]
    ! tmux has-session -t "$SESSION" 2>/dev/null
}

@test "TALO-0001: failed dead respawn role injection restores a dead session" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    tmux send-keys -t "$SESSION" exit Enter
    for _ in $(seq 1 20); do
        [ "$(tmux display-message -p -t "$SESSION" '#{pane_dead}')" = "1" ] && break
        sleep 0.1
    done
    run session_spawn_interactive "$SESSION" "bash --norc -i" no-such-role
    [ "$status" -ne 0 ]
    tmux has-session -t "$SESSION"
    [ "$(tmux display-message -p -t "$SESSION" '#{pane_dead}')" = "1" ]
}

@test "TALO-0001: context bind-process fault returns nonzero and removes the session" {
    export DR_ORCH_CONTEXT_SETUP="$(make_bind_failure_setup)"
    export DR_ORCH_CONTEXT_STATE="$BATS_TEST_TMPDIR/context-state"
    export DR_ORCH_RUNTIME=codex
    export DR_ORCH_ACTIVE_TASK=TALO-0001
    export DR_ORCH_WORKSPACE="$PWD"
    source "${TMUX_MANAGER_UNDER_TEST:-$DR_ORCH_DIR/scripts/tmux_manager.sh}"

    run session_spawn_interactive "$SESSION" "bash --norc -i"
    [ "$status" -ne 0 ] || return 1
    ! tmux has-session -t "$SESSION" 2>/dev/null || return 1
}

@test "TALO-0001: context bind guard remove and invert mutants are RED" {
    local original="$DR_ORCH_DIR/scripts/tmux_manager.sh"
    local behavior='^TALO-0001: context bind-process fault returns nonzero and removes the session$'
    local variant mutant
    for variant in remove invert; do
        mutant="$BATS_TEST_TMPDIR/tmux-manager-$variant.sh"
        cp "$original" "$mutant"
        python3 - "$mutant" "$variant" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
variant = sys.argv[2]
text = path.read_text(encoding="utf-8")
guard = '''  if ! _context_window_setup bind-process "$instance" "$incarnation" "$birth"; then
    tmux kill-session -t "$session" 2>/dev/null || true
    return 1
  fi'''
if guard not in text:
    raise SystemExit("context bind guard mutation target not found")
if variant == "remove":
    replacement = '  _context_window_setup bind-process "$instance" "$incarnation" "$birth"'
else:
    replacement = guard.replace("if ! _context_window_setup", "if _context_window_setup", 1)
path.write_text(text.replace(guard, replacement, 1), encoding="utf-8")
PY
        run env TMUX_MANAGER_UNDER_TEST="$mutant" bats -f "$behavior" "$BATS_TEST_FILENAME"
        [ "$status" -eq 1 ] || return 1
        [[ "$output" == *"not ok 1 TALO-0001: context bind-process fault returns nonzero and removes the session"* ]] || return 1
    done
}

@test "wish-2: spawn without a role omits the injection (backward-compatible)" {
    source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
    session_spawn_interactive "$SESSION" "bash --norc -i"
    sleep 1
    run pane_capture_tail "$SESSION" 12
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q 'ALLOWED_TOOLS='
}
