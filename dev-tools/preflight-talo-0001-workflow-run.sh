#!/usr/bin/env bash
set -euo pipefail

event_file=${1:?event path required}
head_sha=$(jq -er '.workflow_run.head_sha' "$event_file")
conclusion=$(jq -er '.workflow_run.conclusion' "$event_file")
event=$(jq -er '.workflow_run.event' "$event_file")
head_repository=$(jq -er '.workflow_run.head_repository.full_name' "$event_file")
repository=$(jq -er '.workflow_run.repository.full_name' "$event_file")
workflow_id=$(jq -er '.workflow_run.workflow_id' "$event_file")
workflow_name=$(jq -er '.workflow_run.name' "$event_file")
workflow_path=$(jq -er '.workflow_run.path' "$event_file")
pr_count=$(jq -er '.workflow_run.pull_requests | length' "$event_file")
pr_head_sha=$(jq -er '.workflow_run.pull_requests[0].head.sha' "$event_file")
pr_number=$(jq -er '.workflow_run.pull_requests[0].number' "$event_file")
pr_head_ref=$(jq -er '.workflow_run.pull_requests[0].head.ref' "$event_file")
pr_head_repository=$(jq -er \
    '.workflow_run.pull_requests[0].head.repo.url | sub("https://api.github.com/repos/"; "")' \
    "$event_file")
pr_base_ref=$(jq -er '.workflow_run.pull_requests[0].base.ref' "$event_file")
pr_base_repository=$(jq -er \
    '.workflow_run.pull_requests[0].base.repo.url | sub("https://api.github.com/repos/"; "")' \
    "$event_file")
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || exit 1
if [ "$conclusion" != success ] || [ "$event" != pull_request ] \
    || [ "$head_repository" != Arcanada-one/datarim ] \
    || [ "$repository" != Arcanada-one/datarim ] \
    || [ "$workflow_id" -ne 270931528 ] \
    || [ "$workflow_name" != dev-tools-lint ] \
    || [ "$workflow_path" != .github/workflows/dev-tools-lint.yml ] \
    || [ "$head_sha" != "$pr_head_sha" ] \
    || [ "$pr_number" -ne 394 ] \
    || [ "$pr_head_ref" != research/TALO-0001-frontend-design ] \
    || [ "$pr_head_repository" != Arcanada-one/datarim ] \
    || [ "$pr_base_ref" != main ] \
    || [ "$pr_base_repository" != Arcanada-one/datarim ] \
    || [ "$pr_count" -ne 1 ]; then
    exit 1
fi
printf 'trusted_workflow_run=ACCEPTED head_sha=%s\n' "$head_sha"
