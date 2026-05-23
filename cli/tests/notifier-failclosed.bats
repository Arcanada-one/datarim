#!/usr/bin/env bats
# V-AC-4 / V-AC-25 — notifier fail-closed; ≥1-success contract over pluggable backends.
# Source: TUNE-0271 plan § Detailed Design 4.5.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    NOTIFY_LIB="$CLI_DIR/lib/notify.sh"
    [ -f "$NOTIFY_LIB" ] || skip "notify.sh missing"
}

@test "V-AC-4: zero backends configured → exit 18" {
    run env DATARIM_CLI_NOTIFIER_TARGETS="" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    [ "$status" -eq 18 ]
}

@test "V-AC-4: all backends fail → exit 18 (fail-closed)" {
    run env DATARIM_CLI_NOTIFIER_TARGETS="stub_fail,stub_fail" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    [ "$status" -eq 18 ]
    [[ "$output" == *"0/2 backends acknowledged"* ]]
}

@test "V-AC-25: ≥1 backend acknowledges → exit 0 (pluggable contract)" {
    run env DATARIM_CLI_NOTIFIER_TARGETS="stub_fail,stub" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    [ "$status" -eq 0 ]
}

@test "V-AC-25: single stub backend acknowledges → exit 0" {
    run env DATARIM_CLI_NOTIFIER_TARGETS="stub" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    [ "$status" -eq 0 ]
}

@test "V-AC-4: unknown backend name → counted as failure (no crash)" {
    run env DATARIM_CLI_NOTIFIER_TARGETS="totally_nonexistent_backend" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    [ "$status" -eq 18 ]
    [[ "$output" == *"unknown backend"* ]]
}

@test "V-AC-4: telegram backend missing token/chat → fail (counted, exit 18 if sole backend)" {
    run env DATARIM_CLI_NOTIFIER_TARGETS="telegram" DATARIM_CLI_TG_TOKEN="" DATARIM_CLI_TG_CHAT_ID="" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    [ "$status" -eq 18 ]
    [[ "$output" == *"missing token or chat_id"* ]]
}

@test "V-AC-25: telegram succeeds against stub API (200) → exit 0" {
    # Spawn a tiny mock TG API that returns 200 on POST.
    local mock="$CLI_DIR/tests/fixtures/mock-webhook.py"
    local port
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
    MOCK_MODE=sync_ok MOCK_PORT="$port" python3 "$mock" &
    local pid=$!
    sleep 0.2

    run env DATARIM_CLI_NOTIFIER_TARGETS="telegram" \
        DATARIM_CLI_TG_TOKEN="fake-token" \
        DATARIM_CLI_TG_CHAT_ID="123" \
        DATARIM_CLI_TG_API_BASE="http://127.0.0.1:$port" \
        bash -c ". '$NOTIFY_LIB'; notify_irreversible critical 'test' 'body'"
    kill "$pid" 2>/dev/null || true
    [ "$status" -eq 0 ]
}
