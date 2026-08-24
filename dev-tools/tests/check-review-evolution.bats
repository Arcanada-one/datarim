#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # Each Bats test intentionally gets an isolated setup subshell.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    SCRIPT_SOURCE="${REVIEW_EVOLUTION_SCRIPT:-${REPO_ROOT}/dev-tools/check-review-evolution.sh}"
    TEST_FRAMEWORK="${BATS_TEST_TMPDIR}/framework"
    mkdir -p "${TEST_FRAMEWORK}/dev-tools"
    cp "$SCRIPT_SOURCE" "${TEST_FRAMEWORK}/dev-tools/check-review-evolution.sh"
    SCRIPT="${TEST_FRAMEWORK}/dev-tools/check-review-evolution.sh"
    # shellcheck disable=SC2016  # The generated A2 oracle must retain its own shell variables literally.
    printf '%s\n' \
        '#!/bin/bash -p' \
        'set -euo pipefail' \
        'root=""; task=""; stage=""; format=""' \
        'while (($#)); do' \
        '  case "$1" in' \
        '    --root) root="$2"; shift 2 ;;' \
        '    --task) task="$2"; shift 2 ;;' \
        '    --stage) stage="$2"; shift 2 ;;' \
        '    --format) format="$2"; shift 2 ;;' \
        '    *) exit 2 ;;' \
        '  esac' \
        'done' \
        '[[ "$stage" == qa && "$format" == json && -n "$root" ]] || exit 2' \
        'if [[ "$task" != WEB-0001 ]] || ! yq -e '\''.requirements.req-0001.coverage_chain.red_green'\'' "${root}/datarim/receipts/${task}-customer-delivery.yaml" >/dev/null 2>&1; then' \
        '  printf '\''{"decision":"NOT_MET","epic_status":"NOT_MET","findings":["test_a2_rejection"],"stage":"qa","status":"NOT_MET","task":"%s"}\n'\'' "$task"' \
        '  exit 1' \
        'fi' \
        'printf '\''{"decision":"MET","epic_status":"MET","findings":[],"stage":"qa","status":"MET","task":"%s"}\n'\'' "$task"' \
        >"${TEST_FRAMEWORK}/dev-tools/check-customer-delivery.sh"
    chmod +x "${TEST_FRAMEWORK}/dev-tools/check-customer-delivery.sh"
    ROOT="${BATS_TEST_TMPDIR}/consumer"
    TASK_ID='WEB-0001'
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    ARTIFACT_PATH='canon/customer-delivery-review-checklist.md'
    RED_PATH='artifacts/evolution/red-live-evidence-gate.txt'
    GREEN_PATH='artifacts/evolution/green-live-evidence-gate.txt'
    mkdir -p "${ROOT}/datarim/tasks" "${ROOT}/datarim/receipts" \
        "${ROOT}/canon" "${ROOT}/artifacts/evolution" "${ROOT}/artifacts/reviews"
    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    cp "${REPO_ROOT}/templates/review-evolution-template.yaml" "$REVIEW"
    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    yq -i '.requirements.req-0001.acceptance.implementation.code_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" |
      .requirements.req-0001.acceptance.implementation.content_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" |
      .requirements.req-0001.acceptance.disposition = "accepted"' "$REQUIREMENTS"
    printf '%s\n' '# Review checklist revision 2' >"${ROOT}/${ARTIFACT_PATH}"
    printf '%s\n' 'status=failed_as_expected' 'command=review-gate-mutant' >"${ROOT}/${RED_PATH}"
    printf '%s\n' 'status=passed' 'command=review-gate' >"${ROOT}/${GREEN_PATH}"
    printf '%s\n' 'neutral evidence without a verdict marker' >"${ROOT}/artifacts/evolution/neutral.txt"
    printf '%s\n' '{"state":"APPROVED","review_id":"review-0001"}' \
        >"${ROOT}/artifacts/reviews/review-0001-approval.json"
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.name test
    git -C "$ROOT" config user.email test@example.invalid
    git -C "$ROOT" add .
    GIT_AUTHOR_DATE='2026-01-03T15:10:00Z' GIT_COMMITTER_DATE='2026-01-03T15:10:00Z' \
        git -C "$ROOT" commit -q -m 'canon evolution evidence'
    ARTIFACT_REVISION="$(git -C "$ROOT" rev-parse HEAD)"
    ARTIFACT_DIGEST="sha256:$(openssl dgst -sha256 "${ROOT}/${ARTIFACT_PATH}" | awk '{print $NF}')"
    yq -i ".canonical_change.artifact_id = \"${ARTIFACT_PATH}\" |
      .canonical_change.artifact_revision = \"${ARTIFACT_REVISION}\" |
      .canonical_change.digest = \"${ARTIFACT_DIGEST}\" |
      .canonical_change.recorded_at = \"2026-01-03T15:30:00Z\"" "$REVIEW"
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
        "evidence": "artifacts/reviews/review-0001-approval.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T14:56:00Z"
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
          "approved_at": "2026-01-03T14:56:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_missing_evidence'
}

