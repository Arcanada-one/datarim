#!/usr/bin/env bats
# Phase 4 V-AC-19, V-AC-24 — datarim tmux new (whitelist enforcement, async timeout).

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
    # Notifier stub: targets=stub, results=ack — so notifier_gate passes.
    export DATARIM_CLI_NOTIFIER_TARGETS=stub
    export DATARIM_CLI_NOTIFY_STUB_RESULT=0
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

@test "tmux new with valid cmd → 202 + poll success → exit 0" {
    _start_mock tmux_new_202
    run "$DATARIM_BIN" tmux new --task TUNE-9999 --cmd "claude -p"
    [ "$status" -eq 0 ]
    [[ "$output" == *"%1"* ]] || [[ "$output" == *"claude -p"* ]]
}

@test "V-AC-19: tmux new with disallowed --cmd → exit 32 INVALID_COMMAND" {
    run "$DATARIM_BIN" tmux new --task TUNE-9999 --cmd "rm -rf /"
    [ "$status" -eq 32 ]
}

@test "tmux new without --task → exit 32 INVALID_COMMAND" {
    run "$DATARIM_BIN" tmux new --cmd "claude -p"
    [ "$status" -eq 32 ]
}

@test "V-AC-24: tmux new async timeout (polling ceiling exceeded) → exit 27 ASYNC_TIMEOUT" {
    _start_mock tmux_new_async_never
    # Force ceiling to 1s + poll interval 1s so timeout fires fast.
    export DATARIM_CLI_ASYNC_TIMEOUT=1
    export DATARIM_CLI_TMUX_POLL_INTERVAL=1
    run "$DATARIM_BIN" tmux new --task TUNE-9999 --cmd "claude -p"
    [ "$status" -eq 27 ]
}

@test "tmux new without notifier configured → exit 19 TMUX_NOTIFIER_OFF" {
    unset DATARIM_CLI_NOTIFIER_TARGETS
    run "$DATARIM_BIN" tmux new --task TUNE-9999 --cmd "claude -p"
    [ "$status" -eq 19 ]
}
