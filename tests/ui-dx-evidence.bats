#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  ROOT="$BATS_TEST_TMPDIR/repo"
  VALIDATOR="$BATS_TEST_DIRNAME/../dev-tools/check-ui-dx-evidence.py"
  FIXTURE="$BATS_TEST_DIRNAME/ui-dx-evidence-fixture.py"
  mkdir -p "$ROOT/datarim/qa/synthetic"
  git -C "$ROOT" init -q
  git -C "$ROOT" config user.name Fixture
  git -C "$ROOT" config user.email fixture@example.invalid
  printf 'synthetic source pin\n' > "$ROOT/source.txt"
  git -C "$ROOT" add source.txt
  git -C "$ROOT" commit -qm 'synthetic UI and DX validator fixture'
  python3 "$FIXTURE" clean "$ROOT"
}

run_check() {
  run python3 "$VALIDATOR" --root "$ROOT" \
    --evidence "$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
}

run_summary_check() {
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --evidence "$ROOT/datarim/qa/synthetic/ui-dx-evidence.json" \
    --summary-json
}

assert_summary_contract() {
  local json_text="$output"
  python3 - "$json_text" "$@" <<'PY'
import json
import sys

(
    result, exit_code, diagnostic, revision_state, revision,
    digest_state, digest, score_state, score, notes_state, notes,
) = sys.argv[2:]
value = json.loads(sys.argv[1])
assert set(value) == {
    "schema", "result", "exit_code", "diagnostic_codes", "source_revision",
    "evidence_sha256", "lowest_rubric_score", "notes_count",
}
assert value["schema"] == "UIDXEvidenceValidationSummary/v1"
assert value["result"] == result
assert value["exit_code"] == int(exit_code)
assert value["diagnostic_codes"] == ([] if diagnostic == "-" else [diagnostic])
assert value["source_revision"] == {"availability": revision_state, "value": None if revision == "-" else revision}
assert value["evidence_sha256"] == {"availability": digest_state, "value": None if digest == "-" else digest}
assert value["lowest_rubric_score"] == {
    "availability": score_state,
    "value": None if score == "-" else int(score),
}
assert value["notes_count"] == {
    "availability": notes_state,
    "value": None if notes == "-" else int(notes),
}
PY
}

@test "complete synthetic UI and DX evidence passes at exact HEAD" {
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"UI_DX_REVIEW PASS"* ]]
  [[ "$output" == *"lowest_rubric_score=2"* ]]
}

@test "missing UI error state is rejected" {
  python3 "$FIXTURE" missing-ui-error "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_ui_state_error"* ]]
}

@test "missing developer recovery path is rejected" {
  python3 "$FIXTURE" missing-recovery "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_journey_stage_recover"* ]]
}

@test "explicit UI and DX not-applicable results are reported distinctly" {
  python3 "$FIXTURE" not-applicable "$ROOT"
  run_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"UI_DX_REVIEW NOT_APPLICABLE"* ]]
}

@test "adoption statistics are rejected" {
  python3 "$FIXTURE" adoption-statistic "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"prohibited_input"* ]]
}

@test "designer binary dependencies are rejected" {
  python3 "$FIXTURE" designer-binary "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"prohibited_input"* ]]
}

@test "retained phrasing without attribution is rejected" {
  python3 "$FIXTURE" unattributed "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"unattributed_retained_material"* ]]
}

@test "stale source revision is rejected" {
  python3 "$FIXTURE" stale "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale_source_revision"* ]]
}

@test "changed referenced artifact bytes are rejected" {
  python3 "$FIXTURE" artifact-digest-mismatch "$ROOT"
  run_check
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence_digest_mismatch"* ]]
}

@test "design and QA commands consume the fragments without replacing Layer 4h" {
  local design="$BATS_TEST_DIRNAME/../commands/dr-design.md"
  local qa="$BATS_TEST_DIRNAME/../commands/dr-qa.md"
  run grep -F 'skills/frontend-ui/SKILL.md' "$design"
  [ "$status" -eq 0 ]
  run grep -F 'skills/dx-review/SKILL.md' "$qa"
  [ "$status" -eq 0 ]
  run grep -F 'check-ui-dx-evidence.py' "$qa"
  [ "$status" -eq 0 ]
  run grep -F '### Layer 4h — Test-Environment Verification' "$qa"
  [ "$status" -eq 0 ]
  run grep -F 'This check is separate from Layer 4h.' "$qa"
  [ "$status" -eq 0 ]
  run grep -F -- '--summary-json' "$qa"
  [ "$status" -eq 0 ]
  run grep -F 'documentation/reference/ui-dx-evidence-summary.md' "$qa"
  [ "$status" -eq 0 ]
}

