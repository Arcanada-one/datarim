#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT=c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae
IMAGE='python:3.12-bookworm@sha256:80f5d259a5969c86f6c92145d572de4a68c68e0edd28d4367dec0fb411b42af3'
EVENT="" CANDIDATE="" DEPLOY_KEY="" OUTPUT=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --event) EVENT=$2; shift 2 ;;
        --candidate) CANDIDATE=$2; shift 2 ;;
        --deploy-key) DEPLOY_KEY=$2; shift 2 ;;
        --output) OUTPUT=$2; shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done
for value in EVENT CANDIDATE DEPLOY_KEY OUTPUT; do
    [ -n "${!value}" ] || { echo "ERROR: --${value,,} is required" >&2; exit 2; }
done
for command in curl docker gh git jq sha256sum ssh-keygen; do
    command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 2; }
done

scratch=$(mktemp -d)
trap 'rm -f -- "$DEPLOY_KEY"; rm -rf -- "$scratch"' EXIT
head_sha=$(jq -er '.workflow_run.head_sha' "$EVENT")
conclusion=$(jq -er '.workflow_run.conclusion' "$EVENT")
event=$(jq -er '.workflow_run.event' "$EVENT")
head_repository=$(jq -er '.workflow_run.head_repository.full_name' "$EVENT")
pr_count=$(jq -er '.workflow_run.pull_requests | length' "$EVENT")
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: invalid candidate SHA" >&2; exit 1; }
if [ "$conclusion" != success ] || [ "$event" != pull_request ] \
    || [ "$head_repository" != Arcanada-one/datarim ] || [ "$pr_count" -ne 1 ]; then
    echo "ERROR: untrusted workflow_run identity" >&2
    exit 1
fi
git init --quiet "$CANDIDATE"
git -C "$CANDIDATE" remote add origin https://github.com/Arcanada-one/datarim.git
git -C "$CANDIDATE" fetch --quiet --depth=1 origin "$head_sha"
git -C "$CANDIDATE" checkout --quiet --detach "$head_sha"
[ "$(git -C "$CANDIDATE" rev-parse HEAD)" = "$head_sha" ] \
    || { echo "ERROR: candidate checkout mismatch" >&2; exit 1; }

knowledge="$scratch/knowledge"
comments="$scratch/comments"
cache="$scratch/cache"
mkdir -p "$comments" "$cache"
gh api meta --jq '.ssh_keys[] | "github.com " + .' >"$scratch/known_hosts"
GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$scratch/known_hosts" \
    git clone --filter=blob:none --no-checkout --quiet \
    git@github.com:Arcanada-one/talomnia-knowledge.git "$knowledge"
GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$scratch/known_hosts" \
    git -C "$knowledge" fetch --quiet --depth=1 origin "$SNAPSHOT"
git -C "$knowledge" checkout --quiet --detach "$SNAPSHOT"
rm -f -- "$DEPLOY_KEY"
unset GIT_SSH_COMMAND

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

manifest="$CANDIDATE/datarim/insights/TALO-0001-research-authority-audit.json"
insights="$CANDIDATE/datarim/insights/INSIGHTS-TALO-0001.md"
validator="$CANDIDATE/dev-tools/check-research-authority-audit.py"
for path in "$manifest" "$insights" "$validator"; do
    [ -f "$path" ] || { echo "ERROR: candidate input missing" >&2; exit 1; }
done

run_validator() {
    local manifest_path=$1 insights_path=$2 expected_status=$3 expected_text=$4
    local result="$scratch/result"
    set +e
    docker run --rm --network none --read-only --user 65534:65534 \
        --memory 256m --cpus 1 --pids-limit 64 --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=16m \
        -e PYTHONDONTWRITEBYTECODE=1 \
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
        -e GIT_CONFIG_VALUE_0=/knowledge \
        -v "$CANDIDATE:/candidate:ro" -v "$knowledge:/knowledge:ro" \
        -v "$comments:/comments:ro" -v "$cache:/cache:ro" \
        -v "$scratch:/inputs:ro" "$IMAGE" \
        python3 /candidate/dev-tools/check-research-authority-audit.py \
        --expected-task-id TALO-0001 --manifest "$manifest_path" \
        --insights "$insights_path" --knowledge-root /knowledge \
        --comment-json 5347868439=/comments/5347868439.json \
        --comment-json 5347971637=/comments/5347971637.json \
        --external-cache-dir /cache >"$result" 2>&1
    local status=$?
    set -e
    if [ "$status" -ne "$expected_status" ] \
        || ! grep -Fqx -- "$expected_text" "$result"; then
        echo "ERROR: sandboxed verdict mismatch" >&2
        : >"$result"
        exit 1
    fi
    : >"$result"
}

run_validator /candidate/datarim/insights/TALO-0001-research-authority-audit.json \
    /candidate/datarim/insights/INSIGHTS-TALO-0001.md 0 \
    'research_authority_audit=MET items=66 candidates=19 external_pins=8'

mkdir -p "$scratch/mutants"
jq 'del(.reviews[] | select(.id=="R2")) | .item_table.expected_rows=28' "$manifest" >"$scratch/mutants/items.json"
jq 'del(.candidates[-1])' "$manifest" >"$scratch/mutants/candidates.json"
jq 'del(.external_pins[-1])' "$manifest" >"$scratch/mutants/external.json"
jq '(.derived_records[0].evidence_path)="replacement.json"' "$manifest" >"$scratch/mutants/derived.json"
jq 'del(.comments[-1])' "$manifest" >"$scratch/mutants/comments.json"
jq '.task_id="TALO-9999"' "$manifest" >"$scratch/mutants/task.json"
jq '.knowledge_snapshot="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$manifest" >"$scratch/mutants/snapshot.json"
for mutant in items candidates external derived comments task snapshot; do
    run_validator "/inputs/mutants/$mutant.json" \
        /candidate/datarim/insights/INSIGHTS-TALO-0001.md 1 \
        'research_authority_audit=NOT_MET'
done

validator_digest=$(sha256sum "$validator" | cut -d' ' -f1)
manifest_digest=$(sha256sum "$manifest" | cut -d' ' -f1)
mutation_digest=$(sha256sum "$scratch"/mutants/*.json | sha256sum | cut -d' ' -f1)
jq -n --arg head "$head_sha" --arg knowledge "$SNAPSHOT" \
    --arg validator "$validator_digest" --arg manifest "$manifest_digest" \
    --arg mutations "$mutation_digest" \
    '{schema_version:1,verdict:"MET",head_sha:$head,knowledge_snapshot:$knowledge,validator_sha256:$validator,manifest_sha256:$manifest,mutation_set_sha256:$mutations,counts:{items:66,candidates:19,external_pins:8,derived_records:3,comments:2,mutants:7}}' \
    >"$OUTPUT"