@test "NO_CANON_CHANGE fails without reviewer approval" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/review-0001-approval.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": false,
          "approved_at": "2026-01-03T14:56:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_not_approved'
}

@test "NO_CANON_CHANGE approval must come from the classified finding reviewer" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/review-0001-approval.json",
        "reviewer_approval": {
          "reviewer": "different-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T14:56:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_reviewer_mismatch:independent-reviewer:different-reviewer'
}

@test "forged authored delivery summary cannot substitute for the A2 delivery verdict" {
    yq -i '. = {
      "schema_version": 1,
      "receipt_id": "receipt-0001",
      "parent_links": [
        {"relation": "epic", "id": "epic:web:0000"},
        {"relation": "task", "id": "task:web:0001"}
      ],
      "requirements": {
        "req-0001": {
          "coverage_status": "MET",
          "coverage_chain": {"customer_disposition": {"status": "accepted"}}
        }
      }
    }' "$RECEIPT"
    run_validator
    assert_not_met 'customer_delivery_not_met'
}

@test "canonical evolution requires an immutable existing artifact with its real digest and revision" {
    yq -i '.canonical_change.artifact_id = "canon/missing.md"' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_artifact_missing:ABSENT' || return 1

    cp "${REPO_ROOT}/templates/review-evolution-template.yaml" "$REVIEW"
    yq -i ".canonical_change.artifact_id = \"${ARTIFACT_PATH}\" |
      .canonical_change.artifact_revision = \"2\" |
      .canonical_change.digest = \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"" "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'canonical_change_invalid_revision:ABSENT'* ]] \
        && [[ "$output" == *'canonical_change_digest_mismatch:ABSENT'* ]]
}

@test "canonical evolution rejects path escape and nonexistent red-green evidence" {
    yq -i '.canonical_change.artifact_id = "../outside.md" |
      .canonical_change.enforcement.red_evidence = "artifacts/evolution/missing-red.txt" |
      .canonical_change.enforcement.green_evidence = "artifacts/evolution/missing-green.txt"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'canonical_change_artifact_path_invalid:ABSENT'* ]] \
        && [[ "$output" == *'canonical_change_red_evidence_missing:ABSENT'* ]] \
        && [[ "$output" == *'canonical_change_green_evidence_missing:ABSENT'* ]]
}

@test "canonical evolution requires actual RED and GREEN verdict evidence" {
    yq -i '.canonical_change.enforcement.red_evidence = "artifacts/evolution/neutral.txt"' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_red_evidence_invalid:ABSENT'
}

@test "canonical evolution timestamp is valid and cannot attribute pre-review work post-hoc" {
    yq -i '.canonical_change.recorded_at = "not-a-time"' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_invalid_recorded_at:ABSENT' || return 1

    yq -i '.canonical_change.recorded_at = "2026-01-03T15:30:00Z" |
      .reviewed_at = "2026-01-03T15:20:00Z"' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_post_hoc:ABSENT'
}

@test "NO_CANON_CHANGE cannot self-approve with unauthenticated evidence or time" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "arbitrary prose",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "not-a-time"
        }
      }' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'no_canon_change_evidence_not_authenticated'* ]] \
        && [[ "$output" == *'no_canon_change_approval_not_authenticated'* ]] \
        && [[ "$output" == *'no_canon_change_invalid_approved_at'* ]]
}

@test "CLI task is bound to signed internal task identities and cannot be renamed" {
    local renamed='TALO-0001'
    cp "$REQUIREMENTS" "${ROOT}/datarim/tasks/${renamed}-customer-requirements.yaml"
    cp "$RECEIPT" "${ROOT}/datarim/receipts/${renamed}-customer-delivery.yaml"
    cp "$REVIEW" "${ROOT}/datarim/receipts/${renamed}-review-evolution.yaml"
    TASK_ID="$renamed"
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'customer_delivery_not_met'* ]] \
        && [[ "$output" == *'task_identity_mismatch:TALO-0001'* ]]
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
