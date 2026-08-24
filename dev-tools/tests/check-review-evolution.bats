#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # Each Bats test intentionally gets an isolated setup subshell.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    SCRIPT_SOURCE="${REVIEW_EVOLUTION_SCRIPT:-${REPO_ROOT}/dev-tools/check-review-evolution.sh}"
    TEST_FRAMEWORK="${BATS_TEST_TMPDIR}/framework"
    mkdir -p "${TEST_FRAMEWORK}/dev-tools" "${TEST_FRAMEWORK}/config"
    cp "$SCRIPT_SOURCE" "${TEST_FRAMEWORK}/dev-tools/check-review-evolution.sh"
    cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
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
        'if [[ -f "$root/.a2-config-error" ]]; then' \
        '  printf '\''{"decision":"ERROR","findings":["missing_dependency:test-fixture"],"stage":"qa","status":"ERROR","task":"%s"}\n'\'' "$task"' \
        '  exit 2' \
        'fi' \
        'if [[ -f "$root/.a2-malformed" ]]; then' \
        '  printf '\''not-json\n'\''' \
        '  exit 0' \
        'fi' \
        'if [[ -f "$root/.a2-not-met" ]]; then' \
        '  printf '\''{"decision":"NOT_MET","epic_status":"NOT_MET","findings":["test_semantic_gap"],"stage":"qa","status":"NOT_MET","task":"%s"}\n'\'' "$task"' \
        '  exit 1' \
        'fi' \
        'if [[ -f "$root/.a2-hang" ]]; then' \
        "  (trap '' TERM; exec /bin/sleep 120) &" \
        '  printf '\''%s\n'\'' "$!" >"$root/.a2-descendant.pid"' \
        '  wait' \
        'fi' \
        'if [[ "$task" != WEB-0001 ]] || ! yq -e '\''.requirements.req-0001.coverage_chain.red_green'\'' "${root}/datarim/receipts/${task}-customer-delivery.yaml" >/dev/null 2>&1; then' \
        '  printf '\''{"decision":"NOT_MET","epic_status":"NOT_MET","findings":["test_a2_rejection"],"stage":"qa","status":"NOT_MET","task":"%s"}\n'\'' "$task"' \
        '  exit 1' \
        'fi' \
        'printf '\''{"decision":"MET","epic_status":"MET","findings":[],"stage":"qa","status":"MET","task":"%s"}\n'\'' "$task"' \
        >"${TEST_FRAMEWORK}/dev-tools/check-customer-delivery.sh"
    chmod +x "${TEST_FRAMEWORK}/dev-tools/check-customer-delivery.sh"
    DECISION_PRIVATE_KEY="${BATS_TEST_TMPDIR}/decision-private.pem"
    openssl genpkey -algorithm ED25519 -out "$DECISION_PRIVATE_KEY" >/dev/null 2>&1
    DECISION_PUBLIC_KEY="$(openssl pkey -in "$DECISION_PRIVATE_KEY" -pubout -outform DER 2>/dev/null \
        | tail -c 32 | openssl base64 -A)"
    yq -i ".\"x-datarim-signature-contract\".key_resolution.bundled_registry.entries[] |=
      (select(.key_id == \"key-operator-0001\").public_key = \"${DECISION_PUBLIC_KEY}\")" \
        "${TEST_FRAMEWORK}/config/customer-requirement.schema.json"
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
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.name test
    git -C "$ROOT" config user.email test@example.invalid
    git -C "$ROOT" add datarim
    GIT_AUTHOR_DATE='2026-01-03T14:50:00Z' GIT_COMMITTER_DATE='2026-01-03T14:50:00Z' \
        git -C "$ROOT" commit -q -m 'pre-evolution delivery records'
    printf '%s\n' '# Review checklist revision 2' >"${ROOT}/${ARTIFACT_PATH}"
    printf '%s\n' 'status=failed_as_expected' 'command=review-gate-mutant' >"${ROOT}/${RED_PATH}"
    printf '%s\n' 'status=passed' 'command=review-gate' >"${ROOT}/${GREEN_PATH}"
    printf '%s\n' 'neutral evidence without a verdict marker' >"${ROOT}/artifacts/evolution/neutral.txt"
    printf '%s\n' '{"state":"APPROVED","review_id":"review-0001"}' \
        >"${ROOT}/artifacts/reviews/review-0001-approval.json"
    printf '%s\n' 'attacker-controlled unsigned evidence' >"${ROOT}/attacker-evidence"
    git -C "$ROOT" add .
    GIT_AUTHOR_DATE='2026-01-03T15:10:00Z' GIT_COMMITTER_DATE='2026-01-03T15:10:00Z' \
        git -C "$ROOT" commit -q -m 'canon evolution evidence'
    ARTIFACT_REVISION="$(git -C "$ROOT" rev-parse HEAD)"
    ARTIFACT_DIGEST="sha256:$(openssl dgst -sha256 "${ROOT}/${ARTIFACT_PATH}" | awk '{print $NF}')"
    yq -i ".canonical_change.artifact_id = \"${ARTIFACT_PATH}\" |
      .canonical_change.change_kind = \"NEW_ARTIFACT\" |
      .canonical_change.artifact_revision = \"${ARTIFACT_REVISION}\" |
      .canonical_change.digest = \"${ARTIFACT_DIGEST}\" |
      .canonical_change.recorded_at = \"2026-01-03T15:30:00Z\"" "$REVIEW"
}

write_signed_no_canon_decision() {
    local reviewer='independent-reviewer'
    local approved_at='2026-01-03T15:15:00Z'
    local finding_evidence_ref='artifacts/reviews/review-0001-approval.json'
    local originating_review_digest="${DECISION_ORIGIN_DIGEST:-sha256:89ad08914c519c6154801fd4a70752e6edbd35303acc0555b42bd3c36b629235}"
    local originating_review_observed_at="${DECISION_ORIGIN_OBSERVED_AT:-2026-01-03T14:55:00Z}"
    local decision_path='artifacts/reviews/no-canon-change-decision.json'
    local canonical_payload="${BATS_TEST_TMPDIR}/no-canon-payload.json"
    local signature_file="${BATS_TEST_TMPDIR}/no-canon-signature.bin"
    local payload_digest signature
    jq -n --arg task "$TASK_ID" --arg reviewer "$reviewer" \
        --arg approved_at "$approved_at" --arg evidence_ref "$finding_evidence_ref" \
        --arg decision_ref "$decision_path" --arg origin_digest "$originating_review_digest" \
        --arg origin_observed_at "$originating_review_observed_at" '{
          schema_version: 1,
          decision: "NO_CANON_CHANGE",
          task_id: $task,
          requirement_id: "req-0001",
          delivery_receipt_id: "receipt-0001",
          originating_review_id: "review-0001",
          originating_review_digest: $origin_digest,
          originating_review_observed_at: $origin_observed_at,
          reviewer: $reviewer,
          approved: true,
          approved_at: $approved_at,
          finding_evidence_ref: $evidence_ref,
          decision_evidence_ref: $decision_ref,
          authority_id: "authority-operator-0001",
          authority_role: "OPERATOR",
          algorithm: "ED25519",
          key_id: "key-operator-0001"
        }' >"${ROOT}/${decision_path}"
    printf '%s' "$(jq -cS . "${ROOT}/${decision_path}")" >"$canonical_payload"
    payload_digest="sha256:$(openssl dgst -sha256 "$canonical_payload" | awk '{print $NF}')"
    openssl pkeyutl -sign -inkey "$DECISION_PRIVATE_KEY" -rawin \
        -in "$canonical_payload" -out "$signature_file"
    signature="ed25519:$(openssl base64 -A -in "$signature_file")"
    yq -i ".payload_digest = \"${payload_digest}\" | .signature = \"${signature}\"" \
        "${ROOT}/${decision_path}"
    git -C "$ROOT" add "$decision_path"
    GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit -q -m 'signed no-canon decision'
    printf '%s\n' "$decision_path"
}

