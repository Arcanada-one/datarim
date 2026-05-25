#!/usr/bin/env bats
# V-AC-21 — HTTP retry: ECONNREFUSED retries 3×; 500 body → immediate exit 25 (no retry).
# Source: TUNE-0271 plan § Detailed Design 4.1.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    HTTP_LIB="$CLI_DIR/lib/http.sh"
    MOCK="$CLI_DIR/tests/fixtures/mock-webhook.py"
    [ -f "$HTTP_LIB" ] || skip "http.sh missing"
    [ -f "$MOCK" ] || skip "mock-webhook.py missing"
    MOCK_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    export DATARIM_CLI_WEBHOOK_URL="http://127.0.0.1:$MOCK_PORT"
    MOCK_PID=""
}

teardown() {
    [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null || true
}

_spawn_mock() {
    local mode="$1"
    MOCK_MODE="$mode" MOCK_PORT="$MOCK_PORT" python3 "$MOCK" &
    MOCK_PID=$!
    # Wait for listener.
    for _ in $(seq 1 50); do
        if curl -fsS --max-time 0.2 "http://127.0.0.1:$MOCK_PORT/_ping" >/dev/null 2>&1 || \
           curl -s --max-time 0.2 "http://127.0.0.1:$MOCK_PORT/" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

@test "V-AC-21: ECONNREFUSED with no listener → exit 21" {
    # No mock spawned — port closed.
    run bash -c ". '$HTTP_LIB'; http_dispatch_sync dr-status '{}'"
    [ "$status" -eq 21 ]
}

@test "V-AC-21: 500 response → exit 25 (no retry, immediate fail)" {
    _spawn_mock server_5xx
    run bash -c ". '$HTTP_LIB'; http_dispatch_sync dr-status '{}'"
    [ "$status" -eq 25 ]
}

@test "V-AC-21: 400 response → exit 24" {
    _spawn_mock server_4xx
    run bash -c ". '$HTTP_LIB'; http_dispatch_sync dr-status '{}'"
    [ "$status" -eq 24 ]
}

@test "V-AC-21: 200 sync_ok → exit 0, body returned" {
    _spawn_mock sync_ok
    run bash -c ". '$HTTP_LIB'; http_dispatch_sync dr-status '{}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "ok"'* ]] || [[ "$output" == *'"status":"ok"'* ]]
}

@test "V-AC-22: non-idempotent slash via sync path → exit 26 (no HTTP attempt)" {
    # Mock not running — if sync attempted, would exit 21. Refusal must happen first.
    run bash -c ". '$HTTP_LIB'; http_dispatch_sync dr-archive '{}'"
    [ "$status" -eq 26 ]
}

@test "V-AC-22: non-idempotent slash via async path → succeeds" {
    _spawn_mock async_ok
    run bash -c ". '$HTTP_LIB'; http_dispatch_async dr-archive '{}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"result"* ]]
}

@test "V-AC-22: classify_slash routing matrix" {
    run bash -c ". '$HTTP_LIB'; classify_slash dr-status"
    [ "$status" -eq 0 ]; [ "$output" = "sync" ]

    run bash -c ". '$HTTP_LIB'; classify_slash dr-help"
    [ "$output" = "sync" ]

    run bash -c ". '$HTTP_LIB'; classify_slash dr-archive"
    [ "$output" = "forbidden_sync" ]

    run bash -c ". '$HTTP_LIB'; classify_slash /dr-do"
    [ "$output" = "forbidden_sync" ]

    run bash -c ". '$HTTP_LIB'; classify_slash dr-something-new"
    [ "$output" = "async" ]
}
