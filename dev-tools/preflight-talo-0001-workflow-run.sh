#!/usr/bin/env bash
set -euo pipefail

event_file=${1:?event path required}
head_sha=$(jq -er '.workflow_run.head_sha' "$event_file")
conclusion=$(jq -er '.workflow_run.conclusion' "$event_file")
event=$(jq -er '.workflow_run.event' "$event_file")
head_repository=$(jq -er '.workflow_run.head_repository.full_name' "$event_file")
pr_count=$(jq -er '.workflow_run.pull_requests | length' "$event_file")
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || exit 1
if [ "$conclusion" != success ] || [ "$event" != pull_request ] \
    || [ "$head_repository" != Arcanada-one/datarim ] || [ "$pr_count" -ne 1 ]; then
    exit 1
fi
printf 'trusted_workflow_run=ACCEPTED head_sha=%s\n' "$head_sha"
