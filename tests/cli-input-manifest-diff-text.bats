#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup_file() {
  FORMATTER="$BATS_TEST_DIRNAME/../dev-tools/format-cli-input-manifest-diff.py"
  if [[ -n "${D5_INPUT_FIXTURES:-}" ]]; then
    FIXTURES="$D5_INPUT_FIXTURES"
  else
    FIXTURES="$BATS_FILE_TMPDIR/diff-text-fixtures"
    (umask 077 && mkdir -m 700 -p -- "$FIXTURES")
    python3 - "$FIXTURES" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
schema = "DatarimCliInputManifestDiff/v1"
a = "a" * 64
b = "b" * 64

def row(path, kind, before_hash=None, after_hash=None, before_size=None, after_size=None):
    return {
        "relative_path": path,
        "change": kind,
        "before_sha256": before_hash,
        "after_sha256": after_hash,
        "before_byte_count": before_size,
        "after_byte_count": after_size,
    }

def report(result="CHANGED", added=0, removed=0, modified=0, changes=None, *, code=None):
    if changes is None:
        changes = []
    refused = result == "INPUT_REFUSED"
    return {
        "schema": schema,
        "result": result,
        "exit_code": 2 if refused else (0 if result == "UNCHANGED" else 1),
        "diagnostic_codes": ["INPUT_MANIFEST_DIFF_REFUSED"] if refused else (["INPUT_MANIFEST_CHANGED"] if result == "CHANGED" else []),
        "added_count": None if refused else added,
        "removed_count": None if refused else removed,
        "modified_count": None if refused else modified,
        "counts_status": "NOT_MEASURED" if refused else "MEASURED",
        "changes": changes,
    }

def write(name, value=None, raw=None):
    path = root / name
    if raw is not None:
        path.write_bytes(raw)
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

write("unchanged.json", report("UNCHANGED"))
hostile_path = 'added/line\nquote"\\\x1b\x7f'
changed_rows = [
    row(hostile_path, "ADDED", None, a, None, 7),
    row("changed/file.txt", "MODIFIED", a, b, 3, 4),
    row("removed/old.txt", "REMOVED", a, None, 3, None),
]
write("changed-hostile.json", report(added=1, removed=1, modified=1, changes=changed_rows))
write("refused.json", report("INPUT_REFUSED"))

one_added = row("a/file", "ADDED", None, a, None, 3)
write("integral-decimal.json", raw=(
    '{"schema":"%s","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],'
    '"added_count":1.0,"removed_count":0,"modified_count":0,"counts_status":"MEASURED",'
    '"changes":[{"relative_path":"a/file","change":"ADDED","before_sha256":null,'
    '"after_sha256":"%s","before_byte_count":null,"after_byte_count":3.0}]}\n' % (schema, a)
).encode("utf-8"))

fixtures = {}
fixtures["unknown-key.json"] = report(added=1, changes=[{**one_added, "future": "ignored?"}])
fixtures["wrong-schema.json"] = {**report("UNCHANGED"), "schema": "other"}
fixtures["wrong-exit.json"] = {**report("UNCHANGED"), "exit_code": 1}
fixtures["boolean-count.json"] = {**report(added=1, changes=[one_added]), "added_count": True}
fixtures["fractional-count.json"] = {**report(added=1, changes=[one_added]), "added_count": 0.5}
fixtures["negative-count.json"] = {**report(added=1, changes=[one_added]), "added_count": -1}
fixtures["count-mismatch.json"] = {**report(added=0, changes=[one_added])}
fixtures["duplicate-path.json"] = report(added=2, changes=[one_added, {**one_added, "relative_path": "a/file"}])
fixtures["unsorted-paths.json"] = report(added=2, changes=[
    row("z/file", "ADDED", None, a, None, 1), row("a/file", "ADDED", None, b, None, 1),
])
fixtures["invalid-path.json"] = report(added=1, changes=[row("../outside", "ADDED", None, a, None, 1)])
fixtures["unknown-row-key.json"] = report(added=1, changes=[{**one_added, "extra": "x"}])
fixtures["added-has-before.json"] = report(added=1, changes=[{**one_added, "before_sha256": b, "before_byte_count": 0}])
fixtures["modified-identical.json"] = report(modified=1, changes=[row("same/file", "MODIFIED", a, a, 1, 1)])
for name, value in fixtures.items():
    write(name, value)

raw_cases = {
    "duplicate-key.json": ('{"schema":"%s","schema":"%s"}' % (schema, schema)).encode("ascii"),
    "malformed.json": b'{"schema":',
    "invalid-utf8.json": b'{"schema":"\xff"}',
    "nonfinite.json": b'{"schema":"%s","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":NaN,"removed_count":0,"modified_count":0,"counts_status":"MEASURED","changes":[]}' % schema.encode("ascii"),
    "huge-exponent.json": b'{"schema":"%s","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":1e999999,"removed_count":0,"modified_count":0,"counts_status":"MEASURED","changes":[]}' % schema.encode("ascii"),
    "deep.json": b'{"schema":"%s","result":"CHANGED","exit_code":1,"diagnostic_codes":["INPUT_MANIFEST_CHANGED"],"added_count":0,"removed_count":0,"modified_count":0,"counts_status":"MEASURED","changes":' % schema.encode("ascii") + b"[" * 1200 + b"0" + b"]" * 1200 + b"}\n",
    "oversized.json": b" " * (2 * 1024 * 1024 + 1),
}
for name, raw in raw_cases.items():
    write(name, raw=raw)

