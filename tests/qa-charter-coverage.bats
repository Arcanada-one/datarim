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
