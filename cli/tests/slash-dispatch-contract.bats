#!/usr/bin/env bats
# V-AC-8 — `datarim run /dr-status` ≡ direct webhook POST.
# Source: TUNE-0271 plan § Implementation Steps Batch 3.

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

    MOCK_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    export DATARIM_CLI_WEBHOOK_URL="http://127.0.0.1:$MOCK_PORT"
    MOCK_MODE=sync_ok MOCK_PORT="$MOCK_PORT" python3 "$MOCK" &
    MOCK_PID=$!
    for _ in $(seq 1 50); do
        curl -s --max-time 0.2 "http://127.0.0.1:$MOCK_PORT/" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
}

teardown() {
    [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null || true
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" || true
}

@test "V-AC-8: datarim run /dr-status returns mock response + writes audit line" {
    run "$DATARIM_BIN" run /dr-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
    # Audit line written.
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    [ -f "$today_file" ]
    line_count=$(wc -l < "$today_file" | tr -d ' ')
    [ "$line_count" -eq 1 ]
}

@test "V-AC-8: datarim run with no slash-cmd → exit 2" {
    run "$DATARIM_BIN" run
    [ "$status" -eq 2 ]
}

@test "V-AC-8: datarim run /dr-archive routes async (non-idempotent), not exit 26" {
    # Restart mock in async mode for this single test.
    kill "$MOCK_PID" 2>/dev/null || true
    MOCK_MODE=async_ok MOCK_PORT="$MOCK_PORT" python3 "$CLI_DIR/tests/fixtures/mock-webhook.py" &
    MOCK_PID=$!
    sleep 0.2
    run "$DATARIM_BIN" run /dr-archive TUNE-0271
    [ "$status" -eq 0 ]
}
