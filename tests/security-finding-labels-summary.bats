#!/usr/bin/env bats
# Synthetic CLI controls for the opt-in security-finding validation summary.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/check-security-finding-labels.py"
    REPORT="$BATS_TEST_TMPDIR/report.md"
}

write_report() {
    local payload="$1"
    local destination="${2:-$REPORT}"
    {
        printf '%s\n' '# Synthetic summary-control report'
        printf '%s\n' '<!-- security-finding-evidence:begin -->'
        printf '%s\n' '```json'
        printf '%s\n' "$payload"
        printf '%s\n' '```'
        printf '%s\n' '<!-- security-finding-evidence:end -->'
    } > "$destination"
}

assert_summary() {
    local expected_result="$1"
    local expected_exit="$2"
    local expected_codes="$3"
    local expected_status="$4"
    local expected_count="$5"
    python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import json
import sys
obj = json.loads(sys.argv[1])
expected = {
    "schema": "DatarimSecurityFindingLabelsValidationSummary/v1",
    "result": sys.argv[2],
    "exit_code": int(sys.argv[3]),
    "diagnostic_codes": json.loads(sys.argv[4]),
    "validation_error_count": None if sys.argv[6] == "null" else int(sys.argv[6]),
    "validation_error_count_status": sys.argv[5],
}
assert type(obj) is dict and obj == expected, (obj, expected)
assert list(obj) == [
    "schema", "result", "exit_code", "diagnostic_codes",
    "validation_error_count", "validation_error_count_status",
]
PY
}

@test "empty findings emit a measured known-zero summary" {
    write_report '{"schema":"security-finding-evidence/v1","findings":[]}'
    run python3 -I "$SCRIPT" --report "$REPORT" --summary-json
    [ "$status" -eq 0 ]
    assert_summary "$output" VALID 0 '[]' MEASURED 0
}

@test "supported, hypothesis, legacy, and runtime-shaped synthetic labels validate without promotion" {
    local label="$BATS_TEST_TMPDIR/label.json"
    local findings
    for findings in \
        '{"id":"synthetic","evidence_label":"hypothesis","reproduction_state":"not_attempted","assessment_scope":"static","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":[],"origin":"author_reported","witness":null,"custody_ref":null}' \
        '{"id":"synthetic","evidence_label":"supported","reproduction_state":"inconclusive","assessment_scope":"static","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":["synthetic-ref"],"origin":"artifact_cited","witness":null,"custody_ref":null}' \
        '{"id":"synthetic","evidence_label":"legacy_review","reproduction_state":"not_attempted","assessment_scope":"static","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":["synthetic-ref"],"origin":"artifact_cited","witness":null,"custody_ref":null}' \
        '{"id":"synthetic","evidence_label":"supported","reproduction_state":"reproduced","assessment_scope":"qualified_runtime","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":["synthetic-ref"],"origin":"independent_witness","witness":{"identity":"Synthetic witness","evidence_ref":"synthetic-ref"},"custody_ref":"synthetic-ref"}'
    do
        write_report "{\"schema\":\"security-finding-evidence/v1\",\"findings\":[$findings]}" "$label"
        run python3 -I "$SCRIPT" --report "$label" --summary-json
        [ "$status" -eq 0 ]
        assert_summary "$output" VALID 0 '[]' MEASURED 0
    done
}

@test "returned validation errors use only the fixed code and count" {
    write_report '{"schema":"security-finding-evidence/v1","findings":[{"id":"HOSTILE_SYNTHETIC_ID","evidence_label":"bad-label","reproduction_state":"not_attempted","assessment_scope":"static","scope":"HOSTILE_SYNTHETIC_PATH","mechanism":"HOSTILE_SYNTHETIC_MECHANISM","evidence_refs":[],"origin":"author_reported","witness":null,"custody_ref":null},{"id":"ANOTHER_SYNTHETIC_ID","evidence_label":"also-bad","reproduction_state":"not_attempted","assessment_scope":"static","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":[],"origin":"author_reported","witness":null,"custody_ref":null}]}'
    run python3 -I "$SCRIPT" --report "$REPORT" --summary-json
    [ "$status" -eq 1 ]
    [[ "$output" != *"HOSTILE_SYNTHETIC"* ]]
    assert_summary "$output" INVALID 1 '["LABELS_INCONSISTENT"]' MEASURED 2
}

@test "typed input refusals emit not-measured summaries without exception text" {
    local bad="$BATS_TEST_TMPDIR/bad.md"
    local out="$BATS_TEST_TMPDIR/stdout"
    local err="$BATS_TEST_TMPDIR/stderr"
    local kind
    for kind in markers oversize encoding duplicate missing; do
        case "$kind" in
            markers) printf '%s\n' 'no marker' > "$bad" ;;
            oversize) python3 - "$bad" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"x" * 1_000_001)
PY
                ;;
            encoding) python3 - "$bad" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"\xff")
