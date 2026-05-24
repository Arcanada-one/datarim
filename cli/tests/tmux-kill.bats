#!/usr/bin/env bats
# Phase 4 V-AC-10, V-AC-20, V-AC-25 — datarim tmux kill (irreversible, hard-gated).

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
        skip "real-dispatcher mode: fixture-bound assertion not portable (Phase G PROD smoke covers)"
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

@test "V-AC-25: tmux kill with notifier ack → exit 0 + audit entry written" {
    export DATARIM_CLI_NOTIFIER_TARGETS=stub
    export DATARIM_CLI_NOTIFY_STUB_RESULT=0
    _start_mock tmux_kill_200
    run "$DATARIM_BIN" tmux kill %0
    [ "$status" -eq 0 ]
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    [ -f "$today_file" ]
    grep -q '"subcommand":"tmux kill"' "$today_file"
    grep -q '"outcome":"success"' "$today_file"
}

@test "V-AC-10: tmux kill without notifier configured → exit 19 TMUX_NOTIFIER_OFF" {
    run "$DATARIM_BIN" tmux kill %0
    [ "$status" -eq 19 ]
}

@test "tmux kill with notifier delivery fail-soft → exit 18 NOTIFIER_DOWN" {
    export DATARIM_CLI_NOTIFIER_TARGETS=stub_fail
    run "$DATARIM_BIN" tmux kill %0
    [ "$status" -eq 18 ]
}

@test "V-AC-20: tmux kill with HALT sentinel → exit 17 (HALT absolute, before notifier gate)" {
    export DATARIM_CLI_NOTIFIER_TARGETS=stub
    export DATARIM_CLI_NOTIFY_STUB_RESULT=0
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" tmux kill %0
    [ "$status" -eq 17 ]
}

@test "V-AC-20: tmux kill --force does NOT bypass notifier requirement" {
    # Notifier unset → --force still hits exit 19.
    run "$DATARIM_BIN" tmux kill %0 --force
    [ "$status" -eq 19 ]
}

@test "tmux kill --force + HALT still exit 17 (HALT > --force)" {
    export DATARIM_CLI_NOTIFIER_TARGETS=stub
    export DATARIM_CLI_NOTIFY_STUB_RESULT=0
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" tmux kill %0 --force
    [ "$status" -eq 17 ]
}

@test "tmux kill --json on success → envelope with data" {
    export DATARIM_CLI_NOTIFIER_TARGETS=stub
    export DATARIM_CLI_NOTIFY_STUB_RESULT=0
    _start_mock tmux_kill_200
    run "$DATARIM_BIN" tmux kill %0 --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"killed"* ]] || [[ "$output" == *"data"* ]]
}
