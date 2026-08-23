#!/usr/bin/env bats

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    SCRIPT="${REPO_ROOT}/dev-tools/check-customer-delivery.sh"
    FUNCTIONAL_TEST="${BATS_TEST_DIRNAME}/check-customer-delivery.bats"
    PYTHON="${CUSTOMER_DELIVERY_PYTHON:-python3}"
    [ -f "$SCRIPT" ] || { echo "ERROR: validator missing: $SCRIPT" >&2; return 1; }
    [ -f "$FUNCTIONAL_TEST" ] || { echo "ERROR: functional tests missing: $FUNCTIONAL_TEST" >&2; return 1; }
}

@test "every U4 production validation branch is killed by its focused regression" {
    local pair edge filter framework mutant
    local -a pairs=(
        'requirement|receipt source quote digests exactly bind every linked source quote'
        'selected_knowledge|receipt selected knowledge exactly equals the accepted selection'
        'implementation_delta|implementation delta task is bound to selected implementation task'
        'red_green|implementation starts no later than RED evidence'
        'merged_revision|merged revision must be one of the accepted implementation revisions'
        'deployed_revision|production deployment SHA and digest must equal the merged accepted revision'
        'live_evidence|live production identity exactly equals accepted product identity'
        'customer_disposition|customer disposition must agree with the accepted requirement disposition'
    )

    for pair in "${pairs[@]}"; do
        edge="${pair%%|*}"
        filter="${pair#*|}"

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

        framework="${BATS_TEST_TMPDIR}/framework-${edge}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$edge" <<'PY' || return 1
import sys

path, edge = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
marker = f"# U4_RULE:{edge}"
matches = [index for index, line in enumerate(lines) if marker in line]
if len(matches) != 1:
    raise SystemExit(f"real production mutation seam missing or ambiguous for {edge}")
del lines[matches[0]]
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -ne 0 ] \
            && [[ "$output" == *"not ok 1 ${filter}"* ]] \
            || return 1
        printf 'mutant=%s killed_by=%s\n' "$edge" "$filter"
    done
}

@test "every security-critical production branch is killed by its focused regression" {
    local pair marker filter framework mutant
    local -a pairs=(
        'invariant_dispatch|semantic implementation dispatch cannot lose a registered rule'
        'registry_locator|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_owner|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_anchor|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_structure|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_duplicate|trusted registry duplicates conflicts and invalid validity windows fail closed'
        'registry_conflict|trusted registry duplicates conflicts and invalid validity windows fail closed'
        'registry_window|trusted registry duplicates conflicts and invalid validity windows fail closed'
        'registry_order|trusted registry entry order is authenticated before key lookup'
        'registry_digest|trusted registry canonical digest is verified before key lookup'
        'registry_signature|trusted registry signature is verified against the pinned root'
        'registry_receipt_ref|trusted registry locator owner anchor structure and receipt reference are pinned'
        'key_known|approval key identity role and existence are authorized before signature acceptance'
        'key_authority|approval key identity role and existence are authorized before signature acceptance'
        'key_role|approval key identity role and existence are authorized before signature acceptance'
        'key_active|authenticated leaf registry status and approval windows fail closed'
        'key_valid_from|authenticated leaf registry status and approval windows fail closed'
        'key_window|authenticated leaf registry status and approval windows fail closed'
        'artifact_signature|source and assertion signatures use raw digest Ed25519 framing'
        'source_tier_role|source tier role authorization and assertion authority identity are structural'
        'source_digest|source JCS digest and approval payload commitments are independently enforced'
        'source_approved_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'source_approval_digest|source JCS digest and approval payload commitments are independently enforced'
        'assertion_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'assertion_source_binding|source tier role authorization and assertion authority identity are structural'
        'assertion_approved_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'assertion_approval_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'source_history|source records are append-only against available Git history'
        'source_history_repo_required|MET requires an authoritative Git history for the requirement source'
        'source_history_document_required|MET requires the requirement source itself in authoritative Git history'
        'coverage_digest|terminal disposition commits the full pre-disposition coverage chain'
        'disposition_digest|terminal disposition canonical and approval payload digests are independently bound'
        'disposition_approved_digest|terminal disposition canonical and approval payload digests are independently bound'
        'disposition_approval_digest|terminal disposition canonical and approval payload digests are independently bound'
    )

    for pair in "${pairs[@]}"; do
        marker="${pair%%|*}"
        filter="${pair#*|}"

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

        framework="${BATS_TEST_TMPDIR}/security-framework-${marker}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$marker" <<'PY' || return 1
import sys

path, marker = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
needle = f"# SECURITY_RULE:{marker}"
matches = [index for index, line in enumerate(lines) if line.rstrip().endswith(needle)]
if len(matches) != 1:
    raise SystemExit(f"real production security seam missing or ambiguous for {marker}")
index = matches[0]
indent = lines[index][:-len(lines[index].lstrip())]
lines[index] = f"{indent}pass  # MUTATED:{marker}\n"
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -ne 0 ] \
            && [[ "$output" == *"not ok 1 ${filter}"* ]] \
            || return 1
        printf 'mutant=%s killed_by=%s\n' "$marker" "$filter"
    done
}
