#!/usr/bin/env bash
set -euo pipefail

conclusion=failure
summary='Trusted replay did not produce a sealed attestation.'
if [ -f "$ATTESTATION" ] && jq -e --arg head "$HEAD_SHA" \
    '.verdict == "MET" and .head_sha == $head and .knowledge_snapshot == "c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae" and .trusted_evaluator_sha256 == "a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a" and (.candidate_validator_object_sha256 | test("^[0-9a-f]{64}$")) and (.manifest_object_sha256 | test("^[0-9a-f]{64}$")) and (.mutation_set_sha256 | test("^[0-9a-f]{64}$")) and .counts == {items:66,candidates:19,external_pins:8,derived_records:3,comments:2,mutants:7}' \
    "$ATTESTATION" >/dev/null; then
    conclusion=success
    summary=$(jq -c '{head_sha,knowledge_snapshot,trusted_evaluator_sha256,candidate_validator_object_sha256,manifest_object_sha256,mutation_set_sha256,counts}' "$ATTESTATION")
fi
gh api --method POST "repos/Arcanada-one/datarim/check-runs" \
    -f name='talo-0001-privileged-replay' -f head_sha="$HEAD_SHA" \
    -f status=completed -f conclusion="$conclusion" \
    -f 'output[title]=TALO-0001 trusted replay' \
    -f "output[summary]=$summary" >/dev/null
[ "$conclusion" = success ]