write("oversized-file-count.json", report(added=1, changes=[row("large", "ADDED", None, a, None, 1024 * 1024 + 1)]))
too_many_known = [row(f"file-{i:02d}", "ADDED", None, a, None, 1024 * 1024) for i in range(17)]
write("oversized-known-side-total.json", report(added=17, changes=too_many_known))
long_rows = [row(f"path-{i:02d}/" + "x" * 3000, "MODIFIED", a, b, 0, 1) for i in range(64)]
write("output-overflow.json", report(modified=64, changes=long_rows))
PY
  fi
  export FIXTURES
}

setup() {
  FORMATTER="$BATS_TEST_DIRNAME/../dev-tools/format-cli-input-manifest-diff.py"
}

assert_refusal() {
  local name="$1"
  run --separate-stderr "$FORMATTER" < "$FIXTURES/$name"
  [[ "$status" -eq 2 ]] \
    && [[ -z "$output" ]] \
    && [[ "$stderr" == "INPUT_MANIFEST_DIFF_FORMAT_REFUSED" ]]
}

@test "UNCHANGED renders measured zero counts with exit zero" {
  run --separate-stderr "$FORMATTER" < "$FIXTURES/unchanged.json"
  [[ "$status" -eq 0 ]] \
    && [[ -z "$stderr" ]] \
    && [[ "$output" == *"Input manifest difference: UNCHANGED"* ]] \
    && [[ "$output" == *"Counts: added=0 removed=0 modified=0 (MEASURED)"* ]] \
    && [[ "$output" == *"Changes:"* ]] \
    && [[ "$output" == *"(none)"* ]]
}

@test "CHANGED renders every row kind and escaped hostile path on one line" {
  run --separate-stderr "$FORMATTER" < "$FIXTURES/changed-hostile.json"
  [[ "$status" -eq 1 ]] \
    && [[ -z "$stderr" ]] \
    && [[ "$output" == *"Counts: added=1 removed=1 modified=1 (MEASURED)"* ]] \
    && expected_path=$(python3 -c 'import json; print(json.dumps("added/line\nquote\"\\\x1b\x7f", ensure_ascii=True), end="")') \
    && [[ "$output" == *"ADDED $expected_path | before: sha256=NOT_MEASURED bytes=NOT_MEASURED"* ]] \
    && [[ "$output" == *'REMOVED "removed/old.txt" | before: sha256='*" | after: sha256=NOT_MEASURED bytes=NOT_MEASURED"* ]] \
    && [[ "$output" == *'MODIFIED "changed/file.txt" | before: sha256='*" | after: sha256="* ]] \
    && [[ "$output" != *$'added/line\nquote'* ]]
}

@test "INPUT_REFUSED preserves unavailable counts rather than reporting zero" {
  run --separate-stderr "$FORMATTER" < "$FIXTURES/refused.json"
  [[ "$status" -eq 2 ]] \
    && [[ -z "$stderr" ]] \
    && [[ "$output" == *"Counts: added=NOT_MEASURED removed=NOT_MEASURED modified=NOT_MEASURED"* ]] \
    && [[ "$output" == *"Changes:"* ]]
}

@test "exact integral decimal numeric tokens are accepted without rounding" {
  run --separate-stderr "$FORMATTER" < "$FIXTURES/integral-decimal.json"
  [[ "$status" -eq 1 ]] \
    && [[ -z "$stderr" ]] \
    && [[ "$output" == *"Counts: added=1 removed=0 modified=0 (MEASURED)"* ]] \
    && [[ "$output" == *"after: sha256="*" bytes=3"* ]]
}

@test "unknown top-level fields refuse without echoing their value" {
  assert_refusal unknown-key.json
}

@test "unknown schema is refused" {
  assert_refusal wrong-schema.json
}

@test "exit code correlation is enforced" {
  assert_refusal wrong-exit.json
}

@test "duplicate JSON keys are refused" {
  assert_refusal duplicate-key.json
}

@test "malformed JSON is refused" {
  assert_refusal malformed.json
}

@test "invalid UTF-8 is refused" {
  assert_refusal invalid-utf8.json
}

@test "non-finite numbers are refused" {
  assert_refusal nonfinite.json
}

@test "boolean counts are refused" {
  assert_refusal boolean-count.json
}

@test "fractional counts are refused" {
  assert_refusal fractional-count.json
}

@test "negative counts are refused" {
  assert_refusal negative-count.json
}

@test "huge exponent counts are refused before integer conversion" {
  assert_refusal huge-exponent.json
}

@test "summary counts must agree with change rows" {
  assert_refusal count-mismatch.json
}

@test "duplicate paths are refused" {
  assert_refusal duplicate-path.json
}

@test "unsorted paths are refused" {
  assert_refusal unsorted-paths.json
}

@test "noncanonical relative paths are refused" {
  assert_refusal invalid-path.json
}

@test "unknown row keys are refused" {
  assert_refusal unknown-row-key.json
}

@test "ADDED rows require null before-side values" {
  assert_refusal added-has-before.json
}

@test "MODIFIED rows require a changed digest or size tuple" {
  assert_refusal modified-identical.json
}

@test "excessive JSON nesting is refused" {
  assert_refusal deep.json
}

@test "input over two MiB is refused" {
  assert_refusal oversized.json
}

@test "a known file size above one MiB is refused" {
  assert_refusal oversized-file-count.json
}

@test "known changed-side bytes above sixteen MiB are refused" {
  assert_refusal oversized-known-side-total.json
}

@test "rendered output over 128 KiB is refused all-or-nothing" {
  assert_refusal output-overflow.json
}

@test "unexpected command arguments refuse without printing help" {
  run --separate-stderr "$FORMATTER" --help < "$FIXTURES/unchanged.json"
  [[ "$status" -eq 2 ]] \
    && [[ -z "$output" ]] \
    && [[ "$stderr" == "INPUT_MANIFEST_DIFF_FORMAT_REFUSED" ]]
}
