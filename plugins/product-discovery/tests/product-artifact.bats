#!/usr/bin/env bats

CHECKER="$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"

@test "complete synthetic artifact examples pass together" {
  run "$CHECKER" --root "$FIXTURES/positive/complete" --bundle .
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "observed claim without raw ref emits only E_OBSERVED_RAW_REQUIRED" {
  run "$CHECKER" --root "$FIXTURES/negative/5-5" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_OBSERVED_RAW_REQUIRED" ]
}

@test "user-reported evidence cannot be labeled observed" {
  run "$CHECKER" --root "$FIXTURES/negative/5-6" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_USER_REPORTED_AS_OBSERVED" ]
}

@test "accepted protocol cannot consume a draft hypothesis" {
  run "$CHECKER" --root "$FIXTURES/negative/5-7" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "protocol.md: E_INPUT_NOT_READY" ]
}

@test "input reference to a superseded revision emits E_INPUT_SUPERSEDED" {
  run "$CHECKER" --root "$FIXTURES/negative/input-superseded" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "decision.md: E_INPUT_SUPERSEDED" ]
}

@test "draft artifact with observed claim emits E_DRAFT_OBSERVED_CLAIM" {
  run "$CHECKER" --root "$FIXTURES/negative/draft-observed" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_DRAFT_OBSERVED_CLAIM" ]
}

@test "KC self-label fixture is refused" {
  run "$CHECKER" --root "$FIXTURES/negative/ct12-kc-self-label" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_KC_SELF_LABEL" ]
}

@test "checker reports usage errors as exit 2" {
  run "$CHECKER" --root "$FIXTURES/positive/complete"
  [ "$status" -eq 2 ]
}

@test "checker refuses an artifact path outside the declared root" {
  run "$CHECKER" --root "$FIXTURES/positive/complete" --artifact "$CHECKER"
  [ "$status" -eq 2 ]
}
