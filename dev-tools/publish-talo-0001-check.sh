#!/usr/bin/env bash
set -euo pipefail

conclusion=failure
summary='Trusted replay did not produce a sealed attestation.'
expected_nonce=$(
    printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        "$TRUSTED_RUN_ID" "$TRUSTED_RUN_ATTEMPT" "$TRUSTED_WORKFLOW_SHA" \
        "$SOURCE_RUN_ID" "$SOURCE_RUN_ATTEMPT" "$HEAD_SHA" "$BASE_SHA" \
        | sha256sum | cut -d' ' -f1
)
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
gh api --method POST "repos/Arcanada-one/datarim/check-runs" \
    -f name='talo-0001-privileged-replay' -f head_sha="$HEAD_SHA" \
    -f status=completed -f conclusion="$conclusion" \
    -f 'output[title]=TALO-0001 trusted replay' \
    -f "output[summary]=$summary" >/dev/null
[ "$conclusion" = success ]
