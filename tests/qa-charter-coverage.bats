#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$BATS_TEST_TMPDIR/repo"
  VALIDATOR="$BATS_TEST_DIRNAME/../dev-tools/check-qa-charter-coverage.py"
  mkdir -p "$ROOT/datarim/qa/example/run-20261018T120000Z"
  git -C "$ROOT" init -q
  git -C "$ROOT" config user.name Fixture
  git -C "$ROOT" config user.email fixture@example.invalid
  printf 'synthetic source pin\n' > "$ROOT/source.txt"
  git -C "$ROOT" add source.txt
  git -C "$ROOT" commit -qm 'synthetic validator fixture'
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" seed "$ROOT"
}

assert_summary_metadata() {
  local expected_verdict="$1" expected_exit="$2" expected_code="$3"
  python3 - "$output" "$expected_verdict" "$expected_exit" "$expected_code" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
verdict, exit_code, diagnostic = sys.argv[2:]
assert set(summary) == {
    "schema", "verdict", "exit_code", "exit_code_meaning",
    "diagnostic_codes", "counts", "checkpoint_linkage",
}
assert summary["schema"] == "DatarimQaCharterCoverageSummary/v1"
assert summary["verdict"] == verdict
assert summary["exit_code"] == int(exit_code)
assert summary["exit_code_meaning"] == ("pass" if exit_code == "0" else "refusal")
assert summary["diagnostic_codes"] == ([] if diagnostic == "none" else [diagnostic])
assert set(summary["counts"]) == {
    "declared_probes", "required_probes", "recorded_probes",
    "missing_required_probes", "optional_unrecorded_probes",
    "checkpoint_transitions",
}
for count in summary["counts"].values():
    assert set(count) == {"available", "value"}
    assert count["available"] is (count["value"] is not None)
PY
}

assert_summary_counts() {
  python3 - "$output" "$1" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
expected = json.loads(sys.argv[2])
assert summary["counts"] == expected
PY
}

@test "complete required charter probes with current immutable-run evidence pass" {
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHARTER_COVERAGE PASS"* ]]
  [[ "$output" == *"checkpoint_linkage=NOT_MEASURED"* ]]
}

@test "relative spelling of the canonical repository root remains accepted" {
  run bash -c 'cd "$1" && exec python3 "$2" --root repo --charter "$3" --evidence "$4"' \
    _ "$BATS_TEST_TMPDIR" "$VALIDATOR" \
    "$ROOT/datarim/qa/example/qa-charter.md" \
    "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHARTER_COVERAGE PASS"* ]]
}

@test "direct symlink spelling of repository root is refused as invalid_root" {
  ln -s "$ROOT" "$BATS_TEST_TMPDIR/root-alias"
  run bash -c 'cd "$1" && exec python3 "$2" --root root-alias --charter "$3" --evidence "$4"' \
    _ "$BATS_TEST_TMPDIR" "$VALIDATOR" \
    "$ROOT/datarim/qa/example/qa-charter.md" \
    "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHARTER_COVERAGE FAIL reason=invalid_root"* ]]
}

@test "explicit null checkpoint_chain is rejected instead of treated as legacy omission" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" null-checkpoint-chain "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid_charter"*"checkpoint_chain must contain boolean required"* ]]
}

@test "explicit null checkpoint_chains is rejected as malformed evidence" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" null-checkpoint-chains "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid_checkpoint_chain"*"checkpoint_chains must be an array"* ]]
}

@test "omitted required probe blocks coverage" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" omit "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_required_probe"* ]]
}

@test "duplicate required fields cannot silently make probes optional" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" duplicate-required "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate_key"* ]]
}

@test "ASCII duplicate evidence key keeps the named duplicate_key refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" duplicate-key-ascii "$ROOT"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = 'CHARTER_COVERAGE FAIL reason=duplicate_key: duplicate JSON object key: duplicate-key' ]
  [ "$stderr" = "" ]
}

@test "valid Unicode duplicate evidence key remains readable in the refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" duplicate-key-unicode "$ROOT"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = 'CHARTER_COVERAGE FAIL reason=duplicate_key: duplicate JSON object key: duplicate-雪' ]
  [ "$stderr" = "" ]
}

