#!/usr/bin/env bats
# Phase 4 V-AC-9, V-AC-23 — datarim tmux ls.
# Source: TUNE-0268 Phase 4 plan § Test Plan.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DATARIM_BIN="$CLI_DIR/datarim"
    MOCK="$CLI_DIR/tests/fixtures/mock-webhook.py"
    UUID_GEN="$CLI_DIR/lib/uuid7-gen.sh"
    [ -x "$DATARIM_BIN" ] || skip "datarim binary missing"

    TMP_DIR="$(mktemp -d)"
    export DATARIM_CLI_AUDIT_DIR="$TMP_DIR/audit"
    export DATARIM_CLI_HALT_PATH="$TMP_DIR/HALT"
    export DATARIM_CLI_AGENT_ID="$("$UUID_GEN")"
}

teardown() {
    [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null || true
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" || true
}

_start_mock() {
    local mode="$1"
    # TUNE-0295 V-AC-5 dual-mode toggle: when real dispatcher is active, skip
    # mock spawn (caller runs dr_orchestrate_server.sh externally; fixture-
    # bound assertions skip via mode != caller-controlled).
    if [ "${DATARIM_CLI_USE_REAL_DISPATCHER:-}" = "1" ]; then
        [ -n "${DATARIM_CLI_WEBHOOK_URL:-}" ] || skip "real-dispatcher mode requires DATARIM_CLI_WEBHOOK_URL"
        skip "real-dispatcher mode: fixture-bound assertion not portable on live tmux state — wish_id phase4-cli-bats-not-regressed § V-AC-5 deferred to Phase G PROD smoke runbook"
    fi
    MOCK_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    export DATARIM_CLI_WEBHOOK_URL="http://127.0.0.1:$MOCK_PORT"
    MOCK_MODE="$mode" MOCK_PORT="$MOCK_PORT" python3 "$MOCK" &
    MOCK_PID=$!
    for _ in $(seq 1 50); do
        curl -s --max-time 0.2 "http://127.0.0.1:$MOCK_PORT/" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
}

@test "V-AC-9: tmux ls plain output enumerates 3 panes from fixture" {
    _start_mock tmux_list_3pane
    run "$DATARIM_BIN" tmux ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"%0"* ]]
    [[ "$output" == *"%1"* ]]
    [[ "$output" == *"%2"* ]]
}

@test "V-AC-23: tmux ls --json envelope contains version/command/ts/data/error" {
    _start_mock tmux_list_3pane
    run "$DATARIM_BIN" tmux ls --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert set(['version','command','ts','data','error']).issubset(d.keys()); assert d['command']=='tmux'"
}

@test "tmux ls empty list — plain output prints (no panes)" {
    _start_mock tmux_list_empty
    run "$DATARIM_BIN" tmux ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"no panes"* ]]
}

@test "tmux ls webhook unreachable → exit 21 HTTP_CONNECT_FAIL" {
    # Point at unused loopback port.
    export DATARIM_CLI_WEBHOOK_URL="http://127.0.0.1:1"
    run "$DATARIM_BIN" tmux ls
    [ "$status" -eq 21 ]
}

@test "V-AC-27: tmux ls with HALT sentinel → exit 17 (kill-switch first)" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" tmux ls
    [ "$status" -eq 17 ]
}
