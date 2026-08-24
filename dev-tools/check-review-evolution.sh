#!/bin/bash -p
# Validate the review-to-evolution contract without treating canon evolution as
# proof that the associated customer Requirement was delivered.
#
# Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<'EOF'
usage: check-review-evolution.sh --root DIR --task TASK-ID [--format text|json]

Reads exactly these canonical task-bound artifacts below DIR:
  datarim/tasks/<TASK-ID>-customer-requirements.yaml
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
platform="$(/usr/bin/uname -s 2>/dev/null || true)"
case "$platform" in
    Linux)
        select_tool /usr/bin/git || {
            emit_config_error 'missing_dependency:git'
            exit 2
        }
        git_bin="$selected_tool"
        select_tool /usr/bin/openssl || {
            emit_config_error 'missing_dependency:openssl'
            exit 2
        }
        openssl_bin="$selected_tool"
        ;;
    Darwin)
        select_tool /Library/Developer/CommandLineTools/usr/bin/git /usr/bin/git || {
            emit_config_error 'missing_dependency:git'
            exit 2
        }
        git_bin="$selected_tool"
        select_tool /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl /usr/bin/openssl || {
            emit_config_error 'missing_dependency:openssl'
            exit 2
        }
        openssl_bin="$selected_tool"
        ;;
    *)
        emit_config_error 'unsupported_platform'
        exit 2
        ;;
esac

requirements="${root}/datarim/tasks/${task}-customer-requirements.yaml"
review="${root}/datarim/receipts/${task}-review-evolution.yaml"
receipt="${root}/datarim/receipts/${task}-customer-delivery.yaml"
script_dir="$(cd "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
trust_registry_schema="${script_dir}/../config/customer-requirement.schema.json"

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
resolve_artifact customer_requirements "$requirements" || exit 2
resolve_artifact review_evolution "$review" || exit 2
resolve_artifact customer_delivery "$receipt" || exit 2
if [[ ! -f "$trust_registry_schema" || -L "$trust_registry_schema" ]]; then
    emit_config_error 'missing_dependency:trusted_authority_registry'
    exit 2
fi
trust_registry_bytes="$(/usr/bin/wc -c <"$trust_registry_schema" | /usr/bin/tr -d '[:space:]')"
if [[ ! "$trust_registry_bytes" =~ ^[0-9]+$ ]] || ((trust_registry_bytes > 1048576)); then
    emit_config_error 'trusted_authority_registry_too_large'
    exit 2
fi

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
delivery_output="${tmp_dir}/customer-delivery.json"
requirements_snapshot="${tmp_dir}/requirements.yaml"
review_snapshot="${tmp_dir}/review.yaml"
receipt_snapshot="${tmp_dir}/receipt.yaml"
trust_registry_snapshot="${tmp_dir}/customer-requirement.schema.json"
/bin/cp -- "$requirements" "$requirements_snapshot"
/bin/cp -- "$review" "$review_snapshot"
/bin/cp -- "$receipt" "$receipt_snapshot"
/bin/cp -- "$trust_registry_schema" "$trust_registry_snapshot"
requirements_snapshot_digest="$("$openssl_bin" dgst -sha256 "$requirements_snapshot" | /usr/bin/awk '{print $NF}')"
review_snapshot_digest="$("$openssl_bin" dgst -sha256 "$review_snapshot" | /usr/bin/awk '{print $NF}')"
receipt_snapshot_digest="$("$openssl_bin" dgst -sha256 "$receipt_snapshot" | /usr/bin/awk '{print $NF}')"
trust_registry_snapshot_digest="$("$openssl_bin" dgst -sha256 "$trust_registry_snapshot" | /usr/bin/awk '{print $NF}')"
customer_delivery_validator="${script_dir}/check-customer-delivery.sh"
if [[ ! -f "$customer_delivery_validator" || -L "$customer_delivery_validator" \
    || ! -x "$customer_delivery_validator" ]]; then
    emit_config_error 'missing_dependency:check-customer-delivery'
    exit 2
fi
set +e
"$customer_delivery_validator" --root "$root" --task "$task" --stage qa --format json \
    >"$delivery_output" 2>/dev/null
