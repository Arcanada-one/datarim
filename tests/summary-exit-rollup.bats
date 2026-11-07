#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/aggregate-summary-exits.py"

setup() {
    TMPROOT="$BATS_TEST_TMPDIR/summary-exit-rollup"
    mkdir -p "$TMPROOT"
    umask 077
    CASE_EVIDENCE_DIR="${D5_EVIDENCE_DIR:-$TMPROOT/evidence}"
    mkdir -p "$CASE_EVIDENCE_DIR"
    mkdir -p "$CASE_EVIDENCE_DIR/fixtures"
    chmod 700 "$CASE_EVIDENCE_DIR"
    chmod 700 "$CASE_EVIDENCE_DIR/fixtures"
}

write_fixture() {
    local name="$1"
    shift
    local path="$TMPROOT/$name.json"
    cat >"$path"
    chmod 600 "$path"
    FIXTURE="$path"
}

capture_rollup() {
    local label="$1"
    local fixture="$2"
    local durable_fixture="$CASE_EVIDENCE_DIR/fixtures/$label.json"
    local out="$CASE_EVIDENCE_DIR/$label.stdout"
    local err="$CASE_EVIDENCE_DIR/$label.stderr"
    local receipt="$CASE_EVIDENCE_DIR/$label.receipt.json"
    local started ended pid status source_sha test_sha fixture_sha

    cp -- "$fixture" "$durable_fixture"
    chmod 600 "$durable_fixture"
    fixture="$durable_fixture"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    source_sha="$(sha256sum "$SCRIPT" | cut -d' ' -f1)"
    test_sha="$(sha256sum "${BATS_TEST_FILENAME}" | cut -d' ' -f1)"
    fixture_sha="$(sha256sum "$fixture" | cut -d' ' -f1)"
    : >"$out"
    : >"$err"
    chmod 600 "$out" "$err"

    "$SCRIPT" <"$fixture" >"$out" 2>"$err" &
    pid=$!
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    ROLLUP_RECEIPT="$receipt" \
    ROLLUP_LABEL="$label" \
    ROLLUP_STARTED="$started" \
    ROLLUP_ENDED="$ended" \
    ROLLUP_PID="$pid" \
    ROLLUP_STATUS="$status" \
    ROLLUP_SOURCE_SHA="$source_sha" \
    ROLLUP_TEST_SHA="$test_sha" \
    ROLLUP_FIXTURE_SHA="$fixture_sha" \
    ROLLUP_SCRIPT="$SCRIPT" \
    ROLLUP_TEST="${BATS_TEST_FILENAME}" \
    ROLLUP_FIXTURE="$fixture" \
    ROLLUP_STDOUT="$out" \
    ROLLUP_STDERR="$err" \
    python3 - <<'PY'
import hashlib
import json
import os
import stat
from pathlib import Path

def measured(path):
    data = Path(path).read_bytes()
    return {"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

record = {
    "case": os.environ["ROLLUP_LABEL"],
    "argv": [os.environ["ROLLUP_SCRIPT"]],
    "cwd": os.getcwd(),
    "started_utc": os.environ["ROLLUP_STARTED"],
    "ended_utc": os.environ["ROLLUP_ENDED"],
    "pid": int(os.environ["ROLLUP_PID"]),
    "exit_code": int(os.environ["ROLLUP_STATUS"]),
    "source_sha256": os.environ["ROLLUP_SOURCE_SHA"],
    "test_sha256": os.environ["ROLLUP_TEST_SHA"],
    "fixture": {"path": os.environ["ROLLUP_FIXTURE"], "sha256": os.environ["ROLLUP_FIXTURE_SHA"]},
    "stdout": measured(os.environ["ROLLUP_STDOUT"]),
    "stderr": measured(os.environ["ROLLUP_STDERR"]),
}
destination = Path(os.environ["ROLLUP_RECEIPT"])
destination.write_text(json.dumps(record, sort_keys=True) + "\n", encoding="utf-8")
destination.chmod(0o600)
saved = json.loads(destination.read_text(encoding="utf-8"))
if saved["exit_code"] != int(os.environ["ROLLUP_STATUS"]):
    raise SystemExit("capture receipt exit mismatch")
if saved["source_sha256"] != hashlib.sha256(Path(os.environ["ROLLUP_SCRIPT"]).read_bytes()).hexdigest():
    raise SystemExit("capture receipt source mismatch")
if saved["test_sha256"] != hashlib.sha256(Path(os.environ["ROLLUP_TEST"]).read_bytes()).hexdigest():
    raise SystemExit("capture receipt test mismatch")
if saved["fixture"]["sha256"] != hashlib.sha256(Path(os.environ["ROLLUP_FIXTURE"]).read_bytes()).hexdigest():
    raise SystemExit("capture receipt fixture mismatch")
for name in ("stdout", "stderr"):
    raw_path = Path(saved[name]["path"])
    raw_bytes = raw_path.read_bytes()
    if len(raw_bytes) != saved[name]["bytes"] or hashlib.sha256(raw_bytes).hexdigest() != saved[name]["sha256"]:
        raise SystemExit("capture receipt stream mismatch")
    if stat.S_IMODE(raw_path.stat().st_mode) != 0o600:
        raise SystemExit("capture receipt stream permissions mismatch")
if stat.S_IMODE(destination.stat().st_mode) != 0o600:
    raise SystemExit("capture receipt permissions mismatch")
PY

    ACTUAL_STATUS="$status"
    ACTUAL_STDOUT="$out"
    ACTUAL_STDERR="$err"
}

assert_output() {
    local expected="$1"
    local expected_path="$TMPROOT/expected.json"
    printf '%s\n' "$expected" >"$expected_path"
    cmp -s "$expected_path" "$ACTUAL_STDOUT"
    [ ! -s "$ACTUAL_STDERR" ]
}

assert_refusal() {
    [ "$ACTUAL_STATUS" -eq 2 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"INPUT_REFUSED","exit_code":2,"diagnostic_codes":["SUMMARY_EXIT_ROLLUP_REFUSED"],"summary_count":null,"summary_count_status":"NOT_MEASURED","exit_counts":null}'
}

@test "all-zero summaries and an empty array are measured clean results" {
    write_fixture "clean" <<'JSON'
[{"schema":"DatarimExample/v1","exit_code":0},{"schema":"DatarimOther2/v12","exit_code":0,"opaque":{"private":"do-not-echo"}}]
JSON
    capture_rollup "clean" "$FIXTURE"
    [ "$ACTUAL_STATUS" -eq 0 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"summary_count":2,"summary_count_status":"MEASURED","exit_counts":{"0":2,"1":0,"2":0}}'

    write_fixture "empty" <<'JSON'
[]
JSON
    capture_rollup "empty" "$FIXTURE"
    [ "$ACTUAL_STATUS" -eq 0 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"summary_count":0,"summary_count_status":"MEASURED","exit_counts":{"0":0,"1":0,"2":0}}'
}

@test "findings take aggregate status one and integer-valued decimal declarations are exact" {
    write_fixture "findings" <<'JSON'
[{"schema":"DatarimFinding/v2","exit_code":1.0},{"schema":"DatarimFinding/v2","exit_code":0}]
JSON
    capture_rollup "findings" "$FIXTURE"
    [ "$ACTUAL_STATUS" -eq 1 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"FINDINGS","exit_code":1,"diagnostic_codes":["SUMMARY_FINDINGS_PRESENT"],"summary_count":2,"summary_count_status":"MEASURED","exit_counts":{"0":1,"1":1,"2":0}}'
}

@test "declared tool error takes precedence over findings" {
    write_fixture "error-precedence" <<'JSON'
[{"schema":"DatarimFinding/v2","exit_code":1},{"schema":"DatarimTool/v1","exit_code":2}]
JSON
    capture_rollup "error-precedence" "$FIXTURE"
    [ "$ACTUAL_STATUS" -eq 2 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"ERROR","exit_code":2,"diagnostic_codes":["SUMMARY_ERROR_PRESENT"],"summary_count":2,"summary_count_status":"MEASURED","exit_counts":{"0":0,"1":1,"2":1}}'
}

@test "duplicate keys, booleans, strings, nonfinite numbers, and non-object items are refused" {
    local input
    local index=0
    for input in \
        '[{"schema":"DatarimX/v1","exit_code":0,"exit_code":1}]' \
        '[{"schema":"DatarimX/v1","exit_code":true}]' \
        '[{"schema":"DatarimX/v1","exit_code":"1"}]' \
        '[{"schema":"DatarimX/v1","exit_code":NaN}]' \
        '[{"schema":"DatarimX/v1","exit_code":0},null]'
    do
        index=$((index + 1))
        write_fixture "invalid-$index" <<JSON
$input
JSON
        capture_rollup "invalid-$index" "$FIXTURE"
        assert_refusal
    done
}

@test "malformed top level and duplicate nested keys are refused without partial counts" {
    write_fixture "nested-duplicate" <<'JSON'
[{"schema":"DatarimX/v1","exit_code":0,"opaque":{"k":1,"k":2}}]
JSON
    capture_rollup "nested-duplicate" "$FIXTURE"
    assert_refusal

    write_fixture "non-array" <<'JSON'
{"schema":"DatarimX/v1","exit_code":0}
JSON
    capture_rollup "non-array" "$FIXTURE"
    assert_refusal

    write_fixture "partial-invalid" <<'JSON'
[{"schema":"DatarimX/v1","exit_code":0},{"schema":"DatarimX/v1","exit_code":3}]
JSON
    capture_rollup "partial-invalid" "$FIXTURE"
    assert_refusal
}

@test "schema identifiers are bounded ASCII versioned Datarim identifiers" {
    write_fixture "bad-schema" <<'JSON'
[{"schema":"DatarimX/v0","exit_code":0}]
JSON
    capture_rollup "bad-schema" "$FIXTURE"
    assert_refusal

    python3 - "$TMPROOT/schema-128.json" <<'PY'
import json
import sys
schema = "Datarim" + "x" * 118 + "/v1"
assert len(schema) == 128
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump([{"schema": schema, "exit_code": 0}], stream, separators=(",", ":"))
PY
    chmod 600 "$TMPROOT/schema-128.json"
    capture_rollup "schema-128" "$TMPROOT/schema-128.json"
    [ "$ACTUAL_STATUS" -eq 0 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"summary_count":1,"summary_count_status":"MEASURED","exit_counts":{"0":1,"1":0,"2":0}}'
}

@test "the 256-object limit is inclusive and larger arrays are refused" {
    python3 - "$TMPROOT/count-256.json" "$TMPROOT/count-257.json" <<'PY'
import json
import sys
item = {"schema": "DatarimX/v1", "exit_code": 0}
for path, count in zip(sys.argv[1:], (256, 257)):
    with open(path, "w", encoding="utf-8") as stream:
        json.dump([item] * count, stream, separators=(",", ":"))
PY
    chmod 600 "$TMPROOT/count-256.json" "$TMPROOT/count-257.json"
    capture_rollup "count-256" "$TMPROOT/count-256.json"
    [ "$ACTUAL_STATUS" -eq 0 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"summary_count":256,"summary_count_status":"MEASURED","exit_counts":{"0":256,"1":0,"2":0}}'

    capture_rollup "count-257" "$TMPROOT/count-257.json"
    assert_refusal
}

@test "64 KiB is accepted and the detection byte is refused" {
    python3 - "$TMPROOT/bytes-65536.json" "$TMPROOT/bytes-65537.json" <<'PY'
import sys
valid = b'[{"schema":"DatarimX/v1","exit_code":0}]'
with open(sys.argv[1], "wb") as stream:
    stream.write(valid + b" " * (65536 - len(valid)))
with open(sys.argv[2], "wb") as stream:
    stream.write(valid + b" " * (65537 - len(valid)))
PY
    chmod 600 "$TMPROOT/bytes-65536.json" "$TMPROOT/bytes-65537.json"
    capture_rollup "bytes-65536" "$TMPROOT/bytes-65536.json"
    [ "$ACTUAL_STATUS" -eq 0 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"summary_count":1,"summary_count_status":"MEASURED","exit_counts":{"0":1,"1":0,"2":0}}'

    capture_rollup "bytes-65537" "$TMPROOT/bytes-65537.json"
    assert_refusal
}

@test "hostile opaque metadata is ignored and never echoed" {
    local canary='PATH /synthetic/private/report.json content DO-NOT-EMIT'
    printf '[{"schema":"DatarimX/v1","exit_code":0,"opaque":%s}]\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$canary")" >"$TMPROOT/hostile.json"
    chmod 600 "$TMPROOT/hostile.json"
    capture_rollup "hostile" "$TMPROOT/hostile.json"
    [ "$ACTUAL_STATUS" -eq 0 ]
    assert_output '{"schema":"DatarimSummaryExitRollup/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"summary_count":1,"summary_count_status":"MEASURED","exit_counts":{"0":1,"1":0,"2":0}}'
    ! grep -Fq "$canary" "$ACTUAL_STDOUT"
}
