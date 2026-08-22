#!/usr/bin/env bats

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    SCRIPT="${REPO_ROOT}/dev-tools/check-customer-delivery.sh"
    PYTHON="${CUSTOMER_DELIVERY_PYTHON:-python3}"
    TASK_ID="WEB-0001"
    ROOT="${BATS_TEST_TMPDIR}/consumer"
    REQUIREMENTS="${ROOT}/datarim/tasks/${TASK_ID}-customer-requirements.yaml"
    RECEIPT="${ROOT}/datarim/receipts/${TASK_ID}-customer-delivery.yaml"
    [ -f "$SCRIPT" ] || { echo "ERROR: validator missing: $SCRIPT" >&2; return 1; }
    mkdir -p "${ROOT}/datarim/tasks" "${ROOT}/datarim/receipts"
    cp "${REPO_ROOT}/templates/customer-requirements-template.yaml" "$REQUIREMENTS"
    cp "${REPO_ROOT}/templates/customer-delivery-receipt-template.yaml" "$RECEIPT"
    cp "${REPO_ROOT}/templates/review-evolution-template.yaml" \
        "${ROOT}/datarim/receipts/${TASK_ID}-review-evolution.yaml"
    local digest
    digest="$($PYTHON - "$REQUIREMENTS" <<'PY'
import hashlib, sys, yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
print("sha256:" + hashlib.sha256(data["requirements"]["req-0001"]["acceptance"]["exact_source_quote"].encode()).hexdigest())
PY
)"
    yq -i '.requirements.req-0001.acceptance.implementation.code_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" |
        .requirements.req-0001.acceptance.implementation.content_revision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" |
        .requirements.req-0001.acceptance.disposition = "accepted"' "$REQUIREMENTS"
    yq -i ".requirements.req-0001.coverage_chain.requirement.source_quote_digest = \"${digest}\"" "$RECEIPT"
}

@test "removing every U4 edge rule is detected with exact attribution" {
    local edge mutant
    for edge in requirement selected_knowledge implementation_delta red_green merged_revision deployed_revision live_evidence customer_disposition; do
        mutant="${BATS_TEST_TMPDIR}/check-customer-delivery-${edge}.sh"
        cp "$SCRIPT" "$mutant" || return 1
        "$PYTHON" - "$mutant" "$edge" <<'PY' || return 1
import sys

path, edge = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
needle = f'    "{edge}",  # U4_EDGE\n'
if source.count(needle) != 1:
    raise SystemExit(f"mutation seam missing or ambiguous for {edge}")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source.replace(needle, "", 1))
PY
        chmod +x "$mutant"
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_FRAMEWORK_ROOT="$REPO_ROOT" \
            "$mutant" --root "$ROOT" --task "$TASK_ID" --stage qa --format text
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"validator_rule_removed:${edge}"* ]] \
            || return 1
        printf 'mutant=%s exit=1 finding=validator_rule_removed:%s\n' "$edge" "$edge"
    done
}