delivery_status=$?
set -e
delivery_verified=false
delivery_inputs_stable=false
# shellcheck disable=SC2016  # $task is a jq variable.
if [[ "$delivery_status" -eq 0 ]] \
    && "$jq_bin" -se --arg task "$task" \
        'length == 1 and .[0].decision == "MET" and .[0].status == "MET"
         and .[0].epic_status == "MET" and .[0].stage == "qa"
         and .[0].task == $task and .[0].findings == []' \
        "$delivery_output" >/dev/null 2>&1; then
    delivery_verified=true
fi
if [[ "$("$openssl_bin" dgst -sha256 "$requirements" 2>/dev/null | /usr/bin/awk '{print $NF}')" \
        == "$requirements_snapshot_digest" \
    && "$("$openssl_bin" dgst -sha256 "$review" 2>/dev/null | /usr/bin/awk '{print $NF}')" \
        == "$review_snapshot_digest" \
    && "$("$openssl_bin" dgst -sha256 "$receipt" 2>/dev/null | /usr/bin/awk '{print $NF}')" \
        == "$receipt_snapshot_digest" \
    && "$("$openssl_bin" dgst -sha256 "$trust_registry_schema" 2>/dev/null | /usr/bin/awk '{print $NF}')" \
        == "$trust_registry_snapshot_digest" ]]; then
    delivery_inputs_stable=true
fi

if ! "$yq_bin" eval -o=json '.' "$review_snapshot" >"$review_json" 2>/dev/null; then
    printf '%s\n' '{}' >"$review_json"
    review_parse_error=true
else
    review_parse_error=false
fi
if ! "$yq_bin" eval -o=json '.' "$receipt_snapshot" >"$receipt_json" 2>/dev/null; then
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

if [[ "$delivery_verified" != true ]]; then
    add_finding 'customer_delivery_not_met'
fi
if [[ "$delivery_inputs_stable" != true ]]; then
    add_finding 'customer_delivery_inputs_changed'
fi

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

run_bound_git() {
    /usr/bin/env -i LC_ALL=C GIT_NO_REPLACE_OBJECTS=1 \
        "$git_bin" -C "$root" "$@"
}

bound_head="$(run_bound_git rev-parse --verify HEAD 2>/dev/null || true)"
if [[ ! "$bound_head" =~ ^[0-9a-f]{40}$ ]]; then
    add_finding 'repository_head_invalid'
fi

