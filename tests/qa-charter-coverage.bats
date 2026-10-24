#!/usr/bin/env bats

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
