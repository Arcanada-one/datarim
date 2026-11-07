#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/check-qa-run-fail-lines.py"
    RUN="$BATS_TEST_TMPDIR/run"
    MANIFEST="$BATS_TEST_TMPDIR/manifest.json"
    mkdir -p "$RUN"
}

write_fail_line() {
    printf 'FAIL: synthetic assertion marker\n' > "$RUN/results.log"
}

run_summary() {
    run --separate-stderr python3 "$SCRIPT" \
        --run-dir "$RUN" --manifest "$MANIFEST" --summary-json
}

assert_summary() {
    python3 - "$status" "$output" "$stderr" "$1" "$2" "$3" <<'PY'
import json
import sys

status, stdout, stderr = int(sys.argv[1]), sys.argv[2], sys.argv[3]
expected_result, expected_exit = sys.argv[4], int(sys.argv[5])
expected_codes = [] if not sys.argv[6] else sys.argv[6].split(",")
assert status == expected_exit, (status, expected_exit)
assert stderr == "", stderr
lines = stdout.splitlines()
assert len(lines) == 1, repr(stdout)
payload = json.loads(lines[0])
assert list(payload) == ["schema", "result", "exit_code", "diagnostic_codes"]
assert payload == {
    "schema": "DatarimQaRunFailLinesValidationSummary/v1",
    "result": expected_result,
    "exit_code": expected_exit,
    "diagnostic_codes": expected_codes,
}
PY
}

@test "empty synthetic FAIL-line set produces a fixed PASS summary without changing inputs" {
    printf 'synthetic output has no failure marker\n' > "$RUN/results.log"
    printf '{"cases":{},"fail_lines":[]}\n' > "$MANIFEST"
    before="$(sha256sum "$RUN/results.log" "$MANIFEST")"
    run_summary
    assert_summary PASS 0 ""
    after="$(sha256sum "$RUN/results.log" "$MANIFEST")"
    [ "$before" = "$after" ]
}

@test "recorded failing case is accounted for without claiming its underlying case passed" {
    write_fail_line
    printf '{"cases":{"case-one":"fail"},"fail_lines":[{"path":"results.log","line":1,"disposition":"failing_case","case_id":"case-one"}]}\n' > "$MANIFEST"
    run_summary
    assert_summary PASS 0 ""
}

@test "harness-fixed summary uses synthetic recorded response evidence without replaying a command" {
    write_fail_line
    printf 'synthetic response bytes\n' > "$RUN/response.txt"
    response_sha="$(sha256sum "$RUN/response.txt" | cut -d' ' -f1)"
    printf '{"response_sha256":"%s","result":"pass"}\n' "$response_sha" > "$RUN/reevaluation.json"
    printf '{"cases":{},"fail_lines":[{"path":"results.log","line":1,"disposition":"harness_fixed","response_path":"response.txt","reevaluation_path":"reevaluation.json"}]}\n' > "$MANIFEST"
    before="$(sha256sum "$RUN/results.log" "$RUN/response.txt" "$RUN/reevaluation.json" "$MANIFEST")"
    run_summary
    assert_summary PASS 0 ""
    after="$(sha256sum "$RUN/results.log" "$RUN/response.txt" "$RUN/reevaluation.json" "$MANIFEST")"
    [ "$before" = "$after" ]
}

@test "harness-fixed response mismatch is refused with one fixed code and no fixture values" {
    printf 'FAIL: private line canary marker\n' > "$RUN/private-line-canary.log"
    printf 'synthetic response bytes\n' > "$RUN/response.txt"
    response_sha="$(sha256sum "$RUN/response.txt" | cut -d' ' -f1)"
    wrong_sha="$(python3 - "$response_sha" <<'PY'
import sys

digest = sys.argv[1]
replacement = "1" if digest[0] != "1" else "0"
print(replacement + digest[1:])
PY
)"
    printf '{"response_sha256":"%s","result":"pass"}\n' "$wrong_sha" > "$RUN/reevaluation.json"
    printf '{"cases":{},"fail_lines":[{"path":"private-line-canary.log","line":1,"disposition":"harness_fixed","response_path":"response.txt","reevaluation_path":"reevaluation.json"}]}\n' > "$MANIFEST"
    run_summary
    assert_summary FAIL 1 RUN_VALIDATION_FAILED
    [[ "$output" != *"private-line-canary"* ]]
    [[ "$output" != *"response.txt"* ]]
    [[ "$output" != *"$wrong_sha"* ]]
}

