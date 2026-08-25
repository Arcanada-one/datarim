#!/usr/bin/env bash
set -euo pipefail

API_VERSION=2022-11-28

live_main_commit() {
    local response
    response=$(gh api -H "X-GitHub-Api-Version: $API_VERSION" \
        repos/Arcanada-one/datarim/git/ref/heads/main) || return 1
    jq -er '
        select(type == "object" and (keys | sort) == ["node_id","object","ref","url"])
        | select(.ref == "refs/heads/main")
        | select(.node_id | type == "string" and length > 0)
        | select(.url == "https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main")
        | .object
        | select(type == "object" and (keys | sort) == ["sha","type","url"])
        | select(.type == "commit")
        | select(.url == ("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + .sha))
        | .sha
        | select(type == "string" and test("^[0-9a-f]{40}$"))
    ' <<<"$response"
}

conclusion=failure
summary='Trusted replay did not produce a sealed attestation.'
expected_nonce=$(
    printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        "$TRUSTED_RUN_ID" "$TRUSTED_RUN_ATTEMPT" "$TRUSTED_WORKFLOW_SHA" \
        "$SOURCE_RUN_ID" "$SOURCE_RUN_ATTEMPT" "$HEAD_SHA" "$BASE_SHA" \
        | sha256sum | cut -d' ' -f1
)
[ "$expected_nonce" = "$EXPECTED_EXECUTION_NONCE" ] || {
    echo "ERROR: trusted execution nonce mismatch" >&2
    exit 1
}
[ "$BASE_SHA" = "$TRUSTED_WORKFLOW_SHA" ] || {
    echo "ERROR: source base is not current trusted main" >&2
    exit 1
}
[[ "$CHECK_RUN_ID" =~ ^[1-9][0-9]*$ ]]
current_check=$(gh api "repos/Arcanada-one/datarim/check-runs/$CHECK_RUN_ID")
jq -e --argjson id "$CHECK_RUN_ID" --arg head "$HEAD_SHA" \
    --arg nonce "$expected_nonce" \
    'select(.id == $id and .name == "talo-0001-privileged-replay" and .head_sha == $head and .external_id == $nonce and .status == "in_progress")' \
    <<<"$current_check" >/dev/null
attestation_size=$(stat -c '%s' "$ATTESTATION" 2>/dev/null || true)
attestation_owner=$(stat -c '%u' "$ATTESTATION" 2>/dev/null || true)
attestation_mode=$(stat -c '%a' "$ATTESTATION" 2>/dev/null || true)
if [ -f "$ATTESTATION" ] && [ ! -L "$ATTESTATION" ] \
    && [[ "$attestation_size" =~ ^[1-9][0-9]*$ ]] \
    && [ "$attestation_size" -le 8192 ] \
    && [ "$attestation_owner" = "$(id -u)" ] \
    && [ "$attestation_mode" = 600 ] \
    && jq -e --arg head "$HEAD_SHA" --arg base "$BASE_SHA" \
    --arg controller "$TRUSTED_WORKFLOW_SHA" \
    --argjson trusted_run_id "$TRUSTED_RUN_ID" \
    --argjson trusted_run_attempt "$TRUSTED_RUN_ATTEMPT" \
    --argjson source_run_id "$SOURCE_RUN_ID" \
    --argjson source_run_attempt "$SOURCE_RUN_ATTEMPT" \
    --arg nonce "$expected_nonce" \
    '.verdict == "MET" and .head_sha == $head and .base_sha == $base and .controller_commit == $controller and .trusted_run_id == $trusted_run_id and .trusted_run_attempt == $trusted_run_attempt and .source_run_id == $source_run_id and .source_run_attempt == $source_run_attempt and .execution_nonce_sha256 == $nonce and .knowledge_snapshot == "c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae" and .trusted_evaluator_sha256 == "a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a" and (.candidate_validator_object_sha256 | test("^[0-9a-f]{64}$")) and (.manifest_object_sha256 | test("^[0-9a-f]{64}$")) and (.mutation_set_sha256 | test("^[0-9a-f]{64}$")) and .counts == {items:66,candidates:19,external_pins:8,derived_records:3,comments:2,mutants:7}' \
    "$ATTESTATION" >/dev/null; then
    conclusion=success
    summary=$(jq -c '{head_sha,base_sha,controller_commit,trusted_run_id,trusted_run_attempt,source_run_id,source_run_attempt,execution_nonce_sha256,knowledge_snapshot,trusted_evaluator_sha256,candidate_validator_object_sha256,manifest_object_sha256,mutation_set_sha256,counts}' "$ATTESTATION")
fi
if [ "$conclusion" = success ]; then
    current_main=$(live_main_commit || true)
    if [ "$current_main" != "$TRUSTED_WORKFLOW_SHA" ]; then
        conclusion=failure
        summary='Trusted controller is no longer verified live main.'
    fi
fi
gh api --method PATCH \
    "repos/Arcanada-one/datarim/check-runs/$CHECK_RUN_ID" \
    -f status=completed -f conclusion="$conclusion" \
    -f 'output[title]=TALO-0001 trusted replay' \
    -f "output[summary]=$summary" >/dev/null
[ "$conclusion" = success ]
