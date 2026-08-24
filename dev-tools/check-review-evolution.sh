#!/bin/bash -p
# Validate the review-to-evolution contract without treating canon evolution as
# proof that the associated customer Requirement was delivered.
#
# Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

usage() {
    cat <<'EOF'
usage: check-review-evolution.sh --root DIR --task TASK-ID [--format text|json]

Reads exactly these canonical task-bound artifacts below DIR:
  datarim/receipts/<TASK-ID>-review-evolution.yaml
  datarim/receipts/<TASK-ID>-customer-delivery.yaml

Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
EOF
}

root=''
task=''
format='text'
parse_error=''
while (($#)); do
    case "$1" in
        --root|--task|--format)
            option="$1"
            if (($# < 2)); then
                parse_error='invalid_usage'
                break
            fi
            value="$2"
            case "$option" in
                --root) root="$value" ;;
                --task) task="$value" ;;
                --format) format="$value" ;;
            esac
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            parse_error='invalid_usage'
            shift
            ;;
    esac
done

emit_config_error() {
    local finding="$1"
    local safe_task=''
    [[ "$task" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ ]] && safe_task="$task"
    if [[ "$format" == json ]]; then
        printf '{"classification":"","findings":["%s"],"status":"ERROR","task":"%s"}\n' \
            "$finding" "$safe_task"
    else
        printf 'status=ERROR task=%s classification= findings=%s\n' "$safe_task" "$finding"
        printf 'finding=%s\n' "$finding"
    fi
}

if [[ -n "$parse_error" || -z "$root" || -z "$task" ]]; then
    emit_config_error 'invalid_usage'
    exit 2
fi
[[ "$format" == text || "$format" == json ]] || {
    format='text'
    emit_config_error 'invalid_format'
    exit 2
}
[[ "$task" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ ]] || {
    emit_config_error 'invalid_task'
    exit 2
}
[[ -d "$root" && ! -L "$root" ]] || {
    emit_config_error 'invalid_root'
    exit 2
}
root="$(cd "$root" && pwd -P)"

select_tool() {
    local candidate
    for candidate in "$@"; do
        if [[ -x "$candidate" && ! -d "$candidate" ]]; then
            selected_tool="$candidate"
            return 0
        fi
    done
    return 1
}

selected_tool=''
select_tool /usr/local/bin/yq /opt/homebrew/bin/yq /usr/bin/yq || {
    emit_config_error 'missing_dependency:yq'
    exit 2
}
yq_bin="$selected_tool"
select_tool /usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq || {
    emit_config_error 'missing_dependency:jq'
    exit 2
}
jq_bin="$selected_tool"

review="${root}/datarim/receipts/${task}-review-evolution.yaml"
receipt="${root}/datarim/receipts/${task}-customer-delivery.yaml"