PY
                ;;
            duplicate) write_report '{"schema":"security-finding-evidence/v1","schema":"security-finding-evidence/v1","findings":[]}' "$bad" ;;
            missing) rm -f -- "$bad" ;;
        esac
        run env SCRIPT="$SCRIPT" BAD="$bad" OUT="$out" ERR="$err" bash -c 'python3 -I "$SCRIPT" --report "$BAD" --summary-json > "$OUT" 2> "$ERR"; printf "%s" "$?" > "${OUT}.status"; exit 0'
        [ "$status" -eq 0 ]
        refusal_status="$(cat "${out}.status")"
        [ "$refusal_status" -eq 2 ]
        [ ! -s "$err" ]
        assert_summary "$(cat "$out")" INPUT_REFUSED 2 '["REPORT_INPUT_REFUSED"]' NOT_MEASURED null
    done
}

@test "default and summary modes preserve acceptance and exit parity for 0, 1, and 2" {
    local invalid="$BATS_TEST_TMPDIR/invalid.md"
    local absent="$BATS_TEST_TMPDIR/absent.md"
    write_report '{"schema":"security-finding-evidence/v1","findings":[]}' "$REPORT"
    write_report '{"schema":"security-finding-evidence/v1","findings":[{"id":"synthetic","evidence_label":"bad-label","reproduction_state":"not_attempted","assessment_scope":"static","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":[],"origin":"author_reported","witness":null,"custody_ref":null}]}' "$invalid"
    for pair in "$REPORT:0:VALID:MEASURED:0" "$invalid:1:INVALID:MEASURED:1" "$absent:2:INPUT_REFUSED:NOT_MEASURED:null"; do
        IFS=: read -r path expected result availability count <<< "$pair"
        run python3 -I "$SCRIPT" --report "$path"
        default_status="$status"
        run python3 -I "$SCRIPT" --report "$path" --summary-json
        [ "$status" -eq "$expected" ]
        [ "$default_status" -eq "$status" ]
        if [ "$expected" -eq 0 ]; then
            assert_summary "$output" "$result" 0 '[]' "$availability" "$count"
        elif [ "$expected" -eq 1 ]; then
            assert_summary "$output" "$result" 1 '["LABELS_INCONSISTENT"]' "$availability" "$count"
        else
            assert_summary "$output" "$result" 2 '["REPORT_INPUT_REFUSED"]' "$availability" "$count"
        fi
    done
}

@test "default text diagnostics and stream placement remain unchanged" {
    local invalid="$BATS_TEST_TMPDIR/default-invalid.md"
    local refused="$BATS_TEST_TMPDIR/default-refused.md"
    local out="$BATS_TEST_TMPDIR/default.stdout"
    local err="$BATS_TEST_TMPDIR/default.stderr"
    write_report '{"schema":"security-finding-evidence/v1","findings":[]}' "$REPORT"
    run env SCRIPT="$SCRIPT" REPORT="$REPORT" OUT="$out" ERR="$err" bash -c 'python3 -I "$SCRIPT" --report "$REPORT" > "$OUT" 2> "$ERR"; printf "%s" "$?" > "${OUT}.status"; exit 0'
    [ "$status" -eq 0 ]
    [ "$(cat "${out}.status")" -eq 0 ]
    [ "$(cat "$out")" = "security finding labels: structurally consistent" ]
    [ ! -s "$err" ]

    write_report '{"schema":"security-finding-evidence/v1","findings":[{"id":"synthetic","evidence_label":"bad-label","reproduction_state":"not_attempted","assessment_scope":"static","scope":"Synthetic scope","mechanism":"Synthetic mechanism","evidence_refs":[],"origin":"author_reported","witness":null,"custody_ref":null}]}' "$invalid"
    run env SCRIPT="$SCRIPT" REPORT="$invalid" OUT="$out" ERR="$err" bash -c 'python3 -I "$SCRIPT" --report "$REPORT" > "$OUT" 2> "$ERR"; printf "%s" "$?" > "${OUT}.status"; exit 0'
    [ "$status" -eq 0 ]
    [ "$(cat "${out}.status")" -eq 1 ]
    [ ! -s "$out" ]
    [ "$(cat "$err")" = "security finding labels: finding[0]: invalid evidence_label" ]

    write_report 'no json block' "$refused"
    run env SCRIPT="$SCRIPT" REPORT="$refused" OUT="$out" ERR="$err" bash -c 'python3 -I "$SCRIPT" --report "$REPORT" > "$OUT" 2> "$ERR"; printf "%s" "$?" > "${OUT}.status"; exit 0'
    [ "$status" -eq 0 ]
    [ "$(cat "${out}.status")" -eq 2 ]
    [ ! -s "$out" ]
    [ "$(cat "$err")" = "security finding labels: label block contains invalid or duplicate-key JSON" ]
}

@test "help advertises the opt-in flag and parser errors remain outside summary output" {
    run python3 -I "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--summary-json"* ]]
    run python3 -I "$SCRIPT" --summary-json
    [ "$status" -eq 2 ]
    [[ "$output" != *'"schema":"DatarimSecurityFindingLabelsValidationSummary/v1"'* ]]
}

@test "summary validation leaves synthetic input bytes unchanged" {
    write_report '{"schema":"security-finding-evidence/v1","findings":[]}'
    before="$(sha256sum "$REPORT" | cut -d ' ' -f1)"
    run python3 -I "$SCRIPT" --report "$REPORT" --summary-json
    [ "$status" -eq 0 ]
    after="$(sha256sum "$REPORT" | cut -d ' ' -f1)"
    [ "$before" = "$after" ]
}
