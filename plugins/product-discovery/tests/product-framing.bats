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
  run "$CHECKER" --root "$FIXTURES/roleplayed-as-observed" --bundle .
  [ "$status" -eq 1 ]
  [ "$output" = "opportunity.md: E_ROLEPLAY_AS_OBSERVED" ]
}

@test "simulated and synthetic raw origins cannot be promoted to observed" {
  local origin candidate
  for origin in simulated synthetic; do
    candidate="$BATS_TEST_TMPDIR/$origin"
    cp -R "$FIXTURES/roleplayed-as-observed" "$candidate"
    sed -i "s/origin_kind: roleplay/origin_kind: $origin/" "$candidate/ledger.md"
    run "$CHECKER" --root "$candidate" --bundle .
    [ "$status" -eq 1 ]
    [ "$output" = "opportunity.md: E_ROLEPLAY_AS_OBSERVED" ]
  done
}

@test "multilingual input fixture expects English artifact output" {
  run grep -F "produce the OpportunityBrief in English" "$FIXTURES/multilingual-ru-en/case.md"
  [ "$status" -eq 0 ]
  run grep -F "The artifact language remains English." "$FIXTURES/multilingual-ru-en/opportunity.md"
  [ "$status" -eq 0 ]
}
