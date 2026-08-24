#!/usr/bin/env bash
set -euo pipefail

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
for command in curl docker gh git jq sha256sum; do
    command -v "$command" >/dev/null || { echo "ERROR: missing $command" >&2; exit 2; }
done

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
"$TRUSTED_ROOT/dev-tools/preflight-talo-0001-workflow-run.sh" "$EVENT" >/dev/null
head_sha=$(jq -er '.workflow_run.head_sha' "$EVENT")
actual_evaluator_sha=$(sha256sum "$TRUSTED_EVALUATOR" | cut -d' ' -f1)
[ "$actual_evaluator_sha" = "$TRUSTED_EVALUATOR_SHA256" ] \
    || { echo "ERROR: trusted evaluator digest mismatch" >&2; exit 1; }
[ -d "$KNOWLEDGE_ROOT" ] \
    || { echo "ERROR: trusted knowledge snapshot unavailable" >&2; exit 1; }
actual_snapshot=$(GIT_NO_REPLACE_OBJECTS=1 git -C "$KNOWLEDGE_ROOT" rev-parse HEAD)
[ "$actual_snapshot" = "$SNAPSHOT" ] \
    || { echo "ERROR: trusted knowledge snapshot mismatch" >&2; exit 1; }
git init --quiet "$CANDIDATE"
git -C "$CANDIDATE" remote add origin https://github.com/Arcanada-one/datarim.git
git -C "$CANDIDATE" fetch --quiet --depth=1 origin "$head_sha"
git -C "$CANDIDATE" checkout --quiet --detach "$head_sha"
[ "$(git -C "$CANDIDATE" rev-parse HEAD)" = "$head_sha" ] \
    || { echo "ERROR: candidate checkout mismatch" >&2; exit 1; }

comments="$scratch/comments"
cache="$scratch/cache"
mkdir -p "$comments" "$cache"

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
candidate_validator="$CANDIDATE/dev-tools/check-research-authority-audit.py"
for path in "$manifest" "$insights" "$candidate_validator"; do
    [ -f "$path" ] || { echo "ERROR: candidate input missing" >&2; exit 1; }
done

run_validator() {
    local case_dir=$1 expected_status=$2 expected_text=$3
    local result="$scratch/result"
    set +e
    docker run --rm --network none --read-only --user 65534:65534 \
        --memory 256m --cpus 1 --pids-limit 64 --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=16m \
        -e PYTHONDONTWRITEBYTECODE=1 \
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory \
        -e GIT_CONFIG_VALUE_0=/knowledge \
        -v "$CANDIDATE:/candidate:ro" -v "$TRUSTED_ROOT:/trusted:ro" \
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
        || ! grep -Fqx -- "$expected_text" "$result"; then
        echo "ERROR: sandboxed verdict mismatch" >&2
        : >"$result"
        exit 1
    fi
    : >"$result"
}

mkdir -p "$scratch/sealed" "$scratch/cases"
cp "$manifest" "$scratch/sealed/baseline.json"
jq 'del(.reviews[] | select(.id=="R2")) | .item_table.expected_rows=28' "$manifest" >"$scratch/sealed/items.json"
jq 'del(.candidates[] | select(.revision_id=="tal-capability-design-systems@r1"))' "$manifest" >"$scratch/sealed/candidates.json"
jq 'del(.external_pins[] | select(.source_id=="S29"))' "$manifest" >"$scratch/sealed/external.json"
jq '(.derived_records[] | select(.id=="TALO-0032-planning-envelope") | .evidence_path)="replacement.json"' "$manifest" >"$scratch/sealed/derived.json"
jq 'del(.comments[] | select((.id|tostring)=="5347971637"))' "$manifest" >"$scratch/sealed/comments.json"
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
run_case "$scratch/sealed/items.json" 1 'finding=review_set_mismatch:missing=R2'
run_case "$scratch/sealed/candidates.json" 1 \
    'finding=candidate_set_mismatch:missing=tal-capability-design-systems@r1'
run_case "$scratch/sealed/external.json" 1 'finding=external_pin_set_mismatch:missing=S29'
run_case "$scratch/sealed/derived.json" 1 \
    'finding=derived_record_authority_mismatch:TALO-0032-planning-envelope'
run_case "$scratch/sealed/comments.json" 1 \
    'finding=comment_set_mismatch:missing=5347971637'
run_case "$scratch/sealed/task.json" 1 \
    'finding=task_id_mismatch:expected=TALO-0001:actual=TALO-9999'
run_case "$scratch/sealed/snapshot.json" 1 'finding=knowledge_snapshot_authority_mismatch'

candidate_validator_digest=$(sha256sum "$candidate_validator" | cut -d' ' -f1)
manifest_digest=$(sha256sum "$manifest" | cut -d' ' -f1)
mutation_digest=$(
    for mutant in items candidates external derived comments task snapshot; do
        sha256sum "$scratch/sealed/$mutant.json" | cut -d' ' -f1
    done | sha256sum | cut -d' ' -f1
)
jq -n --arg head "$head_sha" --arg knowledge "$SNAPSHOT" \
    --arg evaluator "$TRUSTED_EVALUATOR_SHA256" \
    --arg candidate_validator "$candidate_validator_digest" \
    --arg manifest "$manifest_digest" \
    --arg mutations "$mutation_digest" \
    '{schema_version:1,verdict:"MET",head_sha:$head,knowledge_snapshot:$knowledge,trusted_evaluator_sha256:$evaluator,candidate_validator_sha256:$candidate_validator,manifest_sha256:$manifest,mutation_set_sha256:$mutations,counts:{items:66,candidates:19,external_pins:8,derived_records:3,comments:2,mutants:7}}' \
    >"$OUTPUT"
