#!/usr/bin/env bats

setup_file() {
    if [[ -z "${RELAY_EVIDENCE_DIR:-}" ]]; then
        RELAY_EVIDENCE_DIR="${BATS_FILE_TMPDIR}/summary-exit-relay-evidence"
        export RELAY_EVIDENCE_DIR
        mkdir -p -- "$RELAY_EVIDENCE_DIR" || return 2
        chmod 700 -- "$RELAY_EVIDENCE_DIR" || return 2
    fi
}

setup() {
    umask 077
    RELAY_TOOL="${BATS_TEST_DIRNAME}/../dev-tools/relay-summary-exit.py"
    SCHEMA='DatarimTestSummary/v1'
    CASE_DIR="${RELAY_EVIDENCE_DIR}/case-${BATS_TEST_NUMBER}"
    mkdir -m 700 -- "$CASE_DIR" || return 2
    INPUT_FILE="${CASE_DIR}/stdin.json"
    STDOUT_FILE="${CASE_DIR}/stdout.bin"
    STDERR_FILE="${CASE_DIR}/stderr.bin"
    RECEIPT_FILE="${CASE_DIR}/direct-receipt.json"
    EXECUTION_MARKER="${CASE_DIR}/must-not-exist"
}

hash_file() {
    python3 - "$1" <<'PY'
import hashlib
import pathlib
import sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

write_input() {
    printf '%s' "$1" > "$INPUT_FILE" || return 2
    chmod 600 -- "$INPUT_FILE"
}

write_input_bytes() {
    printf '%b' "$1" > "$INPUT_FILE" || return 2
    chmod 600 -- "$INPUT_FILE"
}

write_size_fixture() {
    python3 - "$INPUT_FILE" "$1" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
size = int(sys.argv[2])
prefix = b'{"schema":"DatarimTestSummary/v1","exit_code":0,"padding":"'
suffix = b'"}'
if size < len(prefix) + len(suffix):
    raise SystemExit(2)
path.write_bytes(prefix + (b'x' * (size - len(prefix) - len(suffix))) + suffix)
PY
    chmod 600 -- "$INPUT_FILE"
}

capture_cli() {
    local started ended source_before source_after input_before input_after input_bytes stdout_hash stderr_hash
    local child_status
    local -a command
    command=(python3 "$RELAY_TOOL" "$@")

    source_before="$(hash_file "$RELAY_TOOL")" || return 2
    input_before="$(hash_file "$INPUT_FILE")" || return 2
    input_bytes="$(wc -c < "$INPUT_FILE" | tr -d '[:space:]')" || return 2
    started="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || return 2

    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    chmod 600 -- "$STDOUT_FILE" "$STDERR_FILE" || return 2
    "${command[@]}" < "$INPUT_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE" &
    CLI_PID=$!
    if wait "$CLI_PID"; then
        child_status=0
    else
        child_status=$?
    fi
    ended="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || return 2

    source_after="$(hash_file "$RELAY_TOOL")" || return 2
    input_after="$(hash_file "$INPUT_FILE")" || return 2
    stdout_hash="$(hash_file "$STDOUT_FILE")" || return 2
    stderr_hash="$(hash_file "$STDERR_FILE")" || return 2
    chmod 600 -- "$STDOUT_FILE" "$STDERR_FILE" || return 2

    python3 - "$RECEIPT_FILE" "$CLI_PID" "$started" "$ended" "$child_status" \
        "$PWD" "$source_before" "$source_after" "$input_before" "$input_after" \
        "$input_bytes" "$STDOUT_FILE" "$STDERR_FILE" "$stdout_hash" "$stderr_hash" \
        "${command[@]}" <<'PY'
import json
import os
import pathlib
import sys

(
    receipt_path, pid, started, ended, exit_code, cwd, source_before, source_after,
    input_before, input_after, input_bytes, stdout_path, stderr_path,
    stdout_sha256, stderr_sha256,
) = sys.argv[1:16]
record = {
    "argv": sys.argv[16:],
    "cwd": cwd,
    "end_utc": ended,
    "exit_code": int(exit_code),
    "input_bytes": int(input_bytes),
    "input_sha256_after": input_after,
    "input_sha256_before": input_before,
    "pid": int(pid),
    "source_sha256_after": source_after,
    "source_sha256_before": source_before,
    "start_utc": started,
    "stderr_path": stderr_path,
    "stderr_sha256": stderr_sha256,
    "stdout_path": stdout_path,
    "stdout_sha256": stdout_sha256,
}
path = pathlib.Path(receipt_path)
path.write_text(json.dumps(record, sort_keys=True, indent=2) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
}

assert_capture() {
    local expected_exit="$1" expected_stderr="$2"
    python3 - "$RECEIPT_FILE" "$INPUT_FILE" "$STDOUT_FILE" "$STDERR_FILE" \
        "$RELAY_TOOL" "$expected_exit" "$expected_stderr" <<'PY'
import hashlib
import json
import os
import pathlib
import stat
import sys

receipt_path, input_path, stdout_path, stderr_path, source_path, expected_exit, expected_stderr = sys.argv[1:]
receipt = json.loads(pathlib.Path(receipt_path).read_text(encoding="utf-8"))
input_bytes = pathlib.Path(input_path).read_bytes()
stdout = pathlib.Path(stdout_path).read_bytes()
stderr = pathlib.Path(stderr_path).read_bytes()
source_bytes = pathlib.Path(source_path).read_bytes()
expected_stderr_bytes = (expected_stderr + "\n").encode("utf-8") if expected_stderr else b""

valid = (
    receipt["exit_code"] == int(expected_exit)
    and receipt["pid"] > 0
    and receipt["argv"][:2] == ["python3", source_path]
    and receipt["cwd"] == os.getcwd()
    and receipt["start_utc"].endswith("Z")
    and receipt["end_utc"].endswith("Z")
    and receipt["input_bytes"] == len(input_bytes)
    and receipt["input_sha256_before"] == receipt["input_sha256_after"] == hashlib.sha256(input_bytes).hexdigest()
    and receipt["source_sha256_before"] == receipt["source_sha256_after"] == hashlib.sha256(source_bytes).hexdigest()
    and receipt["stdout_sha256"] == hashlib.sha256(stdout).hexdigest()
    and receipt["stderr_sha256"] == hashlib.sha256(stderr).hexdigest()
    and stdout == b""
    and stderr == expected_stderr_bytes
    and stat.S_IMODE(os.stat(receipt_path).st_mode) == 0o600
    and stat.S_IMODE(os.stat(input_path).st_mode) == 0o600
    and stat.S_IMODE(os.stat(stdout_path).st_mode) == 0o600
    and stat.S_IMODE(os.stat(stderr_path).st_mode) == 0o600
)
if not valid:
    raise SystemExit(1)
PY
}

@test "declared integer exit 0 is relayed without output" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 0 ''
}

@test "declared integer exit 1 is relayed without output" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":1}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 1 ''
}

