#!/usr/bin/env bats

setup() {
  umask 077
  local test_name=${BATS_TEST_NAME//[^A-Za-z0-9_.-]/_}
  if [[ -n ${D5_SUMMARY_EVIDENCE_DIR:-} ]]; then
    TEST_EVIDENCE_DIR="$D5_SUMMARY_EVIDENCE_DIR/$test_name"
  elif [[ -n ${BATS_TEST_TMPDIR:-} ]]; then
    TEST_EVIDENCE_DIR="$BATS_TEST_TMPDIR/self-verification-summary"
  else
    TEST_EVIDENCE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/d5-findings-summary.XXXXXX")
  fi
  mkdir -p "$TEST_EVIDENCE_DIR/fixtures" "$TEST_EVIDENCE_DIR/raw"
  chmod 700 "$TEST_EVIDENCE_DIR" "$TEST_EVIDENCE_DIR/fixtures" "$TEST_EVIDENCE_DIR/raw"
  CLI="$BATS_TEST_DIRNAME/../dev-tools/validate-self-verification-findings.py"
  SOURCE=$(realpath "$CLI")
}

write_fixture() {
  local name=$1 contents=$2
  printf '%s' "$contents" > "$TEST_EVIDENCE_DIR/fixtures/$name.json"
  chmod 600 "$TEST_EVIDENCE_DIR/fixtures/$name.json"
  FIXTURE="$TEST_EVIDENCE_DIR/fixtures/$name.json"
}

run_cli() {
  local label=$1 fixture=$2
  shift 2
  local stdout="$TEST_EVIDENCE_DIR/raw/$label.stdout"
  local stderr="$TEST_EVIDENCE_DIR/raw/$label.stderr"
  local meta="$TEST_EVIDENCE_DIR/raw/$label.process.json"
  local source_before input_before source_after input_after started ended pid exit_code
  local -a argv=(python3 "$SOURCE" --round 1 --max-iter 2 "$@")
  source_before=$(sha256sum "$SOURCE" | cut -d ' ' -f 1)
  input_before=$(sha256sum "$fixture" | cut -d ' ' -f 1)
  started=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  "${argv[@]}" < "$fixture" > "$stdout" 2> "$stderr" &
  pid=$!
  if wait "$pid"; then
    exit_code=0
  else
    exit_code=$?
  fi
  ended=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  source_after=$(sha256sum "$SOURCE" | cut -d ' ' -f 1)
  input_after=$(sha256sum "$fixture" | cut -d ' ' -f 1)
  chmod 600 "$stdout" "$stderr"
  python3 - "$meta" "$pid" "$started" "$ended" "$exit_code" "$PWD" "$source_before" "$source_after" "$input_before" "$input_after" "${argv[@]}" <<'PY'
import json
import sys

(path, pid, started, ended, exit_code, cwd, source_before, source_after,
 input_before, input_after, *argv) = sys.argv[1:]
with open(path, "w", encoding="utf-8") as stream:
    json.dump({
        "pid": int(pid), "started_utc": started, "ended_utc": ended,
        "argv": argv, "cwd": cwd, "exit_code": int(exit_code),
        "source_sha256_before": source_before,
        "source_sha256_after": source_after,
        "input_sha256_before": input_before,
        "input_sha256_after": input_after,
    }, stream, sort_keys=True)
    stream.write("\n")
PY
  chmod 600 "$meta"
  # The direct process receipt is durable before checking the run or its output.
  [[ "$source_before" == "$source_after" ]]
  [[ "$input_before" == "$input_after" ]]
  [[ -s "$stdout" ]]
  CASE_EXIT=$exit_code
  CASE_STDOUT=$(cat "$stdout")
  CASE_STDERR=$(cat "$stderr")
}

assert_summary() {
  local expected_result=$1 expected_exit=$2 expected_code=$3
  local expected_normalized=$4 expected_normalized_status=$5
  local expected_malformed=$6 expected_malformed_status=$7
  python3 - "$CASE_STDOUT" "$expected_result" "$expected_exit" "$expected_code" \
    "$expected_normalized" "$expected_normalized_status" "$expected_malformed" \
    "$expected_malformed_status" <<'PY'
import json
import sys

(raw, result, exit_code, code, normalized, normalized_status,
 malformed, malformed_status) = sys.argv[1:]
value = json.loads(raw)
assert set(value) == {
    "schema", "result", "exit_code", "diagnostic_codes",
    "normalized_count", "normalized_count_status", "malformed_count",
    "malformed_count_status",
}
assert value["schema"] == "DatarimSelfVerificationFindingsSummary/v1"
assert value["result"] == result
assert value["exit_code"] == int(exit_code)
assert value["diagnostic_codes"] == ([] if code == "-" else [code])
assert value["normalized_count"] == (None if normalized == "null" else int(normalized))
assert value["normalized_count_status"] == normalized_status
assert value["malformed_count"] == (None if malformed == "null" else int(malformed))
assert value["malformed_count_status"] == malformed_status
PY
  [[ "$CASE_EXIT" -eq "$expected_exit" ]]
}

@test "empty valid input reports measured zero and retains default output" {
  write_fixture empty-valid '[]'
  run_cli empty-valid-summary "$FIXTURE" --summary-json
  assert_summary VALID 0 - 0 MEASURED 0 MEASURED
  run_cli empty-valid-default "$FIXTURE"
  [[ "$CASE_EXIT" -eq 0 ]]
  [[ "$CASE_STDOUT" == $'{\n  "ok": true,\n  "findings": [],\n  "malformed": []\n}' ]]
}

@test "evidence-backed valid finding reports one normalized record" {
  write_fixture valid-finding '{"findings":[{"severity":"high","category":"correctness","evidence":{"type":"file_quote","source":"synthetic/CANARY-PRIVATE-PATH","excerpt":"CANARY-PRIVATE-EXCERPT must not appear in summary"},"ac_criteria":["synthetic"]}]}'
  run_cli valid-finding "$FIXTURE" --summary-json
  assert_summary VALID 0 - 1 MEASURED 0 MEASURED
  [[ "$CASE_STDOUT" != *CANARY-PRIVATE-* ]]
  run_cli valid-finding-default "$FIXTURE"
  [[ "$CASE_EXIT" -eq 0 ]]
  python3 - "$CASE_STDOUT" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["ok"] is True
assert value["malformed"] == []
assert value["findings"][0]["evidence"]["source"] == "synthetic/CANARY-PRIVATE-PATH"
PY
}

@test "malformed record reports fixed invalid code and measured counts" {
  write_fixture malformed-record '[{"severity":"secret-CANARY","category":"wrong","evidence":{"type":"file_quote","source":"synthetic/CANARY-PRIVATE-PATH","excerpt":"CANARY-PRIVATE-EXCERPT"},"ac_criteria":[]}]'
  run_cli malformed-record "$FIXTURE" --summary-json
  assert_summary INVALID 1 FINDINGS_INVALID 0 MEASURED 1 MEASURED
  [[ "$CASE_STDOUT" != *CANARY-PRIVATE-* ]]
  [[ "$CASE_STDOUT" != *secret-CANARY* ]]
  run_cli malformed-record-default "$FIXTURE"
  [[ "$CASE_EXIT" -eq 1 ]]
  python3 - "$CASE_STDOUT" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["ok"] is False
assert len(value["malformed"]) == 1
assert value["malformed"][0]["finding"]["severity"] == "secret-CANARY"
PY
}

@test "malformed JSON refuses input with both counts unavailable" {
  write_fixture malformed-json 'not-json CANARY-PRIVATE-JSON'
  run_cli malformed-json "$FIXTURE" --summary-json
  assert_summary INPUT_REFUSED 1 FINDINGS_JSON_INVALID null NOT_MEASURED null NOT_MEASURED
  [[ "$CASE_STDOUT" != *CANARY-PRIVATE-JSON* ]]
}

@test "invalid top-level shape refuses input with both counts unavailable" {
  write_fixture invalid-shape '{"findings":"CANARY-PRIVATE-SHAPE"}'
  run_cli invalid-shape "$FIXTURE" --summary-json
  assert_summary INPUT_REFUSED 1 FINDINGS_SHAPE_INVALID null NOT_MEASURED null NOT_MEASURED
  [[ "$CASE_STDOUT" != *CANARY-PRIVATE-SHAPE* ]]
}

@test "legacy upgrade and absent evidence preserve completed normalization behavior" {
  write_fixture legacy-and-absent '[{"severity":"medium","category":"safety","evidence":{"type":"file_quote","source":"synthetic","excerpt":"legacy excerpt"},"ac_criteria":[]},{"severity":"low","category":"completeness","evidence":{"type":"absent"},"ac_criteria":[]}]'
  run_cli legacy-and-absent "$FIXTURE" --summary-json --upgrade-legacy
  assert_summary VALID 0 - 2 MEASURED 0 MEASURED
  [[ "$CASE_STDOUT" != *legacy* ]]
}