@test "duplicate high-surrogate evidence key produces an escaped refusal without traceback" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" duplicate-key-high-surrogate "$ROOT"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = 'CHARTER_COVERAGE FAIL reason=duplicate_key: duplicate JSON object key: \ud800' ]
  [ "$stderr" = "" ]
}

@test "duplicate low-surrogate evidence key produces an escaped refusal without traceback" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" duplicate-key-low-surrogate "$ROOT"
  run --separate-stderr python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = 'CHARTER_COVERAGE FAIL reason=duplicate_key: duplicate JSON object key: \udc00' ]
  [ "$stderr" = "" ]
}

@test "stale source baseline blocks coverage" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" stale "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale_source_revision"* ]]
}

@test "mutable latest alias is rejected as a baseline location" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" mutable "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/latest/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutable_baseline_path"* ]]
}

@test "non-pass required outcome cannot produce coverage pass" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" not-run "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"required_probe_not_pass"* ]]
}

@test "list-valued probe outcome uses the named invalid_outcome refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" invalid-outcome-list "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_outcome: probe returns-result: unsupported outcome" ]
}

@test "object-valued probe outcome uses the named invalid_outcome refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" invalid-outcome-object "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_outcome: probe returns-result: unsupported outcome" ]
}

@test "production CLI refuses a lone surrogate probe id as invalid evidence" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" lone-high-surrogate-probe-id "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_evidence: probe id must be valid UTF-8 text" ]
}

@test "production CLI refuses an unencodable behaviour id with constant invalid charter" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" lone-high-surrogate-behaviour-id "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_charter: behaviour id must be UTF-8 encodable" ]
}

@test "valid Unicode behaviour id keeps ordinary missing-contract refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" unicode-behaviour-id-omitted-contract "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_charter: behaviour behaviour-雪: contract is required" ]
}

@test "valid Unicode undeclared probe id retains unknown_probe refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" unknown-unicode-probe-id "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=unknown_probe: evidence contains undeclared probe undeclared-雪" ]
}

@test "ASCII undeclared probe id retains unknown_probe refusal" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" unknown-probe-id "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [ "$output" = "CHARTER_COVERAGE FAIL reason=unknown_probe: evidence contains undeclared probe undeclared-probe" ]
}

@test "production CLI validates a multi-step hypothesis-linked chain" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" chain "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checkpoint_linkage=PASS transitions=1"* ]]
}

@test "production CLI hashes a valid non-ASCII checkpoint observation as exact UTF-8" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" unicode-scalar-chain "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 0 ] \
    && [[ "$output" == *"CHARTER_COVERAGE PASS"* ]] \
    && [[ "$output" == *"checkpoint_linkage=PASS transitions=1"* ]]
}

@test "production CLI refuses a lone high surrogate as invalid evidence" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" lone-high-surrogate-chain "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ] \
    && [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_evidence: probe returns-result: observed result must be valid UTF-8 text" ]
}

@test "production CLI refuses a lone low surrogate as invalid evidence" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" lone-low-surrogate-chain "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ] \
    && [ "$output" = "CHARTER_COVERAGE FAIL reason=invalid_evidence: probe returns-result: observed result must be valid UTF-8 text" ]
}

@test "required chain missing from current evidence blocks" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" missing-chain "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_checkpoint_chain"* ]]
}

@test "a timestamped attempts list does not satisfy required linkage" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" attempts-only "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing_checkpoint_chain"* ]]
}

@test "stale prior observation pin blocks the chain" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" stale-checkpoint "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale_checkpoint_observation"* ]]
}

@test "dangling next-probe reference blocks the chain" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" dangling-checkpoint "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"out_of_order_checkpoint"* ]]
}

@test "duplicate checkpoint ids block the chain" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" duplicate-checkpoint "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate_checkpoint"* ]]
}

@test "cyclic predecessor relation blocks the chain" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" cyclic-checkpoint "$ROOT"
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid_checkpoint_relation"* ]]
}

@test "legacy charter preserves coverage and reports linkage not measured" {
  run python3 "$VALIDATOR" --root "$ROOT" \
    --charter "$ROOT/datarim/qa/example/qa-charter.md" \
    --evidence "$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checkpoint_linkage=NOT_MEASURED"* ]]
}

