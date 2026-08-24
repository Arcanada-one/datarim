#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    SCRIPT="${REVIEW_EVOLUTION_SCRIPT:-${REPO_ROOT}/dev-tools/check-review-evolution.sh}"
    ROOT="${BATS_TEST_TMPDIR}/consumer"
    TASK_ID='TALO-0001'
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    mkdir -p "${ROOT}/datarim/receipts"
    cp "${REPO_ROOT}/templates/review-evolution-template.yaml" "$REVIEW"
    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
}

run_validator() {
    run "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --format json
}

assert_not_met() {
    local expected="$1"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'"status":"NOT_MET"'* ]] \
        && [[ "$output" == *"${expected}"* ]]
}

@test "all five canon-changing classifications are accepted with evolution and a red-capable check" {
    local classification
    for classification in ABSENT WEAK STALE MIS_SCOPED NOT_BOUND; do
        yq -i ".classification = \"${classification}\"" "$REVIEW"
        run_validator
        [ "$status" -eq 0 ] \
            && [[ "$output" == *'"classification":"'"${classification}"'"'* ]] \
            && [[ "$output" == *'"status":"MET"'* ]] || return 1
    done
}

@test "each canon-changing classification fails without artifact evolution" {
    local classification
    for classification in ABSENT WEAK STALE MIS_SCOPED NOT_BOUND; do
        cp "${REPO_ROOT}/templates/review-evolution-template.yaml" "$REVIEW"
        yq -i ".classification = \"${classification}\" | del(.canonical_change)" "$REVIEW"
        run_validator
        assert_not_met "classification_requires_canonical_change:${classification}" || return 1
    done
}

@test "canon-changing classification fails without a red-capable check" {
    yq -i '.canonical_change.enforcement.red_capable = false' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_not_red_capable:ABSENT'
}

@test "canon-changing classification fails without red evidence" {
    yq -i '.canonical_change.enforcement.red_evidence = ""' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_missing_red_evidence:ABSENT'
}

@test "canon-changing classification requires a concrete artifact revision and distinct red-green evidence" {
    yq -i '.canonical_change.change_kind = "OTHER" |
      .canonical_change.digest = "not-a-digest" |
      .canonical_change.enforcement.green_evidence = .canonical_change.enforcement.red_evidence' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'canonical_change_invalid_kind:ABSENT'* ]] \
        && [[ "$output" == *'canonical_change_invalid_digest:ABSENT'* ]] \
        && [[ "$output" == *'canonical_change_red_green_evidence_not_distinct:ABSENT'* ]]
}

@test "NO_CANON_CHANGE is accepted only with evidence and reviewer approval" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "The finding is product-specific and does not expose a reusable canon gap.",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:30:00Z"
        }
      }' "$REVIEW"
    run_validator
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'"classification":"NO_CANON_CHANGE"'* ]] \
        && [[ "$output" == *'"status":"MET"'* ]]
}

@test "NO_CANON_CHANGE fails without evidence" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:30:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_missing_evidence'
}

@test "NO_CANON_CHANGE fails without reviewer approval" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "No reusable canon gap was found.",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": false,
          "approved_at": "2026-01-03T15:30:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_not_approved'
}

@test "NO_CANON_CHANGE approval must come from the classified finding reviewer" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "No reusable canon gap was found.",
        "reviewer_approval": {
          "reviewer": "different-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:30:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_reviewer_mismatch:independent-reviewer:different-reviewer'
}

@test "evolution alone cannot close a product Requirement" {
    yq -i '.requirements.req-0001.coverage_status = "NOT_MET" |
      .requirements.req-0001.missing_edges = ["live_evidence"]' "$RECEIPT"
    run_validator
    assert_not_met 'product_requirement_not_delivered:req-0001'
}

@test "review requirement and receipt must be bound to the product fix" {
    yq -i '.product_fix.requirement_id = "req-9999" |
      .product_fix.delivery_receipt_id = "receipt-9999"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'product_fix_requirement_mismatch:req-0001:req-9999'* ]] \
        && [[ "$output" == *'product_fix_receipt_mismatch:receipt-0001:receipt-9999'* ]]
}

@test "review delivery receipt must be the canonical product delivery receipt" {
    yq -i '.delivery_receipt_id = "receipt-9999" |
      .product_fix.delivery_receipt_id = "receipt-9999"' "$REVIEW"
    run_validator
    assert_not_met 'review_receipt_mismatch:receipt-0001:receipt-9999'
}

@test "review parent links must bind the requirement and delivery receipt" {
    yq -i '.parent_links |= map(select(.relation != "requirement" and .relation != "delivery_receipt"))' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing_parent_link:requirement:req-0001'* ]] \
        && [[ "$output" == *'missing_parent_link:delivery_receipt:receipt-0001'* ]]
}

@test "review parent links inherit every product epic and task" {
    yq -i '.parent_links |= map(select(.relation != "epic" and .relation != "task"))' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing_parent_link:epic:epic:web:0000'* ]] \
        && [[ "$output" == *'missing_parent_link:task:task:web:0001'* ]]
}

@test "unknown classification fails closed" {
    yq -i '.classification = "OTHER"' "$REVIEW"
    run_validator
    assert_not_met 'invalid_classification:OTHER'
}

@test "usage and missing artifacts are configuration errors" {
    run "$SCRIPT" --root "$ROOT" --format json
    [ "$status" -eq 2 ] \
        && [[ "$output" == *'"status":"ERROR"'* ]] \
        && [[ "$output" == *'invalid_usage'* ]] || return 1

    rm -f "$REVIEW"
    run_validator
    [ "$status" -eq 2 ] \
        && [[ "$output" == *'missing_artifact:review_evolution'* ]]
}
