#!/usr/bin/env bats

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    SCRIPT="${CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE:-${REPO_ROOT}/dev-tools/check-customer-delivery.sh}"
    PYTHON="${CUSTOMER_DELIVERY_PYTHON:-python3}"
    TASK_ID="WEB-0001"
    ROOT="${BATS_TEST_TMPDIR}/consumer"
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    REVIEW="${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    mkdir -p "${ROOT}/datarim/tasks" "${ROOT}/datarim/receipts"

    if ! command -v yq >/dev/null 2>&1; then
        echo "ERROR: yq is required for customer-delivery tests" >&2
        return 1
    fi
    if ! "$PYTHON" -c 'import jsonschema, yaml' >/dev/null 2>&1; then
        echo "ERROR: required Python test dependencies unavailable: jsonschema and PyYAML" >&2
        return 1
    fi

    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    cp "${REPO_ROOT}/templates/review-evolution-template.yaml" "$REVIEW"

    local quote_digest
    quote_digest="$($PYTHON - "$REQUIREMENTS" <<'PY'
import hashlib
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
quote = data["requirements"]["req-0001"]["acceptance"]["exact_source_quote"]
print("sha256:" + hashlib.sha256(quote.encode("utf-8")).hexdigest())
PY
)"
    yq -i ".requirements.req-0001.acceptance.implementation.code_revision = \"${SHA}\" |
        .requirements.req-0001.acceptance.implementation.content_revision = \"${SHA}\" |
        .requirements.req-0001.acceptance.disposition = \"accepted\"" "$REQUIREMENTS"
    yq -i ".requirements.req-0001.coverage_chain.requirement.source_quote_digest = \"${quote_digest}\"" "$RECEIPT"
}

run_validator() {
    run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="$REPO_ROOT" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format text
}

@test "complete canonical delivery chain is MET" {
    run_validator
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"decision=MET"* ]]
}

@test "all hard semantic stages enforce the same delivery decision" {
    local stage
    for stage in qa compliance archive; do
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="$REPO_ROOT" \
            "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage "$stage" --format json
        [ "$status" -eq 0 ] \
            && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["decision"] == "MET" and d["stage"] == sys.argv[2]' "$output" "$stage" \
            || return 1
    done
}

@test "missing verbatim provenance and broken bidirectional mapping are NOT_MET" {
    yq -i 'del(.source_remarks[0].verbatim_quote)' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:requirements"* ]]
}

@test "exact source quotes must agree with every mapped Tier-1 remark" {
    yq -i '.requirements.req-0001.acceptance.exact_source_quote = "Derived paraphrase only."' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"exact_quote_mismatch:req-0001"* ]]
}

@test "tool-only acceptance cannot satisfy a visitor-visible requirement" {
    yq -i '.requirements.req-0001.acceptance.production_acceptance_criterion = "The validator tool exits zero." |
        .requirements.req-0001.acceptance.evidence.method = "CLI and CI checks only."' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"tool_only_visible_acceptance:req-0001"* ]]
}

@test "post-hoc knowledge selection is NOT_MET" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_at = "2026-01-02T10:00:01Z" |
        .requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_before_implementation = true |
        .requirements.req-0001.acceptance.knowledge_selection.roles[0].immutable = true |
        .requirements.req-0001.acceptance.knowledge_selection.roles[0].revision = "1"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.roles[0].selected_at = "2026-01-02T10:00:01Z"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"knowledge_selected_post_hoc:req-0001:roles"* ]]
}

@test "mutable or unpinned knowledge is NOT_MET" {
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].immutable = false' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:requirements"* ]] \
        || return 1

    yq -i '.requirements.req-0001.acceptance.knowledge_selection.skills[0].immutable = true |
        .requirements.req-0001.acceptance.knowledge_selection.skills[0].revision = "main"' "$REQUIREMENTS"
    yq -i '.requirements.req-0001.coverage_chain.selected_knowledge.skills[0].revision = "main"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"knowledge_revision_unpinned:req-0001:skills"* ]]
}

