#!/usr/bin/env bats

CHECKER="$BATS_TEST_DIRNAME/../../../dev-tools/check-product-artifact.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/product-framing"

@test "synthetic product-framing outputs pass structural validation" {
  local name
  for name in positive-demand no-demand contradictory-sources unavailable-source multilingual-ru-en; do
    run "$CHECKER" --root "$FIXTURES/$name" --artifact opportunity.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "positive-demand control explicitly continues rather than stopping" {
  run grep -F "Expected skill result: continue inquiry, do not recommend Stop." "$FIXTURES/positive-demand/case.md"
  [ "$status" -eq 0 ]
  run grep -F "next discriminating action" "$FIXTURES/positive-demand/case.md"
  [ "$status" -eq 0 ]
}

@test "no-demand control records a justified stop and counterevidence" {
  run grep -F "recommend Stop for now" "$FIXTURES/no-demand/case.md"
  [ "$status" -eq 0 ]
  run grep -F "record counterevidence" "$FIXTURES/no-demand/case.md"
  [ "$status" -eq 0 ]
  run grep -F "Counterevidence: only two teams were invited" "$FIXTURES/no-demand/opportunity.md"
  [ "$status" -eq 0 ]
}

@test "roleplayed interview mislabeled observed is rejected structurally" {
  run "$CHECKER" --root "$FIXTURES/roleplayed-as-observed" --artifact opportunity.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"E_OBSERVED_RAW_REQUIRED"* ]]
}

@test "multilingual input fixture expects English artifact output" {
  run grep -F "produce the OpportunityBrief in English" "$FIXTURES/multilingual-ru-en/case.md"
  [ "$status" -eq 0 ]
  run grep -F "The artifact language remains English." "$FIXTURES/multilingual-ru-en/opportunity.md"
  [ "$status" -eq 0 ]
}