resolve_artifact() {
    local label="$1"
    local candidate="$2"
    local resolved_dir
    if [[ ! -f "$candidate" ]]; then
        emit_config_error "missing_artifact:${label}"
        return 2
    fi
    if [[ -L "$candidate" ]]; then
        emit_config_error "path_escape:${label}"
        return 2
    fi
    resolved_dir="$(cd -P -- "${candidate%/*}" && pwd -P)" || {
        emit_config_error "path_escape:${label}"
        return 2
    }
    case "${resolved_dir}/${candidate##*/}" in
        "$root"/*) ;;
        *)
            emit_config_error "path_escape:${label}"
            return 2
            ;;
    esac
    artifact_bytes="$(/usr/bin/wc -c <"$candidate" | /usr/bin/tr -d '[:space:]')"
    if [[ ! "$artifact_bytes" =~ ^[0-9]+$ ]] || ((artifact_bytes > 1048576)); then
        emit_config_error "artifact_too_large:${label}"
        return 2
    fi
}

artifact_bytes=''
resolve_artifact review_evolution "$review" || exit 2
resolve_artifact customer_delivery "$receipt" || exit 2

tmp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/review-evolution.XXXXXX")" || {
    emit_config_error 'temporary_storage_unavailable'
    exit 2
}
cleanup() {
    # shellcheck disable=SC2317  # Called indirectly by the trap below.
    /bin/rm -rf -- "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM
review_json="${tmp_dir}/review.json"
receipt_json="${tmp_dir}/receipt.json"

if ! "$yq_bin" eval -o=json '.' "$review" >"$review_json" 2>/dev/null; then
    printf '%s\n' '{}' >"$review_json"
    review_parse_error=true
else
    review_parse_error=false
fi
if ! "$yq_bin" eval -o=json '.' "$receipt" >"$receipt_json" 2>/dev/null; then
    printf '%s\n' '{}' >"$receipt_json"
    receipt_parse_error=true
else
    receipt_parse_error=false
fi

findings=()
add_finding() {
    local finding="$1"
    local existing
    for existing in "${findings[@]:-}"; do
        [[ "$existing" == "$finding" ]] && return 0
    done
    findings+=("$finding")
}

if [[ "$review_parse_error" == true ]]; then
    add_finding 'malformed_yaml:review_evolution'
fi
if [[ "$receipt_parse_error" == true ]]; then
    add_finding 'malformed_yaml:customer_delivery'
fi

jq_raw() {
    "$jq_bin" -r "$1 // \"\" | if type == \"string\" then . else tostring end" "$2" 2>/dev/null || true
}
jq_type() {
    "$jq_bin" -r "$1 | type" "$2" 2>/dev/null || printf 'null\n'
}
jq_true() {
    "$jq_bin" -e "$1 == true" "$2" >/dev/null 2>&1
}
jq_has_nonempty_string() {
    "$jq_bin" -e "$1 | type == \"string\" and length > 0" "$2" >/dev/null 2>&1
}

classification="$(jq_raw '.classification' "$review_json")"
review_requirement="$(jq_raw '.requirement_id' "$review_json")"
review_receipt="$(jq_raw '.delivery_receipt_id' "$review_json")"
receipt_id="$(jq_raw '.receipt_id' "$receipt_json")"
product_requirement="$(jq_raw '.product_fix.requirement_id' "$review_json")"
product_receipt="$(jq_raw '.product_fix.delivery_receipt_id' "$review_json")"
product_status="$(jq_raw '.product_fix.status' "$review_json")"
reviewer="$(jq_raw '.reviewer' "$review_json")"

case "$classification" in
    ABSENT|WEAK|STALE|MIS_SCOPED|NOT_BOUND)
        if [[ "$(jq_type '.canonical_change' "$review_json")" != object ]]; then
            add_finding "classification_requires_canonical_change:${classification}"
        else
            jq_has_nonempty_string '.canonical_change.artifact_id' "$review_json" || \
                add_finding "canonical_change_missing_artifact:${classification}"
            jq_has_nonempty_string '.canonical_change.artifact_revision' "$review_json" || \
                add_finding "canonical_change_missing_revision:${classification}"
            change_kind="$(jq_raw '.canonical_change.change_kind' "$review_json")"
            if [[ "$change_kind" != NEW_ARTIFACT && "$change_kind" != ARTIFACT_REVISION ]]; then
                add_finding "canonical_change_invalid_kind:${classification}"
            fi
            change_digest="$(jq_raw '.canonical_change.digest' "$review_json")"
            [[ "$change_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || \
                add_finding "canonical_change_invalid_digest:${classification}"
            jq_has_nonempty_string '.canonical_change.recorded_at' "$review_json" || \
                add_finding "canonical_change_missing_recorded_at:${classification}"
            jq_has_nonempty_string '.canonical_change.enforcement.mechanism' "$review_json" || \
                add_finding "canonical_change_missing_mechanism:${classification}"
            jq_has_nonempty_string '.canonical_change.enforcement.owner' "$review_json" || \
                add_finding "canonical_change_missing_owner:${classification}"
            jq_true '.canonical_change.enforcement.red_capable' "$review_json" || \
                add_finding "canonical_change_not_red_capable:${classification}"
            jq_has_nonempty_string '.canonical_change.enforcement.red_evidence' "$review_json" || \
                add_finding "canonical_change_missing_red_evidence:${classification}"
            jq_has_nonempty_string '.canonical_change.enforcement.green_evidence' "$review_json" || \
                add_finding "canonical_change_missing_green_evidence:${classification}"
            red_evidence="$(jq_raw '.canonical_change.enforcement.red_evidence' "$review_json")"
            green_evidence="$(jq_raw '.canonical_change.enforcement.green_evidence' "$review_json")"
            if [[ -n "$red_evidence" && "$red_evidence" == "$green_evidence" ]]; then
                add_finding "canonical_change_red_green_evidence_not_distinct:${classification}"
            fi
        fi
        if [[ "$(jq_type '.no_canon_change' "$review_json")" != null ]]; then
            add_finding "classification_forbids_no_canon_change:${classification}"
        fi
        ;;
    NO_CANON_CHANGE)
        if [[ "$(jq_type '.no_canon_change' "$review_json")" != object ]]; then
            add_finding 'classification_requires_no_canon_change:NO_CANON_CHANGE'
        else
            jq_has_nonempty_string '.no_canon_change.evidence' "$review_json" || \
                add_finding 'no_canon_change_missing_evidence'
            jq_true '.no_canon_change.reviewer_approval.approved' "$review_json" || \
                add_finding 'no_canon_change_not_approved'
            jq_has_nonempty_string '.no_canon_change.reviewer_approval.reviewer' "$review_json" || \
                add_finding 'no_canon_change_missing_reviewer'
            jq_has_nonempty_string '.no_canon_change.reviewer_approval.approved_at' "$review_json" || \
                add_finding 'no_canon_change_missing_approved_at'
            approval_reviewer="$(jq_raw '.no_canon_change.reviewer_approval.reviewer' "$review_json")"
            if [[ "$approval_reviewer" != "$reviewer" ]]; then
                add_finding "no_canon_change_reviewer_mismatch:${reviewer}:${approval_reviewer}"
            fi
        fi
        if [[ "$(jq_type '.canonical_change' "$review_json")" != null ]]; then
            add_finding 'classification_forbids_canonical_change:NO_CANON_CHANGE'
        fi
        ;;
    *) add_finding "invalid_classification:${classification}" ;;
esac

[[ "$review_receipt" == "$receipt_id" ]] || \
    add_finding "review_receipt_mismatch:${receipt_id}:${review_receipt}"
[[ "$product_requirement" == "$review_requirement" ]] || \
    add_finding "product_fix_requirement_mismatch:${review_requirement}:${product_requirement}"
[[ "$product_receipt" == "$review_receipt" ]] || \
    add_finding "product_fix_receipt_mismatch:${review_receipt}:${product_receipt}"
[[ "$product_status" == DELIVERED ]] || \
    add_finding "product_fix_status_not_delivered:${review_requirement}"
jq_true '.product_fix.substitution_prohibited' "$review_json" || \
    add_finding "product_fix_substitution_not_prohibited:${review_requirement}"

# shellcheck disable=SC2016  # $id is a jq variable, not a shell variable.
if ! "$jq_bin" -e --arg id "$review_requirement" \
    '.parent_links | type == "array" and any(.[]; .relation == "requirement" and .id == $id)' \
    "$review_json" >/dev/null 2>&1; then
    add_finding "missing_parent_link:requirement:${review_requirement}"
fi
# shellcheck disable=SC2016  # $id is a jq variable, not a shell variable.
if ! "$jq_bin" -e --arg id "$review_receipt" \
    '.parent_links | type == "array" and any(.[]; .relation == "delivery_receipt" and .id == $id)' \
    "$review_json" >/dev/null 2>&1; then
    add_finding "missing_parent_link:delivery_receipt:${review_receipt}"
fi
while IFS=$'\t' read -r parent_relation parent_id; do
    [[ -n "$parent_relation" && -n "$parent_id" ]] || continue
    # shellcheck disable=SC2016  # $relation and $id are jq variables.
    if ! "$jq_bin" -e --arg relation "$parent_relation" --arg id "$parent_id" \
        '.parent_links | type == "array" and any(.[]; .relation == $relation and .id == $id)' \
        "$review_json" >/dev/null 2>&1; then
        add_finding "missing_parent_link:${parent_relation}:${parent_id}"
    fi
done < <("$jq_bin" -r \
    '.parent_links[]? | select(.relation == "epic" or .relation == "task") | [.relation, .id] | @tsv' \
    "$receipt_json" 2>/dev/null || true)

# shellcheck disable=SC2016  # $id is a jq variable, not a shell variable.
coverage_status="$("$jq_bin" -r --arg id "$review_requirement" \
    '.requirements[$id].coverage_status // ""' "$receipt_json" 2>/dev/null || true)"
# shellcheck disable=SC2016  # $id is a jq variable, not a shell variable.
disposition_status="$("$jq_bin" -r --arg id "$review_requirement" \
    '.requirements[$id].coverage_chain.customer_disposition.status // ""' "$receipt_json" 2>/dev/null || true)"
if [[ "$coverage_status" != MET || \
      ("$disposition_status" != accepted && "$disposition_status" != superseded) ]]; then
    add_finding "product_requirement_not_delivered:${review_requirement}"
fi

if ((${#findings[@]})); then
    status='NOT_MET'
    exit_status=1
else
    status='MET'
    exit_status=0
fi

if [[ "$format" == json ]]; then
    # shellcheck disable=SC2016  # Named values and $ARGS are jq variables.
    "$jq_bin" -cn \
        --arg status "$status" \
        --arg task "$task" \
        --arg classification "$classification" \
        '{classification:$classification,findings:$ARGS.positional,status:$status,task:$task}' \
        --args "${findings[@]}"
else
    findings_csv=''
    for finding in "${findings[@]}"; do
        [[ -z "$findings_csv" ]] || findings_csv+=','
        findings_csv+="$finding"
    done
    printf 'status=%s task=%s classification=%s findings=%s\n' \
        "$status" "$task" "$classification" "$findings_csv"
    for finding in "${findings[@]}"; do
        printf 'finding=%s\n' "$finding"
    done
fi
exit "$exit_status"