@test "Gap and Unbound knowledge permit capability work but not delivered product claims" {
    local marker
    for marker in Gap Unbound; do
        build_marker="$marker"
        yq -i ".requirements.req-0001.acceptance.knowledge_selection.roles[0].id = \"${build_marker}\"" "$REQUIREMENTS"
        yq -i ".requirements.req-0001.coverage_chain.selected_knowledge.roles[0].id = \"${build_marker}\"" "$RECEIPT"
        run_validator
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"unbound_product_delivery:req-0001:roles"* ]] \
            || return 1
    done
}

@test "a user-facing requirement and parent need a visitor-visible delta" {
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_count = 0 |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes = []' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"zero_visitor_visible_delta:req-0001"* ]]
}

@test "missing merge deploy live or disposition edges are NOT_MET" {
    local edge
    for edge in merged_revision deployed_revision live_evidence customer_disposition; do
        cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
        local quote_digest
        quote_digest="$($PYTHON - "$REQUIREMENTS" <<'PY'
import hashlib, sys, yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
print("sha256:" + hashlib.sha256(data["requirements"]["req-0001"]["acceptance"]["exact_source_quote"].encode()).hexdigest())
PY
)"
        yq -i ".requirements.req-0001.coverage_status = \"NOT_MET\" |
            .requirements.req-0001.missing_edges = [\"${edge}\"] |
            del(.requirements.req-0001.coverage_chain.${edge}) |
            .requirements.req-0001.coverage_chain.requirement.source_quote_digest = \"${quote_digest}\"" "$RECEIPT"
        run_validator
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"missing_edge:req-0001:${edge}"* ]] \
            || return 1
    done
}

@test "production deployment SHA and digest must equal the merged accepted revision" {
    yq -i '.requirements.req-0001.coverage_chain.deployed_revision.revision = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_revision_mismatch:req-0001"* ]]
}

@test "open or changes-requested parent review cannot close delivery" {
    yq -i '.product_fix.status = "IN_PROGRESS"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"parent_review_not_closed:req-0001"* ]] \
        || return 1

    yq -i '.product_fix.status = "changes_requested"' "$REVIEW"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:review"* ]]
}

@test "authored epic status is rejected instead of drifting from computed child state" {
    yq -i '.parent_links[0].status = "MET"' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:receipt"* ]]
}

@test "supersession cycles are NOT_MET" {
    yq -i '.source_remarks[0].requirement_ids += ["req-0002"] |
        .requirements.req-0002 = .requirements.req-0001 |
        .requirements.req-0001.acceptance.disposition = "superseded" |
        .requirements.req-0001.acceptance.superseded_by = "req-0002" |
        .requirements.req-0002.acceptance.disposition = "superseded" |
        .requirements.req-0002.acceptance.superseded_by = "req-0001"' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"cycle:req-0001"* ]]
}

@test "duplicate YAML IDs fail closed instead of being overwritten" {
    printf '%s\n' '  req-0001:' '    source_ids: [source-0001]' '    atomic_statement: duplicate' >> "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"duplicate_id:req-0001"* ]]
}

@test "dangling requirement references are NOT_MET" {
    yq -i '.source_remarks[0].requirement_ids = ["req-9999"]' "$REQUIREMENTS"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"dangling_requirement_ref:source-0001:req-9999"* ]]
}

@test "applicable live evidence needs the exact eight-cell RU EN matrix" {
    yq -i 'del(.requirements.req-0001.coverage_chain.live_evidence.painted_matrix[7])' "$RECEIPT"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"schema:receipt"* || "$output" == *"painted_matrix_incomplete:req-0001"* ]]
}

@test "JSON output is deterministic and machine-readable" {
    run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="$REPO_ROOT" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    local first="$output"
    [ "$status" -eq 0 ] || return 1
    run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="$REPO_ROOT" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage compliance --format json
    [ "$status" -eq 0 ] \
        && [ "$output" = "$first" ] \
        && "$PYTHON" -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["decision"] == "MET" and d["findings"] == []' "$output"
}

@test "usage errors and missing canonical artifacts exit 2" {
    run "$SCRIPT" --root "$ROOT" --task bad --stage qa --format text
    [ "$status" -eq 2 ] || return 1
    rm "$RECEIPT"
    run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="$REPO_ROOT" \
        "$SCRIPT" --root "$ROOT" --task "$TASK_ID" --stage qa --format text
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"missing_artifact"* ]]
}
