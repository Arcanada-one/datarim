#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup_file() {
  export SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/format-input-verification.py"
  if [[ -n "${FORMATTER_EVIDENCE_DIR:-}" ]]; then
    export FIXTURE_DIR="${FORMATTER_EVIDENCE_DIR}/formatter-inputs"
  else
    export FIXTURE_DIR="${BATS_FILE_TMPDIR}/formatter-inputs"
  fi
  mkdir -m 700 -- "$FIXTURE_DIR"
  python3 - "$FIXTURE_DIR" "${FORMATTER_EVIDENCE_DIR:-$BATS_FILE_TMPDIR}" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
evidence = pathlib.Path(sys.argv[2])
matched = {
    "schema": "DatarimCliInputManifestVerification/v1",
    "result": "MATCHED", "exit_code": 0, "diagnostic_codes": [],
    "file_count": 3, "file_count_status": "MEASURED", "changed_paths": [],
}
changed = {
    "schema": "DatarimCliInputManifestVerification/v1",
    "result": "CHANGED", "exit_code": 1,
    "diagnostic_codes": ["INPUT_MANIFEST_BYTES_CHANGED"],
    "file_count": 1, "file_count_status": "MEASURED",
    "changed_paths": ['nested/line\nforged\r\t\x1b\x7f\u202e".txt'],
}
refused = {
    "schema": "DatarimCliInputManifestVerification/v1",
    "result": "INPUT_REFUSED", "exit_code": 2,
    "diagnostic_codes": ["INPUT_MANIFEST_VERIFICATION_REFUSED"],
    "file_count": None, "file_count_status": "NOT_MEASURED", "changed_paths": [],
}
cases = {
    "matched.json": json.dumps(matched),
    "changed-hostile.json": json.dumps(changed, ensure_ascii=False),
    "refused.json": json.dumps(refused),
    "unknown-profile.json": json.dumps({**matched, "result": "FUTURE"}),
    "correlation.json": json.dumps({**matched, "exit_code": 1}),
    "extra-key.json": json.dumps({**matched, "extra": "ignored by producer"}),
    "boolean-count.json": json.dumps({**matched, "file_count": True}),
    "duplicate-key.json": '{"schema":"DatarimCliInputManifestVerification/v1",'
        '"result":"MATCHED","exit_code":0,"diagnostic_codes":[],'
        '"file_count":3,"file_count":3,"file_count_status":"MEASURED",'
        '"changed_paths":[]}',
    "nonfinite.json": json.dumps(matched).replace('"file_count": 3', '"file_count": NaN'),
    "deep.json": '{"schema":"DatarimCliInputManifestVerification/v1",'
        '"result":"CHANGED","exit_code":1,'
        '"diagnostic_codes":["INPUT_MANIFEST_BYTES_CHANGED"],'
        '"file_count":1,"file_count_status":"MEASURED",'
        '"changed_paths":[' + '[' * 1200 + '0' + ']' * 1200 + ']}',
    "decimal-count.json": json.dumps({**matched, "file_count": 1.0}),
    "fractional-count.json": json.dumps(matched).replace('"file_count": 3', '"file_count": 2.0000000000000001'),
    "invalid-path.json": json.dumps({**changed, "changed_paths": ["../outside"]}),
    "unsorted-paths.json": json.dumps({**changed, "file_count": 2,
        "changed_paths": ["z/file", "a/file"]}),
    "duplicate-paths.json": json.dumps({**changed, "file_count": 2,
        "changed_paths": ["a/file", "a/file"]}),
}
for name, text in cases.items():
    (root / name).write_bytes(text.encode("utf-8"))
(root / "oversize.json").write_bytes(b" " * (2 * 1024 * 1024 + 1))
(root / "invalid-utf8.json").write_bytes(b'{"schema":"\xff"}')
long_paths = [f"p{i:02d}/" + ("x" * 1100) for i in range(64)]
output_overflow = {**changed, "file_count": 64, "changed_paths": long_paths}
(root / "output-overflow.json").write_text(json.dumps(output_overflow), encoding="utf-8")
rows = []
for path in sorted(root.iterdir()):
    if path.is_file():
        rows.append(f"{path.name} {hashlib.sha256(path.read_bytes()).hexdigest()} {path.stat().st_size}")
manifest = ("\n".join(rows) + "\n").encode("ascii")
fd = os.open(evidence / "formatter-input-hashes.txt", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "wb") as stream:
    stream.write(manifest)
root_note = os.open(evidence / "formatter-fixture-root.txt", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(root_note, "w", encoding="utf-8") as stream:
    stream.write(str(root) + "\n")
PY
}

@test "MATCHED renders measured count and preserves exit zero" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/matched.json"
  [ "$status" -eq 0 ] \
    && [[ "$output" == $'Input verification result: MATCHED\nExit code: 0\nFile count: 3\nChanged paths:\n  (none)' ]] \
    && [[ -z "$stderr" ]]
}

@test "CHANGED renders hostile path text as one escaped JSON line" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/changed-hostile.json"
  [ "$status" -eq 1 ] \
    && [[ "$output" == *'  "nested/line\nforged\r\t\u001b\u007f\u202e\".txt"'* ]] \
    && [[ "$(printf '%s\n' "$output" | wc -l)" -eq 5 ]] \
    && [[ -z "$stderr" ]]
}

@test "INPUT_REFUSED is a valid report with unavailable count, not malformed input" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/refused.json"
  [ "$status" -eq 2 ] \
    && [[ "$output" == *"File count: NOT_MEASURED (unavailable)"* ]] \
    && [[ "$output" == *"Input verification result: INPUT_REFUSED"* ]] \
    && [[ -z "$stderr" ]]
}

@test "unknown result profile is refused" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/unknown-profile.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "exit code and result profile must agree" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/correlation.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "unknown fields are refused rather than silently discarded" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/extra-key.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "boolean count is not accepted as an integer count" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/boolean-count.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "duplicate JSON keys are refused" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/duplicate-key.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "non-finite JSON numbers are refused" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/nonfinite.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "deep JSON recursion is refused without a traceback" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/deep.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "input over two mebibytes is refused before parsing" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/oversize.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "unrenderable output over 64 kibibytes is refused all at once" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/output-overflow.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "integral decimal count is checked exactly and accepted" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/decimal-count.json"
  [ "$status" -eq 0 ] && [[ "$output" == *"File count: 1"* ]] && [[ -z "$stderr" ]]
}

@test "fractional decimal count is refused without rounding" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/fractional-count.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "invalid UTF-8 is refused without echoing input" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/invalid-utf8.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "noncanonical changed paths are refused" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/invalid-path.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "changed paths must be unique and sorted" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/unsorted-paths.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}

@test "duplicate changed paths are refused" {
  run --separate-stderr python3 "$SCRIPT" < "$FIXTURE_DIR/duplicate-paths.json"
  [ "$status" -eq 2 ] && [[ -z "$output" ]] && [[ "$stderr" == "INPUT_VERIFICATION_FORMAT_REFUSED" ]]
}