@test "declared integer exit 2 is relayed without output" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":2}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 ''
}

@test "integer-valued float zero is relayed" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0.0}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 0 ''
}

@test "integer-valued float one is relayed" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":1.0}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 1 ''
}

@test "integer-valued float two is relayed" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":2.0}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 ''
}

@test "lowercase Datarim schema identifiers are accepted exactly" {
    write_input '{"schema":"datarim.live-evidence-summary/v1","exit_code":1}' &&
        capture_cli --expected-schema 'datarim.live-evidence-summary/v1' && assert_capture 1 ''
}

@test "boolean exit code is refused with a fixed label" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":true}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "string exit code is refused with a fixed label" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":"1"}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "out-of-range exit code is refused with a fixed label" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":3}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "missing exit code is refused with a fixed label" {
    write_input '{"schema":"DatarimTestSummary/v1"}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "null exit code is refused with a fixed label" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":null}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "schema mismatch is refused without reporting either identifier" {
    write_input '{"schema":"DatarimOtherSummary/v1","exit_code":1}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "missing expected schema is a fixed usage error" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0}' &&
        capture_cli && assert_capture 2 'ERROR: USAGE_ERROR'
}

@test "invalid expected schema is refused with a fixed label" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0}' &&
        capture_cli --expected-schema 'https://example.invalid/schema' &&
        assert_capture 2 'ERROR: INVALID_EXPECTED_SCHEMA'
}

@test "unknown option is a fixed usage error" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0}' &&
        capture_cli --expected-schema "$SCHEMA" --unexpected-value secret-sentinel &&
        assert_capture 2 'ERROR: USAGE_ERROR'
}

@test "duplicate JSON object keys are rejected" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0,"exit_code":1}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "invalid UTF-8 is rejected" {
    write_input_bytes '{"schema":"DatarimTestSummary/v1","exit_code":0}\xff' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "malformed JSON is rejected" {
    write_input '{"schema":,"exit_code":0}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "trailing second JSON value is rejected" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0} {"extra":true}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "NaN is rejected anywhere in the JSON object" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0,"extra":NaN}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "Infinity is rejected anywhere in the JSON object" {
    write_input '{"schema":"DatarimTestSummary/v1","exit_code":0,"extra":Infinity}' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "non-object top-level JSON is rejected" {
    write_input '[{"schema":"DatarimTestSummary/v1","exit_code":0}]' &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "exactly 64 KiB of valid JSON is accepted" {
    write_size_fixture "$((64 * 1024))" &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 0 ''
}

@test "input larger than 64 KiB is refused" {
    write_size_fixture "$((64 * 1024 + 1))" &&
        capture_cli --expected-schema "$SCHEMA" && assert_capture 2 'ERROR: INVALID_SUMMARY'
}

@test "hostile extra data is neither echoed nor executed" {
    printf '{"schema":"DatarimTestSummary/v1","exit_code":0,"payload":"touch %s"}' \
        "$EXECUTION_MARKER" > "$INPUT_FILE" && chmod 600 -- "$INPUT_FILE" &&
        capture_cli --expected-schema "$SCHEMA" &&
        assert_capture 0 '' && [ ! -e "$EXECUTION_MARKER" ]
}
