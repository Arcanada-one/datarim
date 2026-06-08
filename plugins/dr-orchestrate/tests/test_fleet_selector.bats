#!/usr/bin/env bats
# test_fleet_selector.bats — fleet interactive backend selection (3b).
# Distinct from inference resolve() (headless --print) — fleet spawns LIVE agents.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    RESOLVER="$PLUGIN_ROOT/scripts/subagent_resolver.sh"
    TMP_BIN="$(mktemp -d)"
    export STATE_DIR="$(mktemp -d)"
    export PATH="$TMP_BIN:$PATH"
}

teardown() {
    rm -rf "$TMP_BIN" "$STATE_DIR"
}

_fake_bin() { printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_BIN/$1"; chmod +x "$TMP_BIN/$1"; }

@test "fleet interactive form for claude has NO --print (live REPL, not headless)" {
    run bash "$RESOLVER" _resolve_fleet_backend claude
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | head -1)" = "claude" ]
    ! echo "$output" | grep -q -- "--print"
}

@test "cursor backend is mapped for fleet" {
    run bash "$RESOLVER" _resolve_fleet_backend cursor
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | head -1)" = "cursor" ]
}

@test "gemini backend is mapped for fleet" {
    run bash "$RESOLVER" _resolve_fleet_backend gemini
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | head -1)" = "gemini" ]
}

@test "generic coworker provider is mapped for fleet bulk-I/O" {
    run bash "$RESOLVER" _resolve_fleet_backend coworker
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | head -1)" = "coworker" ]
}

@test "select_fleet_backend health-checks and skips an absent backend" {
    # Chain: ghost (absent) → claude (present) → picks claude.
    _fake_bin claude
    run env DR_FLEET_BACKEND_CHAIN="ghost claude" bash "$RESOLVER" select_fleet_backend
    [ "$status" -eq 0 ]
    [ "$output" = "claude" ]
}

@test "select_fleet_backend returns failure when whole chain is absent" {
    run env DR_FLEET_BACKEND_CHAIN="ghost1 ghost2" bash "$RESOLVER" select_fleet_backend
    [ "$status" -ne 0 ]
}

@test "CONN wiring is OFF by default (contract-first stub: pure command -v health-check)" {
    _fake_bin claude
    run env -u DR_FLEET_CONN_ENABLED DR_FLEET_BACKEND_CHAIN="claude" bash "$RESOLVER" select_fleet_backend
    [ "$status" -eq 0 ]
    [ "$output" = "claude" ]
    # No CONN dependency invoked — stub path.
    ! echo "$output" | grep -qi "conn"
}

@test "ARAS is a deferred slot — never selected even if a binary named aras exists" {
    _fake_bin aras
    run env DR_FLEET_BACKEND_CHAIN="aras claude" bash "$RESOLVER" _resolve_fleet_backend aras
    [ "$status" -ne 0 ]
}

# --- wish-2: per-role starter skill + allowed-tools injected at session start ---

@test "fleet_role_session_init emits the role's starter_skill and allowed_tools" {
    run bash "$RESOLVER" fleet_role_session_init developer
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^STARTER_SKILL=skills/fleet/l3-analyst$'
    echo "$output" | grep -q '^ALLOWED_TOOLS=Read,Write,Edit,Bash,Grep,Glob$'
}

@test "fleet_role_session_init reads allowed_tools per-role (reviewer differs from developer)" {
    run bash "$RESOLVER" fleet_role_session_init reviewer
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^STARTER_SKILL=skills/fleet/l2-structured$'
    echo "$output" | grep -q '^ALLOWED_TOOLS=Read,Grep,Glob,Bash$'
}

@test "fleet_role_session_init fails closed on an unknown role" {
    run bash "$RESOLVER" fleet_role_session_init no-such-role
    [ "$status" -ne 0 ]
}

@test "fleet_role_session_init rejects a role id that is not a safe slug" {
    run bash "$RESOLVER" fleet_role_session_init '../etc/passwd'
    [ "$status" -ne 0 ]
}
