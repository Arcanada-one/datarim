#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
set -o pipefail

setup() {
  umask 077
  WORK="$BATS_TEST_TMPDIR/saved-manifest-workflow"
  BEFORE_ROOT="$WORK/before-root"
  AFTER_ROOT="$WORK/after-root"
  mkdir -m 700 -p -- "$BEFORE_ROOT" "$AFTER_ROOT"
  printf 'before bytes\n' >"$BEFORE_ROOT/alpha.txt"
  printf 'same bytes\n' >"$BEFORE_ROOT/shared.txt"
  printf 'after bytes\n' >"$AFTER_ROOT/alpha.txt"
  printf 'same bytes\n' >"$AFTER_ROOT/shared.txt"
  printf 'new bytes\n' >"$AFTER_ROOT/new.txt"

  HASH="$BATS_TEST_DIRNAME/../dev-tools/hash-cli-inputs.py"
  SELECT="$BATS_TEST_DIRNAME/../dev-tools/select-cli-input-manifest.py"
  MERGE="$BATS_TEST_DIRNAME/../dev-tools/merge-cli-input-manifests.py"
  COMPARE="$BATS_TEST_DIRNAME/../dev-tools/compare-cli-input-manifests.py"
  VERIFY="$BATS_TEST_DIRNAME/../dev-tools/verify-cli-input-manifest.py"
  FORMAT_VERIFY="$BATS_TEST_DIRNAME/../dev-tools/format-input-verification.py"
  FORMAT_DIFF="$BATS_TEST_DIRNAME/../dev-tools/format-cli-input-manifest-diff.py"
  MANIFEST_SCHEMA="$BATS_TEST_DIRNAME/../documentation/reference/schemas/cli-input-manifest.v1.schema.json"
  DIFF_SCHEMA="$BATS_TEST_DIRNAME/../documentation/reference/schemas/cli-input-manifest-diff.v1.schema.json"
  VERIFICATION_SCHEMA="$BATS_TEST_DIRNAME/../documentation/reference/schemas/cli-input-manifest-verification.v1.schema.json"
}

validate_schema() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
from jsonschema import Draft202012Validator

with open(sys.argv[1], encoding="utf-8") as stream:
    schema = json.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    instance = json.load(stream)
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(instance)
PY
}

@test "saved manifests flow through selection merge comparison verification and text" {
  run --separate-stderr "$HASH" --root "$BEFORE_ROOT" --file alpha.txt --file shared.txt
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/before.json"
  validate_schema "$MANIFEST_SCHEMA" "$WORK/before.json"

  run --separate-stderr "$HASH" --root "$AFTER_ROOT" --file alpha.txt --file shared.txt --file new.txt
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/after.json"
  validate_schema "$MANIFEST_SCHEMA" "$WORK/after.json"

  run --separate-stderr "$SELECT" --file shared.txt <"$WORK/before.json"
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/before-selected.json"
  validate_schema "$MANIFEST_SCHEMA" "$WORK/before-selected.json"

  run --separate-stderr "$SELECT" --file new.txt <"$WORK/after.json"
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/after-selected.json"
  validate_schema "$MANIFEST_SCHEMA" "$WORK/after-selected.json"

  python3 - "$WORK/before-selected.json" "$WORK/after-selected.json" >"$WORK/merge-input.json" <<'PY'
import json
import sys

values = []
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as stream:
        values.append(json.load(stream))
json.dump(values, sys.stdout, ensure_ascii=True, separators=(",", ":"))
sys.stdout.write("\n")
PY
  run --separate-stderr "$MERGE" <"$WORK/merge-input.json"
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/merged.json"
  validate_schema "$MANIFEST_SCHEMA" "$WORK/merged.json"
  python3 - "$WORK/merged.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
assert value["result"] == "COMPLETE"
assert [row["relative_path"] for row in value["files"]] == ["new.txt", "shared.txt"]
PY

  run --separate-stderr "$COMPARE" --before "$WORK/before.json" --after "$WORK/after.json"
  [ "$status" -eq 1 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/diff.json"
  validate_schema "$DIFF_SCHEMA" "$WORK/diff.json"
  python3 - "$WORK/diff.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
assert value["result"] == "CHANGED" and value["exit_code"] == 1
assert (value["added_count"], value["removed_count"], value["modified_count"]) == (1, 0, 1)
PY

  run --separate-stderr "$VERIFY" --root "$AFTER_ROOT" <"$WORK/after.json"
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  printf '%s\n' "$output" >"$WORK/verification.json"
  validate_schema "$VERIFICATION_SCHEMA" "$WORK/verification.json"

  run --separate-stderr "$FORMAT_VERIFY" <"$WORK/verification.json"
  [ "$status" -eq 0 ] && [ -z "$stderr" ]
  [[ "$output" == *"Input verification result: MATCHED"* ]]
  printf '%s\n' "$output" >"$WORK/verification.txt"

  run --separate-stderr "$FORMAT_DIFF" <"$WORK/diff.json"
  [ "$status" -eq 1 ] && [ -z "$stderr" ]
  [[ "$output" == *"Input manifest difference: CHANGED"* ]]
  [[ "$output" == *"Counts: added=1 removed=0 modified=1 (MEASURED)"* ]]
}