@test "Layer 4h adds charter coverage without replacing test-environment checks" {
  local command="$BATS_TEST_DIRNAME/../commands/dr-qa.md"
  run grep -F '#### QA Charter Coverage subcheck — mandatory for every `/dr-qa` task' "$command"
  [ "$status" -eq 0 ]
  run grep -F '### 4h. QA Charter Coverage and Test-Environment Verification' "$command"
  [ "$status" -eq 0 ]
  run grep -c '^### 4h\.' "$command"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run grep -F '### Layer 4h — Test-Environment Verification' "$command"
  [ "$status" -eq 0 ]
  run grep -F 'SKIP` (documentation/framework-only) / `NO-TEST-ENV`' "$command"
  [ "$status" -eq 0 ]
  run grep -F 'check-qa-charter-coverage.py' "$command"
  [ "$status" -eq 0 ]
}

@test "charter template names its owner, five surfaces, outcomes, and evidence pin" {
  local template="$BATS_TEST_DIRNAME/../templates/qa-charter.md"
  for phrase in '"owner":' '"schema": "DatarimQaCharter/v1"' \
    '`browser`' '`api`' '`cli`' '`worker`' '`webhook`' \
    'DatarimQaCharterEvidence/v1' 'charter_sha256' 'source_revision' \
    'run-YYYYMMDDTHHMMSSZ' 'overwrite a prior'; do
    run grep -F "$phrase" "$template"
    [ "$status" -eq 0 ]
  done
}