reseal_primary_review_digest() {
    local canonical_review_payload review_digest
    canonical_review_payload="$(yq -o=json '.originating_review_inventory[0]' "$REVIEW" \
      | jq -cS '{review_id, requirement_id, delivery_receipt_id, reviewer, review_ref,
          state, observed_at, evidence_ref}')"
    review_digest="sha256:$(printf '%s' "$canonical_review_payload" | openssl dgst -sha256 \
        | awk '{print $NF}')"
    yq -i ".originating_review.review_digest = \"${review_digest}\" |
      .originating_review.authority_approval.approved_digest = \"${review_digest}\" |
      .originating_review_inventory[0].review_digest = \"${review_digest}\" |
      .originating_review_inventory[0].authority_approval.approved_digest = \"${review_digest}\"" \
        "$REVIEW"
    printf '%s\n' "$review_digest"
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
    write_signed_no_canon_decision >/dev/null
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
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
          "approved_at": "2026-01-03T13:01:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_missing_evidence'
}

@test "NO_CANON_CHANGE fails without reviewer approval" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "operator-visual-acceptance-0001",
        "reviewer_approval": {
          "reviewer": "authority-operator-0001",
          "approved": false,
          "approved_at": "2026-01-03T13:01:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_not_approved'
}

@test "NO_CANON_CHANGE approval must come from the authenticated originating reviewer" {
    write_signed_no_canon_decision >/dev/null
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "different-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_reviewer_mismatch:independent-reviewer:different-reviewer'
}