@test "orphan FAIL line with private path marker is summarized without exception text" {
    write_fail_line
    printf '{"cases":{},"fail_lines":[]}\n' > "$MANIFEST"
    run_summary
    assert_summary FAIL 1 RUN_VALIDATION_FAILED
    [[ "$output" != *"results.log"* ]]
    [[ "$output" != *"orphan FAIL lines"* ]]
}

@test "invalid disposition and missing failing case both use the fixed refusal result" {
    write_fail_line
    printf '{"cases":{},"fail_lines":[{"path":"results.log","line":1,"disposition":"private-disposition-canary"}]}\n' > "$MANIFEST"
    run_summary
    assert_summary FAIL 1 RUN_VALIDATION_FAILED
    [[ "$output" != *"private-disposition-canary"* ]]

    printf '{"cases":{"case-one":"pass"},"fail_lines":[{"path":"results.log","line":1,"disposition":"failing_case","case_id":"private-case-canary"}]}\n' > "$MANIFEST"
    run_summary
    assert_summary FAIL 1 RUN_VALIDATION_FAILED
    [[ "$output" != *"private-case-canary"* ]]
}

@test "duplicate and absent FAIL-line entries remain refusals" {
    write_fail_line
    printf '{"cases":{"case-one":"fail"},"fail_lines":[{"path":"results.log","line":1,"disposition":"failing_case","case_id":"case-one"},{"path":"results.log","line":1,"disposition":"failing_case","case_id":"case-one"}]}\n' > "$MANIFEST"
    run_summary
    assert_summary FAIL 1 RUN_VALIDATION_FAILED

    printf '{"cases":{"case-one":"fail"},"fail_lines":[{"path":"absent.log","line":9,"disposition":"failing_case","case_id":"case-one"}]}\n' > "$MANIFEST"
    run_summary
    assert_summary FAIL 1 RUN_VALIDATION_FAILED
    [[ "$output" != *"absent.log"* ]]
}

@test "default PASS output and exit remain unchanged next to summary mode" {
    printf 'synthetic output has no failure marker\n' > "$RUN/results.log"
    printf '{"cases":{},"fail_lines":[]}\n' > "$MANIFEST"
    run --separate-stderr python3 "$SCRIPT" --run-dir "$RUN" --manifest "$MANIFEST"
    default_status="$status"
    default_output="$output"
    default_stderr="$stderr"
    run_summary
    [ "$default_status" -eq 0 ]
    [ "$default_output" = "QA_RUN_FAIL_LINES PASS" ]
    [ "$default_stderr" = "" ]
    assert_summary PASS 0 ""
}

@test "default FAIL prose and exit remain unchanged while summary withholds dynamic detail" {
    write_fail_line
    printf '{"cases":{},"fail_lines":[]}\n' > "$MANIFEST"
    run --separate-stderr python3 "$SCRIPT" --run-dir "$RUN" --manifest "$MANIFEST"
    default_status="$status"
    default_output="$output"
    run_summary
    [ "$default_status" -eq 1 ]
    [[ "$default_output" == *"orphan FAIL lines"* ]]
    assert_summary FAIL 1 RUN_VALIDATION_FAILED
    [[ "$output" != *"orphan FAIL lines"* ]]
}

@test "argument parsing and help retain argparse behavior outside summary output" {
    run --separate-stderr python3 "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--summary-json"* ]]
    [[ "$output" == *"documentation/reference/qa-run-fail-lines-summary.md"* ]]
    [ "$stderr" = "" ]

    run --separate-stderr python3 "$SCRIPT" --summary-json
    [ "$status" -eq 2 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"usage:"* ]]
    [[ "$stderr" != *"DatarimQaRunFailLinesValidationSummary/v1"* ]]
}