@test "summary JSON is deterministic, preserves default output, and leaves inputs unchanged" {
  local before after default_output default_status first_summary revision digest
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  local artifact="$ROOT/datarim/qa/synthetic/run-20261018T170000Z/evidence.txt"
  before=$(sha256sum "$evidence" "$artifact")

  run_check
  default_status="$status"
  default_output="$output"
  revision=$(git -C "$ROOT" rev-parse HEAD)
  digest=$(sha256sum "$evidence" | cut -d' ' -f1)
  [ "$default_status" -eq 0 ]
  [ "$default_output" = "UI_DX_REVIEW PASS source_revision=$revision evidence_sha256=$digest lowest_rubric_score=2" ]

  run_summary_check
  [ "$status" -eq "$default_status" ]
  [ "$stderr" = "" ]
  [[ "$output" != *$'\n'* ]]
  first_summary="$output"
  assert_summary_contract PASS 0 - MEASURED "$revision" MEASURED "$digest" MEASURED 2 MEASURED 0

  run_summary_check
  [ "$status" -eq 0 ]
  [ "$output" = "$first_summary" ]
  after=$(sha256sum "$evidence" "$artifact")
  [ "$before" = "$after" ]
}

@test "summary JSON hashes the exact evidence bytes parsed before a later replacement" {
  python3 - "$VALIDATOR" "$ROOT" <<'PY'
import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import sys

validator_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
evidence_path = root / "datarim/qa/synthetic/ui-dx-evidence.json"
original = evidence_path.read_bytes()
replacement = original.replace(
    b'"schema": "DatarimUiDxEvidence/v1"',
    b'"schema": "DatarimUiDxEvidence/changed"',
    1,
)
assert replacement != original

spec = importlib.util.spec_from_file_location("ui_dx_validator_under_test", validator_path)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
original_validate_ui = validator.validate_ui
replacement_observed = False

def replace_after_load(*args, **kwargs):
    global replacement_observed
    evidence_path.write_bytes(replacement)
    replacement_observed = evidence_path.read_bytes() == replacement
    return original_validate_ui(*args, **kwargs)

validator.validate_ui = replace_after_load
sys.argv = [str(validator_path), "--root", str(root), "--evidence", str(evidence_path), "--summary-json"]
stdout = io.StringIO()
with contextlib.redirect_stdout(stdout):
    exit_code = validator.main()

summary = json.loads(stdout.getvalue())
assert replacement_observed, "the fixture evidence replacement did not occur"
assert exit_code == 0
assert summary["result"] == "PASS"
assert summary["evidence_sha256"] == {
    "availability": "MEASURED",
    "value": hashlib.sha256(original).hexdigest(),
}
assert summary["evidence_sha256"]["value"] != hashlib.sha256(replacement).hexdigest()
PY
}

@test "summary JSON reports NOT_APPLICABLE without inventing a rubric score" {
  python3 "$FIXTURE" not-applicable "$ROOT"
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  local revision digest
  revision=$(git -C "$ROOT" rev-parse HEAD)
  digest=$(sha256sum "$evidence" | cut -d' ' -f1)
  run_summary_check
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  assert_summary_contract NOT_APPLICABLE 0 - MEASURED "$revision" MEASURED "$digest" NOT_MEASURED - MEASURED 0
}

@test "summary JSON preserves typed refusal and marks unvalidated fields NOT_MEASURED" {
  python3 "$FIXTURE" missing-ui-error "$ROOT"
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  local before after default_status revision
  before=$(sha256sum "$evidence")
  revision=$(git -C "$ROOT" rev-parse HEAD)
  run_check
  default_status="$status"
  [ "$default_status" -eq 1 ]

  run_summary_check
  [ "$status" -eq "$default_status" ]
  [ "$stderr" = "" ]
  assert_summary_contract FAIL 1 missing_ui_state_error MEASURED "$revision" NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
  after=$(sha256sum "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON refuses malformed evidence with one fixed diagnostic" {
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  printf '{\n' > "$evidence"
  local before after
  before=$(sha256sum "$evidence")
  run_summary_check
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  assert_summary_contract FAIL 1 invalid_json NOT_MEASURED - NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
  after=$(sha256sum "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON refuses missing evidence without exposing its path" {
  local missing="$ROOT/datarim/qa/synthetic/run-20261018T170001Z/ui-dx-evidence.json"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --evidence "$missing" --summary-json
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"$missing"* ]]
  assert_summary_contract FAIL 1 missing_evidence NOT_MEASURED - NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
}

@test "summary JSON reports current revision and unknown values for a stale evidence refusal" {
  python3 "$FIXTURE" stale "$ROOT"
  local revision
  revision=$(git -C "$ROOT" rev-parse HEAD)
  run_summary_check
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  assert_summary_contract FAIL 1 stale_source_revision MEASURED "$revision" NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
}

@test "summary JSON retains only the earlier validated UI score on later refusal" {
  python3 "$FIXTURE" missing-recovery "$ROOT"
  local revision
  revision=$(git -C "$ROOT" rev-parse HEAD)
  run_summary_check
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  assert_summary_contract FAIL 1 missing_journey_stage_recover MEASURED "$revision" NOT_MEASURED - MEASURED 2 NOT_MEASURED -
}

@test "summary JSON refuses a symlinked evidence path" {
  local evidence="$ROOT/datarim/qa/synthetic/run-20261018T170001Z/ui-dx-evidence.json"
  mkdir -p "${evidence%/*}"
  ln -s ../ui-dx-evidence.json "$evidence"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --evidence "$evidence" --summary-json
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"$evidence"* ]]
  assert_summary_contract FAIL 1 unsafe_evidence_path NOT_MEASURED - NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
}

