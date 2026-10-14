#!/usr/bin/env bats

@test "synthetic v2 records drive checker-backed routing, immutable revisions, resume, and red controls" {
  run python3 "${BATS_TEST_DIRNAME}/product-decision-routing.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRANSCRIPT continue: checker=exit0"*"PRODUCT_ROUTE_CONTINUE"* ]]
  [[ "$output" == *"TRANSCRIPT stop:"*"PRODUCT_ROUTE_STOP"* ]]
  [[ "$output" == *"TRANSCRIPT more-evidence:"*"PRODUCT_ROUTE_MORE_EVIDENCE"* ]]
  [[ "$output" == *"r2-stop-over-authorized-r1"*"PRODUCT_ROUTE_STOP"* ]]
  [[ "$output" == *"r2-continue-with-r1-brief"*"PRODUCT_ROUTE_SUPERSEDED"* ]]
  [[ "$output" == *"broken-supersedes-chain"*"PRODUCT_REFUSE_ARTIFACT_INVALID"* ]]
  [[ "$output" == *"PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISSING"*"PRODUCT_REFUSE_SCOPE_AUTHORIZATION_MISMATCH"* ]]
  [[ "$output" == *"PRODUCT_REFUSE_PRODUCT_BRIEF_MISSING"*"PRODUCT_REFUSE_PARENT_CONTRACT_MISMATCH"* ]]
  [[ "$output" == *"writer=exit0; validator=exit0"*"decision_ref-and-supersedes-identical=true"* ]]
  [[ "$output" == *"red-control:"*"detected=true"* ]]
  [[ "$output" == *"sandbox-dr-prd-continue: profile_active"*"execution-map-sha256="*"PRD discovery includes decision digest"* ]]
}
