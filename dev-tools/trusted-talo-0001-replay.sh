#!/usr/bin/env bash
set -euo pipefail

API_VERSION=2022-11-28
SNAPSHOT=c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae
IMAGE='python:3.12-bookworm@sha256:80f5d259a5969c86f6c92145d572de4a68c68e0edd28d4367dec0fb411b42af3'
KNOWLEDGE_ROOT=/srv/talo-0001-trusted/knowledge
TRUSTED_EVALUATOR_SHA256=a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a
TRUSTED_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TRUSTED_EVALUATOR="$TRUSTED_ROOT/dev-tools/check-talo-0001-trusted-authority.py"
EVENT="" CANDIDATE="" OUTPUT=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --event) EVENT=$2; shift 2 ;;
        --candidate) CANDIDATE=$2; shift 2 ;;
        --output) OUTPUT=$2; shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done
for value in EVENT CANDIDATE OUTPUT; do
    [ -n "${!value}" ] || { echo "ERROR: --${value,,} is required" >&2; exit 2; }
done
umask 077
if [ -L "$OUTPUT" ] || { [ -e "$OUTPUT" ] && [ ! -f "$OUTPUT" ]; }; then
    echo "ERROR: attestation output is not a regular path" >&2
    exit 2
fi
: >"$OUTPUT"
chmod 0600 "$OUTPUT"
for value in TALO_TRUSTED_RUN_ID TALO_TRUSTED_RUN_ATTEMPT \
    TALO_TRUSTED_WORKFLOW_SHA TALO_SOURCE_RUN_ID TALO_SOURCE_RUN_ATTEMPT \
    TALO_BASE_SHA TALO_EXECUTION_NONCE; do
    [ -n "${!value:-}" ] || { echo "ERROR: missing trusted run binding: $value" >&2; exit 2; }
done
for command in chmod cmp curl docker gh git id jq mktemp mv realpath sha256sum; do
    command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 2; }
done

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

require_live_main() {
    local current_main
    current_main=$(live_main_commit) || {
        echo "ERROR: live trusted main could not be verified" >&2
        return 1
    }
    [ "$current_main" = "$TALO_TRUSTED_WORKFLOW_SHA" ] || {
        echo "ERROR: trusted controller is no longer live main" >&2
        return 1
    }
}

