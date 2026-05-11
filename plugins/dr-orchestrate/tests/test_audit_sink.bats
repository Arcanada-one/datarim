#!/usr/bin/env bats
# test_audit_sink.bats — V-AC 10, 11, 12

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export TMP_AUDIT_DIR="$(mktemp -d)"
    AUDIT_FILE="$TMP_AUDIT_DIR/audit.jsonl"
}

teardown() {
    rm -rf "$TMP_AUDIT_DIR"
}

@test "V-AC-10: emit appends a JSONL line" {
    bash "$DR_ORCH_DIR/scripts/audit_sink.sh" emit "$AUDIT_FILE" '{"x":1}'
    [ -s "$AUDIT_FILE" ]
    run wc -l "$AUDIT_FILE"
    [ "$(echo "$output" | awk '{print $1}')" -eq 1 ]
}

@test "V-AC-11: make_event carries all 6 required fields" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event "sample text" "/dr-plan" 0 12 "%2.1")
    echo "$event" \
      | jq -e 'has("timestamp") and has("matched_text_hash") and has("command") and has("exit_code") and has("duration_ms") and has("pane_id")'
}

@test "V-AC-12: make_event never carries raw credential keys" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event "secret-text" "/dr-plan" 0 12 "%2.1")
    run bash -c "echo '$event' | jq -e 'has(\"password\") or has(\"token\") or has(\"secret\")'"
    [ "$status" -ne 0 ]
}

@test "V-AC-12: matched_text_hash is sha256 hex (64 chars)" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event "abc" "/dr-plan" 0 1 "%0.0")
    h=$(echo "$event" | jq -r '.matched_text_hash')
    [ "${#h}" -eq 64 ]
}

@test "V-AC-10: opsbot_emit is a Phase-3+ stub" {
    run bash "$DR_ORCH_DIR/scripts/audit_sink.sh" opsbot_emit any
    [ "$status" -eq 99 ]
}

@test "V-AC-18: make_event_v2 declares schema_version 2 and carries new fields" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event_v2 \
      "some text" "/dr-plan" 0 12 "%2.1" \
      0.87 "deepseek-chat" "coworker-deepseek" "" "resolve" "matched" "ok")
    echo "$event" | jq -e \
      '.schema_version == 2
       and has("confidence") and has("subagent_model")
       and has("backend_used") and has("escalation_backend")
       and has("stage") and has("outcome")'
}

@test "V-AC-18: make_event_v2 keeps matched_text hashed (V-AC-12 preserved)" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event_v2 \
      "secret-text" "/dr-do" 0 1 "%0.0" \
      0.0 "" "" "" "parse" "miss" "")
    h=$(echo "$event" | jq -r .matched_text_hash)
    [ "${#h}" -eq 64 ]
    # raw text must not appear
    run bash -c "echo '$event' | grep -F 'secret-text'"
    [ "$status" -ne 0 ]
}

@test "M5: redact_reason strips password=, token=, api_key=" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event_v2 \
      "x" "/dr-do" 0 1 "%0.0" \
      0.3 "" "" "" "resolve" "escalated" \
      "failed because password=hunter2 token=abc api-key=zzz")
    echo "$event" | jq -r .reason | tee /tmp/reason.out >/dev/null
    run grep -E '(hunter2|abc|zzz)' /tmp/reason.out
    [ "$status" -ne 0 ]
    run grep -F '<REDACTED>' /tmp/reason.out
    [ "$status" -eq 0 ]
    rm -f /tmp/reason.out
}

@test "M5: make_event (v1) remains backward-compatible (no schema_version)" {
    event=$(bash "$DR_ORCH_DIR/scripts/audit_sink.sh" make_event "x" "/dr-init" 0 1 "%0.0")
    run bash -c "echo '$event' | jq -e 'has(\"schema_version\")'"
    [ "$status" -ne 0 ]
}
