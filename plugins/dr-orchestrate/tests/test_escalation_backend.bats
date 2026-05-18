#!/usr/bin/env bats
# test_escalation_backend.bats — TUNE-0165 M3.
# Verifies mock|dev-bot dispatch, JSONL schema, env-var switch, redaction
# passthrough, and unknown-backend error.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    TMP="$(mktemp -d)"
    export DR_ORCH_ESCALATION_MOCK_LOG="$TMP/escalation.jsonl"
    export DR_ORCH_PROMPT_TEXT="sample pane text"
}

teardown() {
    rm -rf "$TMP"
}

_resolver_json() {
    printf '%s' '{"action":"/dr-do","confidence":0.42,"reason":"weak","backend_used":"coworker-deepseek","subagent_model":"deepseek-chat"}'
}

@test "M3: mock writer appends a JSONL line with frozen schema fields" {
    run bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$(_resolver_json)" "%5"
    [ "$status" -eq 0 ]
    [ -s "$DR_ORCH_ESCALATION_MOCK_LOG" ]
    # exactly one line
    n="$(wc -l < "$DR_ORCH_ESCALATION_MOCK_LOG" | tr -d ' ')"
    [ "$n" -eq 1 ]
    # required fields
    run jq -e '.schema_version == 2 and .mock == true and .escalation_backend == "mock"' "$DR_ORCH_ESCALATION_MOCK_LOG"
    [ "$status" -eq 0 ]
}

@test "M3: mock writer hashes prompt and carries action/confidence/backend_used" {
    run bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$(_resolver_json)" "%5"
    [ "$status" -eq 0 ]
    run jq -e '.action_suggested == "/dr-do" and .confidence == 0.42 and .backend_used == "coworker-deepseek" and (.prompt_hash | length) == 64' "$DR_ORCH_ESCALATION_MOCK_LOG"
    [ "$status" -eq 0 ]
}

@test "M3: env-var DR_ORCH_ESCALATION_BACKEND=dev-bot exits 0 (no-op when URL unset)" {
    # _emit_devbot is now a gated no-op: exits 0 silently when
    # DR_ORCH_ESCALATION_DEVBOT_URL is unset (V-AC-7). The old stub (exit 99)
    # is replaced by the real implementation.
    DR_ORCH_ESCALATION_BACKEND=dev-bot \
      run bash -c "unset DR_ORCH_ESCALATION_DEVBOT_URL; DR_ORCH_ESCALATION_BACKEND=dev-bot bash '$DR_ORCH_DIR/scripts/escalation_backend.sh' emit '$(_resolver_json)' '%5'"
    [ "$status" -eq 0 ]
}

@test "M3: unknown backend returns exit 2" {
    run bash -c "DR_ORCH_ESCALATION_BACKEND=nonsense bash '$DR_ORCH_DIR/scripts/escalation_backend.sh' emit '$(_resolver_json)' '%5'"
    [ "$status" -eq 2 ]
}

@test "M3: reason field is grep-redacted for secret keywords" {
    leaky='{"action":"/dr-do","confidence":0.30,"reason":"failed because password=hunter2 token=abc","backend_used":"coworker-deepseek","subagent_model":"deepseek-chat"}'
    run bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$leaky" "%5"
    [ "$status" -eq 0 ]
    run grep -E '(password=hunter2|token=abc)' "$DR_ORCH_ESCALATION_MOCK_LOG"
    [ "$status" -ne 0 ]
    run grep -E '(REDACTED|<redacted>)' "$DR_ORCH_ESCALATION_MOCK_LOG"
    [ "$status" -eq 0 ]
}

@test "M3: cycle_id is non-empty per event" {
    bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$(_resolver_json)" "%5"
    bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$(_resolver_json)" "%6"
    run jq -e '.cycle_id | length > 0' "$DR_ORCH_ESCALATION_MOCK_LOG"
    [ "$status" -eq 0 ]
    # both lines must have distinct cycle_id
    n_unique="$(jq -r '.cycle_id' "$DR_ORCH_ESCALATION_MOCK_LOG" | sort -u | wc -l | tr -d ' ')"
    [ "$n_unique" -eq 2 ]
}
