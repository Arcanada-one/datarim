#!/usr/bin/env bats
# Acceptance contracts for the six TUNE-0166 Phase 3 verification helpers.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  TTL="$REPO_ROOT/dev-tools/check-rule-ttl.sh"
  RESTART="$REPO_ROOT/dev-tools/check-auto-restart.sh"
  ESCAPE="$REPO_ROOT/dev-tools/check-escape-false-positives.sh"
  E2E="$REPO_ROOT/dev-tools/e2e-test-orchestrate.sh"
  REGRESSION="$REPO_ROOT/dev-tools/check-orchestrate-regression.sh"
  DOCS="$REPO_ROOT/dev-tools/check-orchestrate-docs.sh"
  PHASE3_ENV="$REPO_ROOT/plugins/dr-orchestrate/tests/helpers/phase3-env.bash"
}

make_regression_fixture() {
  REGRESSION_ROOT="$BATS_TEST_TMPDIR/regression-tests"
  mkdir -p "$REGRESSION_ROOT/nested/deeper"
  printf '%s\n' '#!/usr/bin/env bats' '@test "resolver" { true; }' \
    >"$REGRESSION_ROOT/nested/test_resolver_history.bats"
  printf '%s\n' '#!/usr/bin/env bats' '@test "learned" { true; }' \
    >"$REGRESSION_ROOT/nested/deeper/test_learned_rules.bats"
  FAKE_BATS="$BATS_TEST_TMPDIR/fake-bats"
  cat >"$FAKE_BATS" <<'SH'
#!/usr/bin/env bash
case "${FAKE_BATS_MODE:-pass}" in
  pass) printf '1..2\nok 1 resolver\nok 2 learned\n' ;;
  redis) printf '1..2\nok 1 resolver # skip Redis not available\nok 2 learned\n' ;;
  bad-skip) printf '1..2\nok 1 resolver # skip unrelated dependency\nok 2 learned\n' ;;
esac
SH
  chmod +x "$FAKE_BATS"
  export REGRESSION_ROOT FAKE_BATS
}

run_fixture_regression() {
  env DR_ORCH_REGRESSION_TEST_ROOT="$REGRESSION_ROOT" \
    DR_ORCH_BATS_BIN="$FAKE_BATS" \
    DR_ORCH_REQUIRED_PHASE3_SUITES='test_resolver_history.bats:test_learned_rules.bats' \
    FAKE_BATS_MODE="${FAKE_BATS_MODE:-pass}" \
    "$REGRESSION" --baseline-files 1 --minimum-files 2 --baseline-tests 1 "$@"
}

@test "Phase 3 acceptance helpers are executable" {
  [ -x "$TTL" ] && [ -x "$RESTART" ] && [ -x "$ESCAPE" ] \
    && [ -x "$E2E" ] && [ -x "$REGRESSION" ] && [ -x "$DOCS" ] \
    && [ -x "$PHASE3_ENV" ]
}

@test "TTL helper rejects missing boundary arguments" {
  run "$TTL" --ttl 604800
  [ "$status" -eq 2 ]
}

@test "TTL helper rejects a non-canonical exact boundary" {
  run "$TTL" --ttl 604800 --revalidate 86399
  [ "$status" -eq 1 ]
}

@test "restart helper requires explicit restore expectation" {
  run "$RESTART" --session datarim
  [ "$status" -eq 2 ]
}

@test "escape corpus helper rejects zero iterations" {
  run "$ESCAPE" --iterations 0
  [ "$status" -eq 2 ]
}

@test "e2e helper requires audit and Telegram-mock expectations" {
  run "$E2E" --intent "run dr-plan" --expect-audit
  [ "$status" -eq 2 ]
}

@test "regression helper rejects an invalid skip policy" {
  run "$REGRESSION" --baseline-files 42 --minimum-files 44 --baseline-tests 332 --allow-skip anything
  [ "$status" -eq 2 ]
}

@test "docs helper rejects arguments" {
  run "$DOCS" unexpected
  [ "$status" -eq 2 ]
}

@test "deterministic safe corpus reports zero false positives" {
  run "$ESCAPE" --iterations 100
  [ "$status" -eq 0 ] && [[ "$output" == *"false_positives=0"* ]] \
    && [[ "$output" == *"population_confidence_claim=false"* ]]
}

@test "TTL helper enforces fresh, due, expired, purge, and renewed boundaries" {
  run "$TTL" --ttl 604800 --revalidate 86400
  [ "$status" -eq 0 ] && [[ "$output" == *"sleep_calls=0"* ]]
}

@test "auto-restart helper recovers without replay or unrelated-session mutation" {
  run "$RESTART" --session datarim --expect-restore
  [ "$status" -eq 0 ] && [[ "$output" == *"action_replays=0"* ]]
}

@test "e2e helper reaches the outbound mock without network" {
  run "$E2E" --intent "run dr-plan" --expect-audit --expect-telegram
  [ "$status" -eq 0 ] && [[ "$output" == *"to_mock_notification"* ]]
}

@test "regression helper discovers required suites recursively" {
  make_regression_fixture
  run run_fixture_regression
  [ "$status" -eq 0 ] && [[ "$output" == *"recursive_files=2"* ]]
}

@test "regression helper rejects a recursively discovered zero-test file" {
  make_regression_fixture
  : >"$REGRESSION_ROOT/nested/zero.bats"
  run run_fixture_regression
  [ "$status" -eq 1 ] && [[ "$output" == *"zero-test Bats file"* ]]
}

@test "regression helper rejects an unapproved skip" {
  make_regression_fixture
  export FAKE_BATS_MODE=bad-skip
  run run_fixture_regression --allow-skip redis-unavailable
  [ "$status" -eq 1 ] && [[ "$output" == *"unapproved skip"* ]]
}

@test "regression helper permits only the labelled Redis availability skip" {
  make_regression_fixture
  export FAKE_BATS_MODE=redis
  run run_fixture_regression --allow-skip redis-unavailable
  [ "$status" -eq 0 ]
}

@test "documentation helper validates all six Class B surfaces" {
  run "$DOCS"
  [ "$status" -eq 0 ] && [[ "$output" == *"phase3_docs=6"* ]]
}

@test "documentation helper enforces each required contract per surface" {
  helper="$REPO_ROOT/dev-tools/check-orchestrate-docs.sh"
  grep -qF 'FAIL: $file lacks confirmation contract' "$helper"
  grep -qF 'FAIL: $file lacks seven-day TTL' "$helper"
  grep -qF 'FAIL: $file lacks 24-hour window' "$helper"
  grep -qF 'FAIL: $file lacks re-validation contract' "$helper"
  grep -qF 'FAIL: $file lacks hard-gate contract' "$helper"
}