@test "NO_CANON_CHANGE cannot authenticate itself by mutating both unsigned review copies" {
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .originating_review.evidence_ref = "attacker-evidence" |
      .originating_review.authority_approval.approved_at = "2026-01-03T15:45:00Z" |
      .originating_review.review_digest = "sha256:7777777777777777777777777777777777777777777777777777777777777777" |
      .originating_review.authority_approval.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" |
      .no_canon_change = {
        "evidence": "attacker-evidence",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:45:00Z"
        }
      }' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'no_canon_change_decision_not_authenticated'* ]]
}

@test "NO_CANON_CHANGE rejects a tampered signed decision payload" {
    write_signed_no_canon_decision >/dev/null
    yq -i '.reviewer = "attacker"' "${ROOT}/artifacts/reviews/no-canon-change-decision.json"
    git -C "$ROOT" add artifacts/reviews/no-canon-change-decision.json
    GIT_AUTHOR_DATE='2026-01-03T15:21:00Z' GIT_COMMITTER_DATE='2026-01-03T15:21:00Z' \
        git -C "$ROOT" commit -q -m 'tamper decision payload'
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_decision_not_authenticated'
}

@test "NO_CANON_CHANGE rejects a forged decision signature" {
    write_signed_no_canon_decision >/dev/null
    yq -i '.signature = "ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="' \
        "${ROOT}/artifacts/reviews/no-canon-change-decision.json"
    git -C "$ROOT" add artifacts/reviews/no-canon-change-decision.json
    GIT_AUTHOR_DATE='2026-01-03T15:21:00Z' GIT_COMMITTER_DATE='2026-01-03T15:21:00Z' \
        git -C "$ROOT" commit -q -m 'forge decision signature'
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_decision_not_authenticated'
}

@test "NO_CANON_CHANGE rejects a forged decision payload digest" {
    write_signed_no_canon_decision >/dev/null
    yq -i '.payload_digest = "sha256:7777777777777777777777777777777777777777777777777777777777777777"' \
        "${ROOT}/artifacts/reviews/no-canon-change-decision.json"
    git -C "$ROOT" add artifacts/reviews/no-canon-change-decision.json
    GIT_AUTHOR_DATE='2026-01-03T15:21:00Z' GIT_COMMITTER_DATE='2026-01-03T15:21:00Z' \
        git -C "$ROOT" commit -q -m 'forge decision digest'
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_decision_not_authenticated'
}

@test "NO_CANON_CHANGE rejects a backward-time inventory mutation preserving the signed envelope" {
    write_signed_no_canon_decision >/dev/null
    yq -i '.originating_review_inventory[0].observed_at = "2020-01-03T14:55:00Z" |
      .classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
        }
      }' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'originating_review_digest_mismatch:review-0001'* ]] \
        && [[ "$output" == *'no_canon_change_decision_not_authenticated'* ]]
}

@test "NO_CANON_CHANGE signed envelope pins the originating review observation time" {
    local changed_review_digest
    yq -i '.originating_review.observed_at = "2020-01-03T14:55:00Z" |
      .originating_review_inventory[0].observed_at = "2020-01-03T14:55:00Z"' "$REVIEW"
    changed_review_digest="$(reseal_primary_review_digest)"
    DECISION_ORIGIN_DIGEST="$changed_review_digest" \
      DECISION_ORIGIN_OBSERVED_AT='2026-01-03T14:55:00Z' \
      write_signed_no_canon_decision >/dev/null
    yq -i '.classification = "NO_CANON_CHANGE" |
      del(.canonical_change) |
      .no_canon_change = {
        "evidence": "artifacts/reviews/no-canon-change-decision.json",
        "reviewer_approval": {
          "reviewer": "independent-reviewer",
          "approved": true,
          "approved_at": "2026-01-03T15:15:00Z"
        }
      }' "$REVIEW"
    run_validator
    assert_not_met 'no_canon_change_decision_not_authenticated'
}