if ! [[ "$TALO_TRUSTED_RUN_ID" =~ ^[1-9][0-9]*$ ]] \
    || ! [[ "$TALO_TRUSTED_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]] \
    || ! [[ "$TALO_SOURCE_RUN_ID" =~ ^[1-9][0-9]*$ ]] \
    || ! [[ "$TALO_SOURCE_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]] \
    || ! [[ "$TALO_TRUSTED_WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]] \
    || ! [[ "$TALO_BASE_SHA" =~ ^[0-9a-f]{40}$ ]] \
    || ! [[ "$TALO_EXECUTION_NONCE" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: invalid trusted run binding" >&2
    exit 2
fi
require_live_main || exit 1
[ "$TALO_BASE_SHA" = "$TALO_TRUSTED_WORKFLOW_SHA" ] || {
    echo "ERROR: source base is not current trusted main" >&2
    exit 1
}

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
"$TRUSTED_ROOT/dev-tools/preflight-talo-0001-workflow-run.sh" "$EVENT" >/dev/null
head_sha=$(jq -er '.workflow_run.head_sha' "$EVENT")
source_run_id=$(jq -er '.workflow_run.id' "$EVENT")
source_run_attempt=$(jq -er '.workflow_run.run_attempt' "$EVENT")
base_sha=$(jq -er '.workflow_run.pull_requests[0].base.sha' "$EVENT")
if [ "$source_run_id" != "$TALO_SOURCE_RUN_ID" ] \
    || [ "$source_run_attempt" != "$TALO_SOURCE_RUN_ATTEMPT" ] \
    || [ "$base_sha" != "$TALO_BASE_SHA" ]; then
    echo "ERROR: event run binding mismatch" >&2
    exit 1
fi
controller_commit=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$TRUSTED_ROOT" rev-parse HEAD)
[ "$controller_commit" = "$TALO_TRUSTED_WORKFLOW_SHA" ] \
    || { echo "ERROR: trusted controller commit mismatch" >&2; exit 1; }
execution_nonce_sha256=$(
    printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        "$TALO_TRUSTED_RUN_ID" "$TALO_TRUSTED_RUN_ATTEMPT" \
        "$TALO_TRUSTED_WORKFLOW_SHA" "$TALO_SOURCE_RUN_ID" \
        "$TALO_SOURCE_RUN_ATTEMPT" "$head_sha" "$TALO_BASE_SHA" \
        | sha256sum | cut -d' ' -f1
)
[ "$execution_nonce_sha256" = "$TALO_EXECUTION_NONCE" ] || {
    echo "ERROR: trusted execution nonce mismatch" >&2
    exit 1
}
actual_evaluator_sha=$(sha256sum "$TRUSTED_EVALUATOR" | cut -d' ' -f1)
[ "$actual_evaluator_sha" = "$TRUSTED_EVALUATOR_SHA256" ] \
    || { echo "ERROR: trusted evaluator digest mismatch" >&2; exit 1; }
[ -d "$KNOWLEDGE_ROOT" ] \
    || { echo "ERROR: trusted knowledge snapshot unavailable" >&2; exit 1; }
actual_snapshot=$(
    GIT_NO_REPLACE_OBJECTS=1 git -c safe.directory="$KNOWLEDGE_ROOT" \
        -C "$KNOWLEDGE_ROOT" rev-parse HEAD
)
[ "$actual_snapshot" = "$SNAPSHOT" ] \
    || { echo "ERROR: trusted knowledge snapshot mismatch" >&2; exit 1; }
sandbox_uid=$(id -u)
sandbox_gid=$(id -g)
[ "$sandbox_uid" -ne 0 ] \
    || { echo "ERROR: trusted replay must not run as root" >&2; exit 1; }
require_live_main || exit 1
GIT_NO_REPLACE_OBJECTS=1 git init --quiet "$CANDIDATE"
GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" remote add origin \
    https://github.com/Arcanada-one/datarim.git
GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" fetch --quiet --depth=1 origin \
    "$head_sha"
actual_candidate_commit=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" \
    rev-parse "$head_sha^{commit}")
[ "$actual_candidate_commit" = "$head_sha" ] \
    || { echo "ERROR: candidate checkout mismatch" >&2; exit 1; }

comments="$scratch/comments"
cache="$scratch/cache"
candidate_materialized=$(realpath -m "$scratch/candidate")
mkdir -p "$comments" "$cache" "$candidate_materialized"

materialize_candidate_blob() {
    local relative=$1 destination entry mode type object_id recorded_path \
        object_digest materialized_digest
    case "$relative" in
        /*|*..*|*//*|*:*)
            echo "ERROR: candidate path is not canonical" >&2
            return 1
            ;;
    esac
    destination=$(realpath -m "$candidate_materialized/$relative")
    case "$destination" in
        "$candidate_materialized"/*) ;;
        *) echo "ERROR: candidate path escapes materialized root" >&2; return 1 ;;
    esac
    entry=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" ls-tree \
        "$head_sha" -- "$relative") || return 1
    if [ -z "$entry" ] || [[ "$entry" == *$'\n'* ]]; then
        echo "ERROR: candidate object is missing or ambiguous" >&2
        return 1
    fi
    IFS=$' \t' read -r mode type object_id recorded_path <<<"$entry"
    if [ "$mode" != 100644 ] || [ "$type" != blob ] \
        || ! [[ "$object_id" =~ ^[0-9a-f]{40}$ ]] \
        || [ "$recorded_path" != "$relative" ]; then
        echo "ERROR: candidate object is not an exact regular Git blob" >&2
        return 1
    fi
    mkdir -p "$(dirname "$destination")"
    if ! GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" cat-file blob \
        "$object_id" >"$destination"; then
        echo "ERROR: candidate Git object extraction failed" >&2
        return 1
    fi
    chmod 0400 "$destination"
    [ -f "$destination" ] && [ ! -L "$destination" ] || return 1
    object_digest=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" \
        cat-file blob "$object_id" | sha256sum | cut -d' ' -f1) || return 1
    materialized_digest=$(sha256sum -- "$destination" | cut -d' ' -f1) \
        || return 1
    [ "$object_digest" = "$materialized_digest" ] || {
        echo "ERROR: candidate materialization digest mismatch" >&2
        return 1
    }
    printf '%s\n' "$object_digest"
}

for comment_id in 5347868439 5347971637; do
    gh api "repos/Arcanada-one/talomnia-trace/issues/comments/$comment_id" \
        >"$comments/$comment_id.json"
done
while IFS=$'\t' read -r source_id repository commit source_path; do
    curl --fail --silent --show-error --location --max-time 20 \
        --max-filesize 16777216 --proto '=https' \
        "https://raw.githubusercontent.com/$repository/$commit/$source_path" \
        --output "$cache/$source_id.body"
done <<'PINS'
S20	GoogleChrome/lighthouse-ci	ebee453dad3f8acacd657a62ccc65e3296afb7d0	README.md
S21	GoogleChrome/lighthouse	2402ec45198dc590b2fb5f69b32fa358695d2145	docs/variability.md
S22	microsoft/playwright	12b611da20d21db663ee0c6be399b1bb854dead0	docs/src/emulation.md
S23	microsoft/playwright	12b611da20d21db663ee0c6be399b1bb854dead0	docs/src/test-snapshots-js.md
S24	microsoft/playwright	12b611da20d21db663ee0c6be399b1bb854dead0	docs/src/accessibility-testing-js.md
S27	backstage/backstage	1a705cad96f0fbd48d4f7fe7e92e8a45d6afbab7	docs/features/software-catalog/descriptor-format.md
S28	backstage/backstage	1a705cad96f0fbd48d4f7fe7e92e8a45d6afbab7	docs/features/software-catalog/creating-the-catalog-graph.md
S29	stryker-mutator/mutation-testing-elements	befa9a40328e7ca3756772eb8551987df1b3e85b	docs/mutant-states-and-metrics.md
PINS

manifest_relative=datarim/insights/TALO-0001-research-authority-audit.json
insights_relative=datarim/insights/INSIGHTS-TALO-0001.md
candidate_validator_relative=dev-tools/check-research-authority-audit.py
manifest="$candidate_materialized/$manifest_relative"
manifest_object_digest=$(materialize_candidate_blob "$manifest_relative") \
    || { echo "ERROR: candidate manifest object rejected" >&2; exit 1; }
materialize_candidate_blob "$insights_relative" >/dev/null \
    || { echo "ERROR: candidate insights object rejected" >&2; exit 1; }
candidate_validator_object_digest=$(
    materialize_candidate_blob "$candidate_validator_relative"
) || { echo "ERROR: candidate validator object rejected" >&2; exit 1; }

run_validator() {
    local case_dir=$1 expected_status=$2 expected_text=$3
    local result="$scratch/result" expected="$scratch/expected"
    printf '%s\n' "$expected_text" >"$expected"
    set +e
    docker run --rm --network none --read-only \
        --user "$sandbox_uid:$sandbox_gid" \
        --memory 256m --cpus 1 --pids-limit 64 --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=16m \
        -e PYTHONDONTWRITEBYTECODE=1 \
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
        -e GIT_CONFIG_VALUE_0=/knowledge \
        -v "$candidate_materialized:/candidate:ro" \
        -v "$TRUSTED_ROOT:/trusted:ro" \
        -v "$KNOWLEDGE_ROOT:/knowledge:ro" \
        -v "$comments:/comments:ro" -v "$cache:/cache:ro" \
        -v "$case_dir:/case:ro" "$IMAGE" \
        python3 /trusted/dev-tools/check-talo-0001-trusted-authority.py \
        --expected-task-id TALO-0001 --manifest /case/manifest.json \
        --insights /candidate/datarim/insights/INSIGHTS-TALO-0001.md \
        --knowledge-root /knowledge \
        --comment-json 5347868439=/comments/5347868439.json \
        --comment-json 5347971637=/comments/5347971637.json \
        --external-cache-dir /cache >"$result" 2>&1
    local status=$?
    set -e
    if [ "$status" -ne "$expected_status" ] \
        || ! cmp -s -- "$expected" "$result"; then
        echo "ERROR: sandboxed verdict mismatch" >&2
        : >"$result"; : >"$expected"
        exit 1
    fi
    : >"$result"; : >"$expected"
}

mkdir -p "$scratch/sealed" "$scratch/cases"
cp "$manifest" "$scratch/sealed/baseline.json"
jq '(.reviews[] | select(.id=="R1") | .mapping_source_git_blob)="0000000000000000000000000000000000000000"' "$manifest" >"$scratch/sealed/mapping.json"
jq '(.candidates[] | select(.revision_id=="tal-role-design-lead@r4") | .path)="graph/data/local/tal-role-developer@r4.json"' "$manifest" >"$scratch/sealed/candidate.json"
jq '(.external_pins[] | select(.source_id=="S29") | .git_blob)="0000000000000000000000000000000000000000"' "$manifest" >"$scratch/sealed/external.json"
jq '(.derived_records[] | select(.id=="TALO-0032-planning-envelope") | .evidence_path)="replacement.json"' "$manifest" >"$scratch/sealed/derived.json"
jq '(.comments[] | select((.id|tostring)=="5347971637") | .body_sha256)="0000000000000000000000000000000000000000000000000000000000000000"' "$manifest" >"$scratch/sealed/comment.json"
jq '.task_id="TALO-9999"' "$manifest" >"$scratch/sealed/task.json"
jq '.knowledge_snapshot="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$manifest" >"$scratch/sealed/snapshot.json"

run_case() {
    local source=$1 expected_status=$2 expected_text=$3
    local case_dir
    case_dir=$(mktemp -d "$scratch/cases/case.XXXXXXXX")
    install -m 0400 "$source" "$case_dir/manifest.json"
    run_validator "$case_dir" "$expected_status" "$expected_text"
}
run_case "$scratch/sealed/baseline.json" 0 \
    'research_authority_audit=MET items=66 candidates=19 external_pins=8'
run_case "$scratch/sealed/mapping.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=review_authority_mismatch:R1\nfinding=source_blob_mismatch:R1-mapping'
run_case "$scratch/sealed/candidate.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=candidate_authority_mismatch:tal-role-design-lead@r4\nfinding=candidate_git_blob_mismatch:tal-role-design-lead@r4\nfinding=candidate_path_missing:tal-role-design-lead@r4'
run_case "$scratch/sealed/external.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=external_authority_mismatch:S29\nfinding=external_pin_blob_mismatch:S29'
run_case "$scratch/sealed/derived.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=derived_record_authority_mismatch:TALO-0032-planning-envelope\nfinding=derived_record_path_missing:TALO-0032-planning-envelope'
run_case "$scratch/sealed/comment.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=comment_authority_mismatch:5347971637\nfinding=comment_body_digest_mismatch:5347971637'
run_case "$scratch/sealed/task.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=task_id_mismatch:expected=TALO-0001:actual=TALO-9999'
run_case "$scratch/sealed/snapshot.json" 1 \
    $'research_authority_audit=NOT_MET\nfinding=knowledge_snapshot_authority_mismatch\nfinding=knowledge_snapshot_mismatch'

mutation_digest=$(
    for mutant in mapping candidate external derived comment task snapshot; do
        sha256sum "$scratch/sealed/$mutant.json" | cut -d' ' -f1
    done | sha256sum | cut -d' ' -f1
)
attestation_tmp=$(mktemp "${OUTPUT}.tmp.XXXXXXXX")
jq -n --arg head "$head_sha" --arg base "$TALO_BASE_SHA" \
    --arg controller "$TALO_TRUSTED_WORKFLOW_SHA" \
    --argjson trusted_run_id "$TALO_TRUSTED_RUN_ID" \
    --argjson trusted_run_attempt "$TALO_TRUSTED_RUN_ATTEMPT" \
    --argjson source_run_id "$TALO_SOURCE_RUN_ID" \
    --argjson source_run_attempt "$TALO_SOURCE_RUN_ATTEMPT" \
    --arg nonce "$execution_nonce_sha256" --arg knowledge "$SNAPSHOT" \
    --arg evaluator "$TRUSTED_EVALUATOR_SHA256" \
    --arg candidate_validator "$candidate_validator_object_digest" \
    --arg manifest "$manifest_object_digest" \
    --arg mutations "$mutation_digest" \
    '{schema_version:1,verdict:"MET",head_sha:$head,base_sha:$base,controller_commit:$controller,trusted_run_id:$trusted_run_id,trusted_run_attempt:$trusted_run_attempt,source_run_id:$source_run_id,source_run_attempt:$source_run_attempt,execution_nonce_sha256:$nonce,knowledge_snapshot:$knowledge,trusted_evaluator_sha256:$evaluator,candidate_validator_object_sha256:$candidate_validator,manifest_object_sha256:$manifest,mutation_set_sha256:$mutations,counts:{items:66,candidates:19,external_pins:8,derived_records:3,comments:2,mutants:7}}' \
    >"$attestation_tmp"
chmod 0600 "$attestation_tmp"
mv -f -- "$attestation_tmp" "$OUTPUT"
