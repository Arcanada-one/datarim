#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO_ROOT/dev-tools/check-plan-completion.py"
    VALID_REPORT="$BATS_TEST_TMPDIR/valid-plan-completion.md"
}

write_valid_report() {
    cat > "$VALID_REPORT" <<'EOF'
### Layer 3: Plan Completeness
| Step / deliverable | Status | Discrepancy reason | Evidence | Planned approach | Actual replacement | Missing evidence / exact check |
|---|---|---|---|---|---|---|
| completed step | DONE | - | commit abc | planned | actual | - |
| partial step | PARTIAL | scope cut | issue 12 | - | - | - |
| pending step | NOT DONE | blocked | issue 13 | - | - | - |
| changed step | CHANGED | scope cut | commit def | old path | new path | - |
| unavailable step | UNVERIFIABLE | blocked | log 14 | - | - | exact retained command |
EOF
}

file_sha256() {
    python3 - "$1" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

run_summary() {
    run --separate-stderr python3 "$CHECKER" --report "$1" --summary-json
}

assert_summary() {
    python3 - "$status" "$output" "$stderr" "$1" "$2" "$3" "$4" "$5" <<'PY'
import json
import sys

status = int(sys.argv[1])
stdout, stderr = sys.argv[2], sys.argv[3]
expected_result, expected_exit = sys.argv[4], int(sys.argv[5])
expected_count = None if sys.argv[6] == "null" else int(sys.argv[6])
expected_count_status = sys.argv[7]
expected_codes = [] if sys.argv[8] == "" else sys.argv[8].split(",")

assert status == expected_exit, (status, expected_exit)
assert stderr == "", stderr
lines = stdout.splitlines()
assert len(lines) == 1, repr(stdout)
payload = json.loads(lines[0])
assert list(payload) == [
    "schema",
    "result",
    "exit_code",
    "diagnostic_codes",
    "validation_error_count",
    "validation_error_count_status",
]
assert payload["schema"] == "DatarimPlanCompletionValidationSummary/v1"
assert payload["result"] == expected_result
assert payload["exit_code"] == expected_exit
assert payload["diagnostic_codes"] == expected_codes
assert payload["validation_error_count"] == expected_count
assert payload["validation_error_count_status"] == expected_count_status
assert set(payload["diagnostic_codes"]) <= {
    "E_SECTION_MISSING",
    "E_STATUS_TABLE_MISSING",
    "E_TABLE_HEADERS_INVALID",
    "E_TABLE_SEPARATOR_MISSING",
    "E_TABLE_ROW_SHAPE_INVALID",
    "E_DELIVERABLE_REQUIRED",
    "E_STATUS_UNSUPPORTED",
    "E_EVIDENCE_REQUIRED",
    "E_DONE_REASON_FORBIDDEN",
    "E_DONE_GAP_FORBIDDEN",
    "E_DISCREPANCY_REASON_UNSUPPORTED",
    "E_CHANGED_FIELDS_REQUIRED",
    "E_UNVERIFIABLE_GAP_REQUIRED",
    "E_GAP_ONLY_UNVERIFIABLE",
    "E_STATUS_TABLE_EMPTY",
    "E_VALIDATION_FAILED",
    "REPORT_UNREADABLE",
}
PY
}

@test "summary reports every existing recorded status without changing validation" {
    write_valid_report
    before="$(file_sha256 "$VALID_REPORT")"
    run_summary "$VALID_REPORT"
    after="$(file_sha256 "$VALID_REPORT")"
    assert_summary VALID 0 0 MEASURED "" \
        && [ "$before" = "$after" ]
}

@test "invalid report returns safe fixed codes and a measured error count" {
    cat > "$VALID_REPORT" <<'EOF'
### Layer 3: Plan Completeness
| Step / deliverable | Status | Discrepancy reason | Evidence | Planned approach | Actual replacement | Missing evidence / exact check |
|---|---|---|---|---|---|---|
| hostile-step-marker | PRIVATE_STATUS_MARKER | blocked | evidence-private-marker | - | - | - |
| evidence row | NOT DONE | blocked | - | - | - | - |
| changed row | CHANGED | scope cut | receipt | - | - | - |
| unverifiable row | UNVERIFIABLE | blocked | receipt | - | - | - |
| malformed row | PARTIAL | scope cut |
EOF
    run_summary "$VALID_REPORT"
    python3 - "$status" "$output" "$stderr" <<'PY'
import json
import sys

status, stdout, stderr = int(sys.argv[1]), sys.argv[2], sys.argv[3]
assert status == 1
assert stderr == ""
assert len(stdout.splitlines()) == 1
payload = json.loads(stdout)
assert payload["result"] == "INVALID"
assert payload["exit_code"] == 1
assert payload["validation_error_count"] == 5
assert payload["validation_error_count_status"] == "MEASURED"
assert payload["diagnostic_codes"] == [
    "E_STATUS_UNSUPPORTED",
    "E_EVIDENCE_REQUIRED",
    "E_CHANGED_FIELDS_REQUIRED",
    "E_UNVERIFIABLE_GAP_REQUIRED",
    "E_TABLE_ROW_SHAPE_INVALID",
]
for private_value in ("hostile-step-marker", "PRIVATE_STATUS_MARKER", "evidence-private-marker"):
    assert private_value not in stdout
PY
}

@test "summary maps a missing section to a fixed code" {
    printf 'no Layer 3 table here\n' > "$VALID_REPORT"
    run_summary "$VALID_REPORT"
    assert_summary INVALID 1 1 MEASURED E_SECTION_MISSING
}

@test "summary redacts a missing report path and marks validation count unavailable" {
    missing="$BATS_TEST_TMPDIR/private-path-canary-do-not-emit.md"
    run_summary "$missing"
    python3 - "$status" "$output" "$stderr" "$missing" <<'PY'
import json
import sys

status, stdout, stderr, path = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
assert status == 2
assert stderr == ""
assert len(stdout.splitlines()) == 1
payload = json.loads(stdout)
assert payload == {
    "schema": "DatarimPlanCompletionValidationSummary/v1",
    "result": "UNREADABLE",
    "exit_code": 2,
    "diagnostic_codes": ["REPORT_UNREADABLE"],
    "validation_error_count": None,
    "validation_error_count_status": "NOT_MEASURED",
}
assert path not in stdout
PY
}

@test "summary treats invalid UTF-8 input as unreadable without leaking its path" {
    report="$BATS_TEST_TMPDIR/private-invalid-utf8-path.md"
    printf '\377\376' > "$report"
    run_summary "$report"
    python3 - "$status" "$output" "$stderr" "$report" <<'PY'
import json
import sys

status, stdout, stderr, path = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
assert status == 2
assert stderr == ""
assert len(stdout.splitlines()) == 1
payload = json.loads(stdout)
assert payload["result"] == "UNREADABLE"
assert payload["exit_code"] == 2
assert payload["diagnostic_codes"] == ["REPORT_UNREADABLE"]
assert payload["validation_error_count"] is None
assert payload["validation_error_count_status"] == "NOT_MEASURED"
assert path not in stdout
PY
}

@test "default valid output and exit remain unchanged beside JSON mode" {
    write_valid_report
    run --separate-stderr python3 "$CHECKER" --report "$VALID_REPORT"
    default_status="$status"
    default_output="$output"
    default_stderr="$stderr"
    run_summary "$VALID_REPORT"
    python3 - "$default_status" "$default_output" "$default_stderr" "$status" "$output" "$stderr" <<'PY'
import json
import sys

default_status = int(sys.argv[1])
default_stdout, default_stderr = sys.argv[2], sys.argv[3]
summary_status, summary_stdout, summary_stderr = int(sys.argv[4]), sys.argv[5], sys.argv[6]
assert default_status == summary_status == 0
assert default_stdout == "plan-completion structure valid; statuses unchanged"
assert default_stderr == summary_stderr == ""
payload = json.loads(summary_stdout)
assert payload["result"] == "VALID" and payload["exit_code"] == 0
assert payload["validation_error_count"] == 0
PY
}

@test "default invalid prose and exit remain unchanged while JSON withholds report text" {
    cat > "$VALID_REPORT" <<'EOF'
### Layer 3: Plan Completeness
| Step / deliverable | Status | Discrepancy reason | Evidence | Planned approach | Actual replacement | Missing evidence / exact check |
|---|---|---|---|---|---|---|
| private-step-canary | PRIVATE-STATUS-CANARY | blocked | private-evidence-canary | - | - | - |
EOF
    before="$(file_sha256 "$VALID_REPORT")"
    run --separate-stderr python3 "$CHECKER" --report "$VALID_REPORT"
    default_status="$status"
    default_stderr="$stderr"
    run_summary "$VALID_REPORT"
    after="$(file_sha256 "$VALID_REPORT")"
    python3 - "$default_status" "$default_stderr" "$status" "$output" "$stderr" "$VALID_REPORT" "$before" "$after" <<'PY'
import json
import sys

default_status, default_stderr = int(sys.argv[1]), sys.argv[2]
summary_status, stdout, stderr = int(sys.argv[3]), sys.argv[4], sys.argv[5]
path, before, after = sys.argv[6:9]
assert default_status == summary_status == 1
assert "private-step-canary" in default_stderr
assert stderr == ""
assert len(stdout.splitlines()) == 1
payload = json.loads(stdout)
assert payload["result"] == "INVALID" and payload["exit_code"] == 1
assert payload["diagnostic_codes"] == ["E_STATUS_UNSUPPORTED"]
assert payload["validation_error_count"] == 1
for value in ("private-step-canary", "PRIVATE-STATUS-CANARY", "private-evidence-canary", path):
    assert value not in stdout
assert before == after
PY
}

@test "argument parser keeps help and usage failures outside the JSON guarantee" {
    run --separate-stderr python3 "$CHECKER" --help
    help_status="$status"
    help_output="$output"
    help_stderr="$stderr"
    run --separate-stderr python3 "$CHECKER" --summary-json
    python3 - "$help_status" "$help_output" "$help_stderr" "$status" "$output" "$stderr" "$REPO_ROOT" <<'PY'
from pathlib import Path
import sys

assert int(sys.argv[1]) == 0
assert sys.argv[2].startswith("usage:") and "--summary-json" in sys.argv[2]
assert "documentation/reference/plan-completion-summary.md" in sys.argv[2]
assert sys.argv[3] == ""
assert int(sys.argv[4]) == 2
assert sys.argv[5] == ""
assert "usage:" in sys.argv[6]
assert "DatarimPlanCompletionValidationSummary/v1" not in sys.argv[6]
assert (Path(sys.argv[7]) / "documentation/reference/plan-completion-summary.md").is_file()
PY
}

@test "unknown internal diagnostic codes collapse to a fixed generic fallback" {
    python3 - "$CHECKER" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("plan_completion", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
codes = module._safe_diagnostic_codes(["private-path-and-report-text-canary"], 1)
assert codes == ["E_VALIDATION_FAILED"]
assert "private-path-and-report-text-canary" not in " ".join(codes)
PY
}