is_safe_relative_path() {
    local candidate="$1" component
    local -a components=()
    [[ -n "$candidate" && "$candidate" != /* && "$candidate" != *$'\n'* \
        && "$candidate" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    IFS='/' read -r -a components <<<"$candidate"
    ((${#components[@]} > 0)) || return 1
    for component in "${components[@]}"; do
        [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
    done
}

git_blob_to_file() {
    local revision="$1" path="$2" destination="$3"
    local tree_line mode size
    tree_line="$(run_bound_git ls-tree "$revision" -- "$path" 2>/dev/null || true)"
    [[ -n "$tree_line" && "$tree_line" != *$'\n'* ]] || return 1
    mode="${tree_line%% *}"
    [[ "$mode" == 100644 || "$mode" == 100755 ]] || return 1
    size="$(run_bound_git cat-file -s "${revision}:${path}" 2>/dev/null || true)"
    [[ "$size" =~ ^[0-9]+$ ]] && ((size > 0 && size <= 1048576)) || return 1
    run_bound_git cat-file blob "${revision}:${path}" >"$destination" 2>/dev/null
}

git_blob_identity() {
    local revision="$1" path="$2"
    local tree_line mode object_type object_id
    tree_line="$(run_bound_git ls-tree "$revision" -- "$path" 2>/dev/null || true)"
    [[ -n "$tree_line" && "$tree_line" != *$'\n'* ]] || return 1
    read -r mode object_type object_id _ <<<"$tree_line"
    [[ "$mode" == 100644 || "$mode" == 100755 ]] || return 1
    [[ "$object_type" == blob && "$object_id" =~ ^[0-9a-f]{40}$ ]] || return 1
    printf '%s\n' "$object_id"
}

sha256_file() {
    "$openssl_bin" dgst -sha256 "$1" 2>/dev/null | /usr/bin/awk '{print "sha256:" $NF}'
}

valid_timestamp_shape() {
    local timestamp="$1"
    [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
        || return 1
    # shellcheck disable=SC2016  # $timestamp is a jq variable.
    "$jq_bin" -en --arg timestamp "$timestamp" \
        '$timestamp | fromdateiso8601' >/dev/null 2>&1
}

timestamp_not_before() {
    local later="$1" earlier="$2"
    # shellcheck disable=SC2016  # jq variables are intentionally quoted literally.
    "$jq_bin" -en --arg later "$later" --arg earlier "$earlier" \
        '($later | fromdateiso8601) >= ($earlier | fromdateiso8601)' >/dev/null 2>&1
}

verify_ed25519_payload() {
    local payload_file="$1" signature="$2" public_key="$3"
    local public_der="${tmp_dir}/decision-public.der"
    local signature_file="${tmp_dir}/decision-signature.bin"
    [[ "$signature" == ed25519:* ]] || return 1
    [[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || return 1
    /usr/bin/printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00' >"$public_der"
    /usr/bin/printf '%s' "$public_key" | "$openssl_bin" base64 -d -A >>"$public_der" 2>/dev/null \
        || return 1
    /usr/bin/printf '%s' "${signature#ed25519:}" \
        | "$openssl_bin" base64 -d -A >"$signature_file" 2>/dev/null || return 1
    [[ "$(/usr/bin/wc -c <"$public_der" | /usr/bin/tr -d '[:space:]')" == 44 ]] || return 1
    [[ "$(/usr/bin/wc -c <"$signature_file" | /usr/bin/tr -d '[:space:]')" == 64 ]] || return 1
    "$openssl_bin" pkeyutl -verify -pubin -keyform DER -inkey "$public_der" -rawin \
        -in "$payload_file" -sigfile "$signature_file" >/dev/null 2>&1
}

validate_no_canon_decision() {
    local evidence_path="$1" approval_reviewer="$2" approval_time="$3"
    local decision_file="${tmp_dir}/no-canon-decision.json"
    local payload_file="${tmp_dir}/no-canon-decision-payload.json"
    local declared_digest computed_digest signature key_id public_key registry_match_count
    if ! is_safe_relative_path "$evidence_path" \
        || ! git_blob_to_file "$bound_head" "$evidence_path" "$decision_file"; then
        return 1
    fi
    # shellcheck disable=SC2016  # Closed JSON envelope is validated by jq.
    "$jq_bin" -e '
      type == "object" and
      (keys | sort) == ([
        "algorithm", "approved", "approved_at", "authority_id", "authority_role",
        "decision", "decision_evidence_ref", "delivery_receipt_id", "finding_evidence_ref",
        "key_id", "originating_review_digest", "originating_review_id", "payload_digest",
        "requirement_id", "reviewer", "schema_version", "signature", "task_id"
      ] | sort) and
      .schema_version == 1 and .decision == "NO_CANON_CHANGE" and .approved == true and
      (.payload_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.signature | type == "string" and startswith("ed25519:"))
    ' "$decision_file" >/dev/null 2>&1 || return 1

    [[ "$(jq_raw '.task_id' "$decision_file")" == "$task" ]] || return 1
    [[ "$(jq_raw '.requirement_id' "$decision_file")" == "$review_requirement" ]] || return 1
    [[ "$(jq_raw '.delivery_receipt_id' "$decision_file")" == "$review_receipt" ]] || return 1
    [[ "$(jq_raw '.originating_review_id' "$decision_file")" == "$review_id" ]] || return 1
    [[ "$(jq_raw '.originating_review_digest' "$decision_file")" == "$signed_review_digest" ]] \
        || return 1
    [[ "$(jq_raw '.reviewer' "$decision_file")" == "$signed_review_reviewer" ]] || return 1
    [[ "$approval_reviewer" == "$signed_review_reviewer" ]] || return 1
    [[ "$(jq_raw '.approved_at' "$decision_file")" == "$approval_time" ]] || return 1
    valid_timestamp_shape "$approval_time" || return 1
    timestamp_not_before "$approval_time" "$signed_review_observed_at" || return 1
    [[ "$(jq_raw '.finding_evidence_ref' "$decision_file")" == "$signed_review_evidence" ]] \
        || return 1
    [[ "$(jq_raw '.decision_evidence_ref' "$decision_file")" == "$evidence_path" ]] || return 1
    is_safe_relative_path "$signed_review_evidence" \
        && git_blob_to_file "$bound_head" "$signed_review_evidence" \
            "${tmp_dir}/no-canon-finding-evidence" || return 1
    [[ "$(jq_raw '.authority_id' "$decision_file")" == "$signed_authority_id" ]] || return 1
    [[ "$(jq_raw '.authority_role' "$decision_file")" == "$signed_authority_role" ]] || return 1
    [[ "$(jq_raw '.algorithm' "$decision_file")" == ED25519 ]] || return 1
    key_id="$(jq_raw '.key_id' "$decision_file")"
    [[ "$key_id" == "$signed_authority_key_id" ]] || return 1

    # A2 has already authenticated this byte-stable bundled registry and review record.
    # shellcheck disable=SC2016  # jq variables are intentionally quoted literally.
    registry_match_count="$("$jq_bin" -r --arg key "$key_id" \
        '[."x-datarim-signature-contract".key_resolution.bundled_registry.entries[]?
          | select(.key_id == $key)] | length' "$trust_registry_snapshot" 2>/dev/null || true)"
    [[ "$registry_match_count" == 1 ]] || return 1
    # shellcheck disable=SC2016  # jq variables are intentionally quoted literally.
    "$jq_bin" -e --arg key "$key_id" --arg authority "$signed_authority_id" \
        --arg role "$signed_authority_role" --arg approved_at "$approval_time" '
          ."x-datarim-signature-contract".key_resolution.bundled_registry.entries
          | map(select(.key_id == $key))[0]
          | .authority_id == $authority and (.allowed_roles | index($role) != null)
            and .status == "ACTIVE"
            and ((.valid_from | fromdateiso8601) <= ($approved_at | fromdateiso8601))
            and (.valid_until == null or (($approved_at | fromdateiso8601) < (.valid_until | fromdateiso8601)))
        ' "$trust_registry_snapshot" >/dev/null 2>&1 || return 1
    # shellcheck disable=SC2016  # jq variables are intentionally quoted literally.
    public_key="$("$jq_bin" -r --arg key "$key_id" \
        '."x-datarim-signature-contract".key_resolution.bundled_registry.entries[]
          | select(.key_id == $key) | .public_key' "$trust_registry_snapshot" 2>/dev/null || true)"

    "$jq_bin" -cS 'del(.payload_digest, .signature)' "$decision_file" >"$payload_file" \
        2>/dev/null || return 1
    declared_digest="$(jq_raw '.payload_digest' "$decision_file")"
    computed_digest="$(sha256_file "$payload_file")"
    [[ "$declared_digest" == "$computed_digest" ]] || return 1
    signature="$(jq_raw '.signature' "$decision_file")"
    verify_ed25519_payload "$payload_file" "$signature" "$public_key"
}

validate_evolution_evidence() {
    local kind="$1" evidence_path="$2" revision="$3" classification_value="$4"
    local marker="$5" destination="${tmp_dir}/${kind}-evidence"
    if ! is_safe_relative_path "$evidence_path"; then
        add_finding "canonical_change_${kind}_evidence_path_invalid:${classification_value}"
        return 1
    fi
    if ! git_blob_to_file "$revision" "$evidence_path" "$destination"; then
        add_finding "canonical_change_${kind}_evidence_missing:${classification_value}"
        return 1
    fi
    if ! /usr/bin/grep -Eq "$marker" "$destination"; then
        add_finding "canonical_change_${kind}_evidence_invalid:${classification_value}"
        return 1
    fi
}

validate_canonical_evolution() {
    local classification_value="$1"
    local artifact_path artifact_revision artifact_digest recorded_at change_kind
    local red_path green_path artifact_file revision_valid=false recorded_valid=false
    local commit_after_review commit_before_record red_digest green_digest
    local revision_parent_line child_identity parent_identity
    local -a revision_parts=()
    artifact_path="$(jq_raw '.canonical_change.artifact_id' "$review_json")"
    artifact_revision="$(jq_raw '.canonical_change.artifact_revision' "$review_json")"
    artifact_digest="$(jq_raw '.canonical_change.digest' "$review_json")"
    recorded_at="$(jq_raw '.canonical_change.recorded_at' "$review_json")"
    change_kind="$(jq_raw '.canonical_change.change_kind' "$review_json")"
    red_path="$(jq_raw '.canonical_change.enforcement.red_evidence' "$review_json")"
    green_path="$(jq_raw '.canonical_change.enforcement.green_evidence' "$review_json")"
    artifact_file="${tmp_dir}/canonical-artifact"

    if [[ "$artifact_revision" =~ ^[0-9a-f]{40}$ ]] \
        && run_bound_git cat-file -e "${artifact_revision}^{commit}" 2>/dev/null; then
        revision_valid=true
        if ! run_bound_git merge-base --is-ancestor "$artifact_revision" "$bound_head" \
            >/dev/null 2>&1; then
            add_finding "canonical_change_revision_not_ancestor:${classification_value}"
        fi
    else
        add_finding "canonical_change_invalid_revision:${classification_value}"
    fi
    if ! is_safe_relative_path "$artifact_path"; then
        add_finding "canonical_change_artifact_path_invalid:${classification_value}"
    elif [[ "$revision_valid" == true ]]; then
        if git_blob_to_file "$artifact_revision" "$artifact_path" "$artifact_file"; then
            if [[ "$(sha256_file "$artifact_file")" != "$artifact_digest" ]]; then
                add_finding "canonical_change_digest_mismatch:${classification_value}"
            fi
        else
            add_finding "canonical_change_artifact_missing:${classification_value}"
        fi
    fi
    if [[ "$artifact_digest" == sha256:0000000000000000000000000000000000000000000000000000000000000000 ]]; then
        add_finding "canonical_change_digest_mismatch:${classification_value}"
    fi

    if [[ "$revision_valid" == true ]] && is_safe_relative_path "$artifact_path"; then
        revision_parent_line="$(run_bound_git rev-list --parents -n 1 "$artifact_revision" \
            2>/dev/null || true)"
        read -r -a revision_parts <<<"$revision_parent_line"
        if ((${#revision_parts[@]} > 2)); then
            add_finding "canonical_change_merge_revision_unsupported:${classification_value}"
        elif ((${#revision_parts[@]} != 2)); then
            add_finding "canonical_change_revision_parent_invalid:${classification_value}"
        else
            child_identity="$(git_blob_identity "$artifact_revision" "$artifact_path" || true)"
            parent_identity="$(git_blob_identity "${revision_parts[1]}" "$artifact_path" || true)"
            case "$change_kind" in
                NEW_ARTIFACT)
                    if [[ -n "$parent_identity" ]]; then
                        add_finding "canonical_change_new_artifact_preexisting:${classification_value}"
                    fi
                    ;;
                ARTIFACT_REVISION)
                    if [[ -z "$parent_identity" ]]; then
                        add_finding "canonical_change_revision_parent_missing_artifact:${classification_value}"
                    elif [[ -n "$child_identity" && "$child_identity" == "$parent_identity" ]]; then
                        add_finding "canonical_change_artifact_unchanged:${classification_value}"
                    fi
                    ;;
            esac
        fi
    fi

    if valid_timestamp_shape "$recorded_at"; then
        recorded_valid=true
    else
        add_finding "canonical_change_invalid_recorded_at:${classification_value}"
    fi
    if [[ "$revision_valid" == true && "$recorded_valid" == true ]]; then
        commit_after_review="$(run_bound_git log -1 --format=%H --since="$signed_review_observed_at" \
            "$artifact_revision" 2>/dev/null || true)"
        if [[ "$commit_after_review" != "$artifact_revision" ]]; then
            add_finding "canonical_change_post_hoc:${classification_value}"
        fi
        commit_before_record="$(run_bound_git log -1 --format=%H --until="$recorded_at" \
            "$artifact_revision" 2>/dev/null || true)"
        if [[ "$commit_before_record" != "$artifact_revision" ]]; then
            add_finding "canonical_change_recorded_before_revision:${classification_value}"
        fi
        validate_evolution_evidence red "$red_path" "$artifact_revision" \
            "$classification_value" '(^|["[:space:]])status[" :=]+"?failed_as_expected' || true
        validate_evolution_evidence green "$green_path" "$artifact_revision" \
            "$classification_value" '(^|["[:space:]])status[" :=]+"?passed' || true
        if [[ -f "${tmp_dir}/red-evidence" && -f "${tmp_dir}/green-evidence" ]]; then
            red_digest="$(sha256_file "${tmp_dir}/red-evidence")"
            green_digest="$(sha256_file "${tmp_dir}/green-evidence")"
            if [[ "$red_digest" == "$green_digest" ]]; then
                add_finding "canonical_change_red_green_evidence_not_distinct:${classification_value}"
            fi
        fi
    fi
}

classification="$(jq_raw '.classification' "$review_json")"
review_id="$(jq_raw '.review_id' "$review_json")"
review_requirement="$(jq_raw '.requirement_id' "$review_json")"
review_receipt="$(jq_raw '.delivery_receipt_id' "$review_json")"
receipt_id="$(jq_raw '.receipt_id' "$receipt_json")"
product_requirement="$(jq_raw '.product_fix.requirement_id' "$review_json")"
product_receipt="$(jq_raw '.product_fix.delivery_receipt_id' "$review_json")"
product_status="$(jq_raw '.product_fix.status' "$review_json")"
# shellcheck disable=SC2016  # jq variables are intentionally quoted literally.
authoritative_review_count="$("$jq_bin" -r --arg review "$review_id" --arg requirement "$review_requirement" \
    '[.originating_review_inventory[]?
      | select(.review_id == $review and .requirement_id == $requirement)] | length' \
    "$review_json" 2>/dev/null || true)"
signed_review_reviewer=''
signed_review_evidence=''
signed_review_digest=''
signed_review_observed_at=''
signed_authority_id=''
signed_authority_role=''
signed_authority_key_id=''
if [[ "$authoritative_review_count" == 1 ]]; then
    # shellcheck disable=SC2016  # jq variables are intentionally quoted literally.
    authoritative_review_query='[.originating_review_inventory[]
      | select(.review_id == $review and .requirement_id == $requirement)][0]'
    signed_review_reviewer="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" "${authoritative_review_query}.reviewer // \"\"" \
        "$review_json" 2>/dev/null || true)"
    signed_review_evidence="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" "${authoritative_review_query}.evidence_ref // \"\"" \
        "$review_json" 2>/dev/null || true)"
    signed_review_digest="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" "${authoritative_review_query}.review_digest // \"\"" \
        "$review_json" 2>/dev/null || true)"
    signed_review_observed_at="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" "${authoritative_review_query}.observed_at // \"\"" \
        "$review_json" 2>/dev/null || true)"
    signed_authority_id="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" \
        "${authoritative_review_query}.authority_approval.authority_id // \"\"" \
        "$review_json" 2>/dev/null || true)"
    signed_authority_role="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" \
        "${authoritative_review_query}.authority_approval.authority_role // \"\"" \
        "$review_json" 2>/dev/null || true)"
    signed_authority_key_id="$("$jq_bin" -r --arg review "$review_id" \
        --arg requirement "$review_requirement" \
        "${authoritative_review_query}.authority_approval.key_id // \"\"" \
        "$review_json" 2>/dev/null || true)"
else
    add_finding "originating_review_binding_invalid:${review_id}:${review_requirement}"
fi
task_prefix="${task%-*}"
task_number="${task##*-}"
task_prefix_lower="$(printf '%s' "$task_prefix" | /usr/bin/tr '[:upper:]' '[:lower:]')"
expected_task_parent="task:${task_prefix_lower}:${task_number}"
# shellcheck disable=SC2016  # $id is a jq variable.
if ! "$jq_bin" -e --arg id "$expected_task_parent" \
    '[.parent_links[]? | select(.relation == "task") | .id] | sort | unique == [$id]' \
    "$receipt_json" >/dev/null 2>&1 \
    || ! "$jq_bin" -e --arg id "$expected_task_parent" \
        '[.parent_links[]? | select(.relation == "task") | .id] | sort | unique == [$id]' \
        "$review_json" >/dev/null 2>&1; then
    add_finding "task_identity_mismatch:${task}"
fi

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
            validate_canonical_evolution "$classification"
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
            if [[ "$approval_reviewer" != "$signed_review_reviewer" ]]; then
                add_finding "no_canon_change_reviewer_mismatch:${signed_review_reviewer}:${approval_reviewer}"
            fi
            no_canon_evidence="$(jq_raw '.no_canon_change.evidence' "$review_json")"
            approval_time="$(jq_raw '.no_canon_change.reviewer_approval.approved_at' "$review_json")"
            if ! valid_timestamp_shape "$approval_time"; then
                add_finding 'no_canon_change_invalid_approved_at'
            fi
            if ! validate_no_canon_decision "$no_canon_evidence" "$approval_reviewer" \
                "$approval_time"; then
                add_finding 'no_canon_change_decision_not_authenticated'
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
