#!/usr/bin/env bats

CHECKER="$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"
DECISION_V2="$FIXTURES/decision-record-v2"


@test "DecisionRecord v2 validates a continue choice with counterevidence and reversal conditions" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "DecisionRecord v2 refuses GO when the counterevidence section is absent" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/decision-no-counterevidence --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_COUNTEREVIDENCE_REQUIRED"* ]]
}
@test "DecisionRecord v2 refuses an empty counterevidence list for GO" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/decision-empty-counterevidence --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_COUNTEREVIDENCE_REQUIRED"* ]]
}
@test "DecisionRecord v2 cannot mark authority granted without an authority reference" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/decision-unbound-authority --bundle .
  [ "$status" -eq 1 ]
  [[ "$output" == *"decision.md: E_AUTHORITY_REF_REQUIRED"* ]]
}
@test "complete synthetic artifact examples pass together" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/positive/complete" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SK04 groups duplicate source families and preserves an explicit conflict" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/sk04/positive-grouped-conflict" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SK04 rejects contradictory references collapsed onto one source" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/sk04/negative-collapsed-conflict" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = $'opportunity.md: E_CONFLICT_COUNTEREVIDENCE_REQUIRED\nopportunity.md: E_COUNTEREVIDENCE_DUPLICATE' ]
}

@test "SK04 rejects conflict-group members collapsed onto the supporting side" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/sk04/negative-conflict-same-side" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_CONFLICT_COUNTEREVIDENCE_REQUIRED" ]
}

@test "SK04 rejects a conflict-group counter-source omitted from the claim" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/sk04/negative-conflict-dropped-counterevidence" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_CONFLICT_COUNTEREVIDENCE_REQUIRED" ]
}

@test "SK04 rejects a publication date without a matching raw basis reference" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/sk04/negative-guessed-published-at" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "ledger.md: E_PUBLISHED_AT_BASIS_INVALID" ]
}

@test "SK04 keeps an unavailable source distinct from a completed no-match search" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/sk04/negative-unavailable-as-no-match" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "ledger.md: E_SOURCE_UNAVAILABLE_INVALID" ]
}

@test "KC boundary disclaimer is accepted" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/positive/disclaimer" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "affirmative KC self-label phrasing one is refused" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/positive/disclaimer-self-label-1 --artifact opportunity.md
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}

@test "affirmative KC self-label phrasing two is refused" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/positive/disclaimer-self-label-2 --artifact opportunity.md
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}

@test "affirmative KC self-label phrasing three is refused" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/positive/disclaimer-self-label-3 --artifact opportunity.md
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}

@test "affirmative KC self-label phrasing four is refused" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root $BATS_TEST_DIRNAME/fixtures/positive/disclaimer-self-label-4 --artifact opportunity.md
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}
@test "observed claim without raw ref emits only E_OBSERVED_RAW_REQUIRED" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/negative/5-5" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_OBSERVED_RAW_REQUIRED" ]
}

@test "user-reported evidence cannot be labeled observed" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/negative/5-6" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_USER_REPORTED_AS_OBSERVED" ]
}

@test "accepted protocol cannot consume a draft hypothesis" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/negative/5-7" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "protocol.md: E_INPUT_NOT_READY" ]
}

@test "input reference to a superseded revision emits E_INPUT_SUPERSEDED" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/negative/input-superseded" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "decision.md: E_INPUT_SUPERSEDED" ]
}

@test "draft artifact with observed claim emits E_DRAFT_OBSERVED_CLAIM" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/negative/draft-observed" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_DRAFT_OBSERVED_CLAIM" ]
}

@test "KC self-label fixture is refused" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/negative/ct12-kc-self-label" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}

@test "checker reports usage errors as exit 2" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/positive/complete"
  [ "$status" -eq 2 ]
}

@test "checker refuses an artifact path outside the declared root" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$FIXTURES/positive/complete" --artifact "$CHECKER"
  [ "$status" -eq 2 ]
}

@test "--files validates an explicit valid subset" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --files decision.md ledger.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--files refuses duplicate entries with usage exit" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --files decision.md decision.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate --files entry"* ]]
}

@test "--files refuses a missing entry with usage exit" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --files missing.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --files entry"* ]]
}

@test "--files refuses a parent traversal entry with usage exit" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --files ../decision.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --files entry"* ]]
}

@test "--files refuses an absolute path outside the declared root" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --files "$CHECKER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid --files entry"* ]]
}

@test "--files cannot be combined with --bundle" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --bundle . --files decision.md
  [ "$status" -eq 2 ]
}

@test "--files cannot be combined with --artifact" {
  run python3 "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.py" --root "$DECISION_V2" --artifact decision.md --files decision.md
  [ "$status" -eq 2 ]
}

