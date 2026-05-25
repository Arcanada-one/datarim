#!/usr/bin/env bats
#
# TUNE-0264 — Programmatic hook-enforce Stage Header preamble + human-summary
# contract validator. Integration tests for dev-tools/hooks/dr-output-stop.{sh,py}.
#
# Fixture transcripts live in tests/fixtures/dr-output/*.jsonl. Paths are
# resolved via $HOME/.claude/tests/fixtures/... (symlinked from framework repo)
# so the hook's home-relative path validation accepts them.

HOOK="${BATS_TEST_DIRNAME}/../dev-tools/hooks/dr-output-stop.sh"
FIXDIR_REAL="${BATS_TEST_DIRNAME}/fixtures/dr-output"
FIXDIR_HOME="${HOME}/.claude/tests/fixtures/dr-output"

# Returns home-relative fixture path; falls back to real path when symlink absent.
_fix() {
    local name="$1"
    if [ -f "${FIXDIR_HOME}/${name}" ]; then
        printf '%s\n' "${FIXDIR_HOME}/${name}"
    else
        printf '%s\n' "${FIXDIR_REAL}/${name}"
    fi
}

_invoke() {
    local fixture="$1"
    local stop_active="${2:-false}"
    local path
    path="$(_fix "$fixture")"
    printf '{"session_id":"test","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":%s}\n' "$path" "$stop_active" | bash "$HOOK"
}

@test "hook script is executable" {
    [ -x "$HOOK" ]
}

@test "Python self-test passes" {
    run python3 "${BATS_TEST_DIRNAME}/../dev-tools/hooks/dr-output-stop.py" --self-test
    [ "$status" -eq 0 ]
}

@test "stage-header: valid header allows" {
    run _invoke "header-valid.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stage-header: missing header blocks on first occurrence" {
    run _invoke "header-missing.jsonl" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]] || [[ "$output" == *'"decision":"block"'* ]]
    [[ "$output" == *"Stage Header missing"* ]]
}

@test "stage-header: missing header advisory on retry (stop_hook_active=true)" {
    run _invoke "header-missing.jsonl" "true"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision"'* ]]
}

@test "stage-header: /dr-help exception is skipped" {
    run _invoke "exception-help.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stage-header: /dr-init pre-Step4 (no TASK-ID in response) is skipped" {
    run _invoke "init-pre-step4.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "transcript: corrupt JSONL falls through to last parseable assistant" {
    run _invoke "corrupt.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "no /dr-* command in user message: hook stays silent" {
    run _invoke "no-dr-cmd.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "human-summary: valid 4-heading + preamble allows" {
    run _invoke "human-summary-valid.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "human-summary: missing one of 4 subheadings blocks" {
    run _invoke "human-summary-missing-heading.jsonl" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision"'*'"block"'* ]] || [[ "$output" == *'"decision":"block"'* ]]
    [[ "$output" == *"missing_subheading_2"* ]]
}

@test "human-summary: wrong order detected" {
    run _invoke "human-summary-wrong-order.jsonl" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"wrong_order"* ]]
}

@test "human-summary: missing self-identifier preamble blocks" {
    run _invoke "human-summary-no-preamble.jsonl" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing_preamble"* ]]
}

@test "human-summary: fifth subheading inside Operator summary blocks" {
    run _invoke "human-summary-fifth-heading.jsonl" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fifth_subheading"* ]]
}

@test "human-summary: /dr-do skipped — validator #2 inactive outside HUMAN_SUMMARY_TRIGGERS" {
    run _invoke "human-summary-dr-do-skipped.jsonl"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "human-summary: missing Operator summary section blocks for /dr-archive" {
    run _invoke "human-summary-missing-section.jsonl" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing_section"* ]]
}

@test "transcript path traversal (../../etc/passwd) is rejected fail-soft" {
    run bash -c 'printf "{\"session_id\":\"t\",\"transcript_path\":\"$HOME/.claude/../../etc/passwd\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}\n" | bash "'"$HOOK"'"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "transcript path outside ~/.claude is rejected fail-soft" {
    run bash -c 'printf "{\"session_id\":\"t\",\"transcript_path\":\"/tmp/not-claude.jsonl\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}\n" | bash "'"$HOOK"'"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