@test "summary JSON maps a root-resolution exception to a fixed refusal" {
  local unresolved_root="$BATS_TEST_TMPDIR/root-resolution-error"
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  run --separate-stderr python3 - "$VALIDATOR" "$unresolved_root" "$evidence" <<'PY'
import contextlib
import importlib.util
import io
import pathlib
import sys
from unittest.mock import patch

validator_path = pathlib.Path(sys.argv[1])
unresolved_root = pathlib.Path(sys.argv[2])
evidence_path = pathlib.Path(sys.argv[3])
spec = importlib.util.spec_from_file_location("ui_dx_validator_under_test", validator_path)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
original_resolve = pathlib.Path.resolve
resolution_calls = []

def resolve_with_controlled_error(path, strict=False):
    if path == unresolved_root:
        resolution_calls.append(path)
        raise RuntimeError("controlled root-resolution failure")
    return original_resolve(path, strict=strict)

sys.argv = [
    str(validator_path), "--root", str(unresolved_root),
    "--evidence", str(evidence_path), "--summary-json",
]
captured_stdout = io.StringIO()
with patch.object(pathlib.Path, "resolve", resolve_with_controlled_error):
    with contextlib.redirect_stdout(captured_stdout):
        product_exit = validator.main()

assert resolution_calls == [unresolved_root], "the controlled root-resolution failure was not reached exactly once"
assert product_exit == 1, "the production CLI main returned the wrong refusal exit"
sys.stdout.write(captured_stdout.getvalue())
PY
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"$unresolved_root"* ]]
  assert_summary_contract FAIL 1 input_unavailable NOT_MEASURED - NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
}

@test "summary JSON refuses unreadable evidence without leaking filesystem details" {
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  local before after summary_output
  before=$(sha256sum "$evidence")
  chmod 000 "$evidence"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --evidence "$evidence" --summary-json
  local summary_status="$status" summary_stderr="$stderr"
  summary_output="$output"
  chmod 600 "$evidence"
  [ "$summary_status" -eq 1 ]
  [ "$summary_stderr" = "" ]
  [[ "$summary_output" != *"$ROOT"* ]]
  output="$summary_output"
  assert_summary_contract FAIL 1 invalid_json NOT_MEASURED - NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
  after=$(sha256sum "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON hides hostile exception details and path text" {
  python3 - "$ROOT/datarim/qa/synthetic/ui-dx-evidence.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value['HOSTILE /outside/private-note "\u96ea"'] = "do-not-print-this-marker"
path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
PY
  local evidence="$ROOT/datarim/qa/synthetic/ui-dx-evidence.json"
  local before after
  before=$(sha256sum "$evidence")
  run_summary_check
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"do-not-print-this-marker"* ]]
  [[ "$output" != *"/outside/private-note"* ]]
  [[ "$output" != *"雪"* ]]
  assert_summary_contract FAIL 1 unknown_field NOT_MEASURED - NOT_MEASURED - NOT_MEASURED - NOT_MEASURED -
  after=$(sha256sum "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON does not expose valid hostile note content" {
  python3 - "$ROOT/datarim/qa/synthetic/ui-dx-evidence.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
marker = 'private-note-雪 \'"},"result":"PASS","host_path":"/outside/secret'
feature = value["ui"]["features"][0]
feature["id"] = marker
step = feature["storyboard"][0]
step["plan_specifies"] = False
step["gap"] = marker
path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
PY
  run_summary_check
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"private-note-雪"* ]]
  [[ "$output" != *"/outside/secret"* ]]
  assert_summary_contract PASS 0 - MEASURED "$(git -C "$ROOT" rev-parse HEAD)" MEASURED "$(sha256sum "$ROOT/datarim/qa/synthetic/ui-dx-evidence.json" | cut -d' ' -f1)" MEASURED 2 MEASURED 1
}