@test "summary JSON is allowlisted, versioned, byte-preserving, and keeps default output" {
  local before after default_status default_output revision
  local charter="$ROOT/datarim/qa/example/qa-charter.md"
  local evidence="$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  before=$(sha256sum "$charter" "$evidence")

  run python3 "$VALIDATOR" --root "$ROOT" --charter "$charter" --evidence "$evidence"
  default_status="$status"
  default_output="$output"
  revision=$(git -C "$ROOT" rev-parse HEAD)
  [ "$default_status" -eq 0 ]
  [ "$default_output" = "CHARTER_COVERAGE PASS required=2 recorded=2 optional_unrecorded=0 source_revision=$revision checkpoint_linkage=NOT_MEASURED" ]

  run --separate-stderr python3 "$VALIDATOR" --summary-json \
    --root "$ROOT" --charter "$charter" --evidence "$evidence"
  [ "$status" -eq "$default_status" ]
  [ "$stderr" = "" ]
  [[ "$output" != *$'\n'* ]]
  assert_summary_metadata PASS 0 none
  assert_summary_counts '{"declared_probes":{"available":true,"value":2},"required_probes":{"available":true,"value":2},"recorded_probes":{"available":true,"value":2},"missing_required_probes":{"available":true,"value":0},"optional_unrecorded_probes":{"available":true,"value":0},"checkpoint_transitions":{"available":false,"value":null}}'

  after=$(sha256sum "$charter" "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON reports a refused charter with available and unavailable counts" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" omit "$ROOT"
  local before after default_status default_output
  local charter="$ROOT/datarim/qa/example/qa-charter.md"
  local evidence="$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  before=$(sha256sum "$charter" "$evidence")

  run python3 "$VALIDATOR" --root "$ROOT" --charter "$charter" --evidence "$evidence"
  default_status="$status"
  default_output="$output"
  [ "$default_status" -eq 1 ]
  [ "$default_output" = "CHARTER_COVERAGE FAIL reason=missing_required_probe: required probe evidence missing: preserves-state" ]

  run --separate-stderr python3 "$VALIDATOR" --summary-json \
    --root "$ROOT" --charter "$charter" --evidence "$evidence"
  [ "$status" -eq "$default_status" ]
  [ "$stderr" = "" ]
  assert_summary_metadata FAIL 1 missing_required_probe
  assert_summary_counts '{"declared_probes":{"available":true,"value":2},"required_probes":{"available":true,"value":2},"recorded_probes":{"available":true,"value":1},"missing_required_probes":{"available":true,"value":1},"optional_unrecorded_probes":{"available":true,"value":0},"checkpoint_transitions":{"available":false,"value":null}}'

  after=$(sha256sum "$charter" "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON fails unreadable evidence without inventing counts or changing bytes" {
  local before after summary_status summary_output summary_stderr
  local charter="$ROOT/datarim/qa/example/qa-charter.md"
  local evidence="$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  before=$(sha256sum "$charter" "$evidence")
  chmod 000 "$evidence"
  run --separate-stderr python3 "$VALIDATOR" --summary-json \
    --root "$ROOT" --charter "$charter" --evidence "$evidence"
  summary_status="$status"
  summary_output="$output"
  summary_stderr="$stderr"
  chmod 600 "$evidence"
  [ "$summary_status" -eq 1 ]
  [ "$summary_stderr" = "" ]
  output="$summary_output"
  assert_summary_metadata FAIL 1 invalid_evidence
  assert_summary_counts '{"declared_probes":{"available":true,"value":2},"required_probes":{"available":true,"value":2},"recorded_probes":{"available":false,"value":null},"missing_required_probes":{"available":false,"value":null},"optional_unrecorded_probes":{"available":false,"value":null},"checkpoint_transitions":{"available":false,"value":null}}'
  after=$(sha256sum "$charter" "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON refuses malformed evidence and marks later counts unavailable" {
  local before after
  local charter="$ROOT/datarim/qa/example/qa-charter.md"
  local evidence="$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  printf '{\n' > "$evidence"
  before=$(sha256sum "$charter" "$evidence")

  run --separate-stderr python3 "$VALIDATOR" --summary-json \
    --root "$ROOT" --charter "$charter" --evidence "$evidence"
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  assert_summary_metadata FAIL 1 invalid_evidence
  assert_summary_counts '{"declared_probes":{"available":true,"value":2},"required_probes":{"available":true,"value":2},"recorded_probes":{"available":false,"value":null},"missing_required_probes":{"available":false,"value":null},"optional_unrecorded_probes":{"available":false,"value":null},"checkpoint_transitions":{"available":false,"value":null}}'

  after=$(sha256sum "$charter" "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON does not expose valid Unicode or adversarial report strings" {
  python3 - "$ROOT" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
qa = root / "datarim/qa/example"
charter_path = qa / "qa-charter.md"
evidence_path = qa / "run-20261018T120000Z/evidence.json"
marker = 'snow-雪 \'"},"verdict":"PASS","external_path":"/outside/private.txt'
text = charter_path.read_text(encoding="utf-8")
match = re.search(r"(?ms)(^```qa-charter-json\s*\n)(.*?)(^```\s*$)", text)
assert match
charter = json.loads(match.group(2))
charter["owner"] = marker
charter["behaviours"][0]["contract"] = marker
charter_path.write_text(
    text[:match.start(2)] + json.dumps(charter, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    + text[match.end(2):], encoding="utf-8"
)
evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
evidence["charter_sha256"] = hashlib.sha256(charter_path.read_bytes()).hexdigest()
evidence["probes"][0]["observed"] = marker
evidence["probes"][0]["command"] = marker
evidence_path.write_text(json.dumps(evidence, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  local before after marker
  local charter="$ROOT/datarim/qa/example/qa-charter.md"
  local evidence="$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  marker='snow-雪 '\''"},"verdict":"PASS","external_path":"/outside/private.txt'
  before=$(sha256sum "$charter" "$evidence")

  run --separate-stderr python3 "$VALIDATOR" --summary-json \
    --root "$ROOT" --charter "$charter" --evidence "$evidence"
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"snow-雪"* ]]
  [[ "$output" != *"/outside/private.txt"* ]]
  assert_summary_metadata PASS 0 none
  after=$(sha256sum "$charter" "$evidence")
  [ "$before" = "$after" ]
}

@test "summary JSON hides user-controlled text from existing refusal diagnostics" {
  python3 "$BATS_TEST_DIRNAME/qa-charter-fixture.py" unknown-unicode-probe-id "$ROOT"
  local before after
  local charter="$ROOT/datarim/qa/example/qa-charter.md"
  local evidence="$ROOT/datarim/qa/example/run-20261018T120000Z/evidence.json"
  before=$(sha256sum "$charter" "$evidence")

  run --separate-stderr python3 "$VALIDATOR" --summary-json \
    --root "$ROOT" --charter "$charter" --evidence "$evidence"
  [ "$status" -eq 1 ]
  [ "$stderr" = "" ]
  [[ "$output" != *"undeclared-雪"* ]]
  [[ "$output" != *"datarim/qa"* ]]
  assert_summary_metadata FAIL 1 unknown_probe

  after=$(sha256sum "$charter" "$evidence")
  [ "$before" = "$after" ]
}