@test "canonical evolution rejects an originating review time with a stale declared digest" {
    yq -i '.originating_review_inventory[0].observed_at = "2020-01-03T14:55:00Z"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'originating_review_digest_mismatch:review-0001'* ]] \
        && [[ "$output" == *'canonical_change_review_time_not_authenticated:ABSENT'* ]]
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

@test "A2 configuration ERROR remains exit 2 with its validated finding" {
    : >"${ROOT}/.a2-config-error"
    run_validator
    [ "$status" -eq 2 ] \
        && [[ "$output" == *'"status":"ERROR"'* ]] \
        && [[ "$output" == *'customer_delivery:missing_dependency:test-fixture'* ]]
}

@test "malformed A2 output fails closed as a result-contract ERROR" {
    : >"${ROOT}/.a2-malformed"
    run_validator
    [ "$status" -eq 2 ] \
        && [[ "$output" == *'"status":"ERROR"'* ]] \
        && [[ "$output" == *'customer_delivery_result_contract_invalid'* ]]
}

@test "A2 semantic NOT_MET remains exit 1" {
    : >"${ROOT}/.a2-not-met"
    run_validator
    assert_not_met 'customer_delivery_not_met'
}

@test "total deadline kills and reaps a hanging A2 process group" {
    local start end elapsed descendant_pid
    sed -i 's/VALIDATION_TOTAL_TIMEOUT_SECONDS = 20/VALIDATION_TOTAL_TIMEOUT_SECONDS = 1/' \
        "$SCRIPT"
    : >"${ROOT}/.a2-hang"
    start="$(python3 -c 'import time; print(time.perf_counter())')"
    run_validator
    end="$(python3 -c 'import time; print(time.perf_counter())')"
    elapsed="$(python3 -c "print(${end} - ${start})")"
    [ "$status" -eq 2 ] \
        && [[ "$output" == *'"status":"ERROR"'* ]] \
        && [[ "$output" == *'validation_resource_limit:deadline'* ]] \
        && awk "BEGIN { exit !(${elapsed} < 5.0) }" \
        && [ -s "${ROOT}/.a2-descendant.pid" ] || return 1
    descendant_pid="$(<"${ROOT}/.a2-descendant.pid")"
    for _ in {1..50}; do
        if ! kill -0 "$descendant_pid" 2>/dev/null; then
            return 0
        fi
        /bin/sleep 0.02
    done
    run kill -0 "$descendant_pid"
    if [ "$status" -eq 0 ]; then
        /bin/kill -KILL "$descendant_pid" 2>/dev/null || true
    fi
    [ "$status" -ne 0 ]
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

@test "canonical evolution rejects a detached revision that is not an ancestor of bound HEAD" {
    local empty_tree detached_parent detached_child current_tree
    empty_tree="$(printf '' | git -C "$ROOT" mktree)"
    detached_parent="$(printf '%s\n' 'detached parent' | env \
        GIT_AUTHOR_DATE='2026-01-03T15:01:00Z' GIT_COMMITTER_DATE='2026-01-03T15:01:00Z' \
        git -C "$ROOT" commit-tree "$empty_tree")"
    current_tree="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
    detached_child="$(printf '%s\n' 'detached evolution' | env \
        GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit-tree "$current_tree" -p "$detached_parent")"
    yq -i ".canonical_change.artifact_revision = \"${detached_child}\"" "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_revision_not_ancestor:ABSENT'
}

@test "ARTIFACT_REVISION rejects a no-op commit whose artifact blob is unchanged" {
    local noop tree parent
    parent="$(git -C "$ROOT" rev-parse HEAD)"
    tree="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
    noop="$(printf '%s\n' 'no-op evolution' | env \
        GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit-tree "$tree" -p "$parent")"
    git -C "$ROOT" update-ref HEAD "$noop"
    yq -i ".canonical_change.change_kind = \"ARTIFACT_REVISION\" |
      .canonical_change.artifact_revision = \"${noop}\"" "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_artifact_unchanged:ABSENT'
}

@test "ARTIFACT_REVISION rejects a mode-only commit whose artifact blob is unchanged" {
    git -C "$ROOT" update-index --chmod=+x "$ARTIFACT_PATH"
    GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit -q -m 'change artifact mode only'
    ARTIFACT_REVISION="$(git -C "$ROOT" rev-parse HEAD)"
    yq -i ".canonical_change.change_kind = \"ARTIFACT_REVISION\" |
      .canonical_change.artifact_revision = \"${ARTIFACT_REVISION}\"" "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_artifact_unchanged:ABSENT'
}

@test "canonical evolution fails closed on merge revisions" {
    local tree first_parent other_parent merge_revision
    first_parent="$(git -C "$ROOT" rev-parse HEAD)"
    tree="$(git -C "$ROOT" rev-parse 'HEAD^{tree}')"
    other_parent="$(printf '%s\n' 'other parent' | env \
        GIT_AUTHOR_DATE='2026-01-03T15:05:00Z' GIT_COMMITTER_DATE='2026-01-03T15:05:00Z' \
        git -C "$ROOT" commit-tree "$tree" -p "$(git -C "$ROOT" rev-parse HEAD^)")"
    merge_revision="$(printf '%s\n' 'merge evolution' | env \
        GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit-tree "$tree" -p "$first_parent" -p "$other_parent")"
    git -C "$ROOT" update-ref HEAD "$merge_revision"
    yq -i ".canonical_change.change_kind = \"ARTIFACT_REVISION\" |
      .canonical_change.artifact_revision = \"${merge_revision}\"" "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_merge_revision_unsupported:ABSENT'
}

@test "ARTIFACT_REVISION accepts a reachable commit that changes the existing artifact" {
    printf '%s\n' '# Review checklist revision 3' >"${ROOT}/${ARTIFACT_PATH}"
    git -C "$ROOT" add "$ARTIFACT_PATH"
    GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit -q -m 'revise canon artifact'
    ARTIFACT_REVISION="$(git -C "$ROOT" rev-parse HEAD)"
    ARTIFACT_DIGEST="sha256:$(openssl dgst -sha256 "${ROOT}/${ARTIFACT_PATH}" | awk '{print $NF}')"
    yq -i ".canonical_change.change_kind = \"ARTIFACT_REVISION\" |
      .canonical_change.artifact_revision = \"${ARTIFACT_REVISION}\" |
      .canonical_change.digest = \"${ARTIFACT_DIGEST}\"" "$REVIEW"
    run_validator
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'"status":"MET"'* ]]
}

