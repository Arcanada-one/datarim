#!/usr/bin/env bats
# Phase 4 V-AC-21 — datarim tmux read.

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
    MOCK_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    export DATARIM_CLI_WEBHOOK_URL="http://127.0.0.1:$MOCK_PORT"
    MOCK_MODE="$mode" MOCK_PORT="$MOCK_PORT" python3 "$MOCK" &
    MOCK_PID=$!
    for _ in $(seq 1 50); do
        curl -s --max-time 0.2 "http://127.0.0.1:$MOCK_PORT/" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
}

@test "tmux read with default --lines 50 → 50 lines printed" {
    _start_mock tmux_read_50lines
    run "$DATARIM_BIN" tmux read %0
    [ "$status" -eq 0 ]
    line_count=$(printf '%s' "$output" | grep -c '^L[0-9]' || true)
    [ "$line_count" -eq 50 ]
}

@test "tmux read --lines 10 accepts custom value" {
    _start_mock tmux_read_50lines
    run "$DATARIM_BIN" tmux read %0 --lines 10
    [ "$status" -eq 0 ]
}

@test "V-AC-21: tmux read with malformed pane id → exit 31 NOT_FOUND" {
    run "$DATARIM_BIN" tmux read foo
    [ "$status" -eq 31 ]
}

@test "tmux read --lines >1000 → exit 32 INVALID_COMMAND" {
    run "$DATARIM_BIN" tmux read %0 --lines 1001
    [ "$status" -eq 32 ]
}

@test "tmux read --lines non-integer → exit 32 INVALID_COMMAND" {
    run "$DATARIM_BIN" tmux read %0 --lines abc
    [ "$status" -eq 32 ]
}
