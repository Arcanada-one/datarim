#!/usr/bin/env bats
# tests/test-fleet-evolution-jsonl.bats — JSONL helpers for fleet skill-evolution.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LIB="$REPO/plugins/dr-fleet-evolution/lib/jsonl.sh"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — JSONL helpers require jq"
    fi
    # shellcheck source=/dev/null
    source "$LIB"
}

@test "lib/jsonl.sh exists" {
    [ -f "$LIB" ]
}

@test "jsonl_emit_record produces a one-line valid JSON object" {
    run jsonl_emit_record "do X" "result Y" "result Z" "success" "archive"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.task_input=="do X" and .outcome=="success" and .source=="archive"'
}

@test "jsonl_emit_record escapes quotes and newlines in content" {
    run jsonl_emit_record 'a "quoted" task' "line1
line2" "" "failure" "dr-dream"
    [ "$status" -eq 0 ]
    # Output is still a single line (newline inside content is escaped).
    [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
    echo "$output" | jq -e '.expected_output | contains("line1") and contains("line2")'
}

@test "jsonl_validate accepts a well-formed dataset" {
    {
        jsonl_emit_record "t1" "e1" "a1" "success" "archive"
        jsonl_emit_record "t2" "e2" "a2" "failure" "dr-dream"
    } > "$TMP/ok.jsonl"
    run jsonl_validate "$TMP/ok.jsonl"
    [ "$status" -eq 0 ]
}

@test "jsonl_validate accepts an empty dataset (empty source is not an error)" {
    : > "$TMP/empty.jsonl"
    run jsonl_validate "$TMP/empty.jsonl"
    [ "$status" -eq 0 ]
}

@test "jsonl_validate rejects a line missing a required field" {
    printf '%s\n' '{"task_input":"t","expected_output":"e","actual_output":"a","outcome":"success"}' > "$TMP/bad.jsonl"
    run jsonl_validate "$TMP/bad.jsonl"
    [ "$status" -eq 1 ]
}

@test "jsonl_validate rejects an invalid outcome value" {
    printf '%s\n' '{"task_input":"t","expected_output":"e","actual_output":"a","outcome":"maybe","source":"x"}' > "$TMP/bad.jsonl"
    run jsonl_validate "$TMP/bad.jsonl"
    [ "$status" -eq 1 ]
}

@test "jsonl_validate rejects a non-object line" {
    printf '%s\n' '"just a string"' > "$TMP/bad.jsonl"
    run jsonl_validate "$TMP/bad.jsonl"
    [ "$status" -eq 1 ]
}

@test "jsonl_merge dedups by (task_input, source)" {
    {
        jsonl_emit_record "dup" "e1" "a1" "success" "archive"
        jsonl_emit_record "dup" "e2" "a2" "failure" "archive"
        jsonl_emit_record "dup" "e3" "a3" "success" "dr-dream"
    } > "$TMP/in.jsonl"
    run jsonl_merge "$TMP/in.jsonl"
    [ "$status" -eq 0 ]
    # 2 unique (task_input,source) pairs: (dup,archive) and (dup,dr-dream).
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}
