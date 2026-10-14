#!/usr/bin/env bats

@test "synthetic v2 decision and brief fixtures drive checked routes and resume safely" {
  run python3 "${BATS_TEST_DIRNAME}/product-decision-routing.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRANSCRIPT continue:"*"PRODUCT_ROUTE_CONTINUE"* ]]
  [[ "$output" == *"TRANSCRIPT stop:"*"PRODUCT_ROUTE_STOP"* ]]
  [[ "$output" == *"TRANSCRIPT more-evidence:"*"PRODUCT_ROUTE_MORE_EVIDENCE"* ]]
  [[ "$output" == *"TRANSCRIPT superseded:"*"PRODUCT_ROUTE_SUPERSEDED"* ]]
  [[ "$output" == *"TRANSCRIPT auto-interrupt:"*"TRANSCRIPT dr-next-resume:"* ]]
  [[ "$output" == *"PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISSING"*"PRODUCT_REFUSE_PARENT_CONTRACT_MISMATCH"* ]]
  [[ "$output" == *"PRODUCT_ROUTE_EVIDENCE_PENDING"*"rejected-is-not-an-outcome"*"E_OUTCOME_INVALID"* ]]
  [[ "$output" == *"red-control:"*"detected=true"* ]]
}