@test "summary JSON reports a measured known-zero bundle without changing validation exit" {
  run python3 "$CHECKER" --root "$FIXTURES/positive/complete" --bundle . --summary-json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1]); assert x == {"schema":"DatarimProductArtifactValidationSummary/v1","selection_mode":"bundle","result":"PASS","exit_code":0,"diagnostics":{"availability":"MEASURED","value":{"count":0,"counts_by_code":{}}}}' "$output"
}

@test "summary JSON reports fixed structural codes and withholds artifact paths" {
  run python3 "$CHECKER" --root "$FIXTURES/negative/5-5" --bundle . --summary-json
  [ "$status" -eq 1 ]
  [[ "$output" != *"opportunity.md"* ]]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["result"] == "FAIL" and x["exit_code"] == 1 and x["diagnostics"] == {"availability":"MEASURED","value":{"count":1,"counts_by_code":{"E_OBSERVED_RAW_REQUIRED":1}}}' "$output"
}

@test "summary JSON preserves missing-input exit and marks diagnostics unmeasured" {
  run python3 "$CHECKER" --root "$DECISION_V2" --files missing.md --summary-json
  [ "$status" -eq 2 ]
  [[ "$output" != *"missing.md"* ]]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["selection_mode"] == "files" and x["result"] == "NOT_MEASURED" and x["exit_code"] == 2 and x["diagnostics"] == {"availability":"NOT_MEASURED","value":None}' "$output"
}

@test "summary JSON selector modes reflect the selected existing input" {
  run python3 "$CHECKER" --root "$FIXTURES/positive/complete" --artifact opportunity.md --summary-json
  artifact_json_status="$status"
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["selection_mode"] == "artifact" and x["exit_code"] in (0,1)' "$output"
  run python3 "$CHECKER" --root "$FIXTURES/positive/complete" --artifact opportunity.md
  [ "$status" -eq "$artifact_json_status" ]
  run python3 "$CHECKER" --root "$DECISION_V2" --files decision.md ledger.md --summary-json
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["selection_mode"] == "files" and x["result"] == "PASS"' "$output"
}

@test "shell entrypoint forwards the opt-in summary flag" {
  run "$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.sh" --root "$FIXTURES/positive/complete" --bundle . --summary-json
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["schema"] == "DatarimProductArtifactValidationSummary/v1" and x["result"] == "PASS"' "$output"
}

@test "summary JSON measures malformed and non-mapping YAML without returning input content" {
  tmp="$(mktemp -d)"
  python3 - "$FIXTURES/positive/complete/opportunity.md" "$tmp" <<'PY'
import pathlib,sys
source=pathlib.Path(sys.argv[1]).read_text()
target=pathlib.Path(sys.argv[2])
front,tail=source.split('---\n',1)[1].split('\n---\n',1)
(target/'malformed.md').write_text(source.replace('schema_version: product-artifact/1','schema_version: [',1))
(target/'scalar.md').write_text('---\nnot-a-mapping\n---\n'+tail)
PY
  run python3 "$CHECKER" --root "$tmp" --artifact malformed.md --summary-json
  [ "$status" -eq 1 ]
  [[ "$output" != *"schema_version"* ]]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["result"] == "FAIL" and x["diagnostics"]["availability"] == "MEASURED" and x["diagnostics"]["value"]["counts_by_code"] == {"E_YAML_INVALID":1}' "$output"
  run python3 "$CHECKER" --root "$tmp" --artifact scalar.md --summary-json
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["diagnostics"]["value"]["counts_by_code"] == {"E_YAML_INVALID":1}' "$output"
  rm -rf "$tmp"
}

@test "summary JSON preserves duplicate and traversal guards as unmeasured" {
  run python3 "$CHECKER" --root "$DECISION_V2" --files decision.md decision.md --summary-json
  [ "$status" -eq 2 ]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["result"] == "NOT_MEASURED" and x["exit_code"] == 2 and x["diagnostics"]["value"] is None' "$output"
  run python3 "$CHECKER" --root "$DECISION_V2" --files ../decision.md --summary-json
  [ "$status" -eq 2 ]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1].splitlines()[-1]); assert x["result"] == "NOT_MEASURED" and x["exit_code"] == 2 and x["diagnostics"]["value"] is None' "$output"
}

@test "summary JSON withholds symlink and hostile input names" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/sentinel-root"
  cp "$DECISION_V2/decision.md" "$DECISION_V2/ledger.md" "$tmp/sentinel-root/"
  ln -s "$FIXTURES/positive/complete/opportunity.md" "$tmp/sentinel-root/private-name-sentinel.md"
  run python3 "$CHECKER" --root "$tmp/sentinel-root" --bundle . --summary-json
  [ "$status" -eq 1 ]
  [[ "$output" != *"private-name-sentinel"* ]]
  [[ "$output" != *"$tmp"* ]]
  python3 -c 'import json,sys; x=json.loads(sys.argv[1]); c=x["diagnostics"]["value"]["counts_by_code"]; assert x["diagnostics"]["availability"] == "MEASURED" and c.get("E_PATH_SYMLINK") == 1' "$output"
  rm -rf "$tmp"
}