@test "NEW_ARTIFACT rejects a path that already existed in the parent revision" {
    printf '%s\n' '# Review checklist revision 3' >"${ROOT}/${ARTIFACT_PATH}"
    git -C "$ROOT" add "$ARTIFACT_PATH"
    GIT_AUTHOR_DATE='2026-01-03T15:20:00Z' GIT_COMMITTER_DATE='2026-01-03T15:20:00Z' \
        git -C "$ROOT" commit -q -m 'revise existing canon artifact'
    ARTIFACT_REVISION="$(git -C "$ROOT" rev-parse HEAD)"
    ARTIFACT_DIGEST="sha256:$(openssl dgst -sha256 "${ROOT}/${ARTIFACT_PATH}" | awk '{print $NF}')"
    yq -i ".canonical_change.artifact_revision = \"${ARTIFACT_REVISION}\" |
      .canonical_change.digest = \"${ARTIFACT_DIGEST}\"" "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_new_artifact_preexisting:ABSENT'
}

@test "ARTIFACT_REVISION rejects a path absent from the parent revision" {
    yq -i '.canonical_change.change_kind = "ARTIFACT_REVISION"' "$REVIEW"
    run_validator
    assert_not_met 'canonical_change_revision_parent_missing_artifact:ABSENT'
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
      .originating_review.observed_at = "2026-01-03T15:20:00Z" |
      .originating_review_inventory[0].observed_at = "2026-01-03T15:20:00Z"' "$REVIEW"
    reseal_primary_review_digest >/dev/null
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
        && [[ "$output" == *'no_canon_change_decision_not_authenticated'* ]] \
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
