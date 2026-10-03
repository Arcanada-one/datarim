#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf '%s\n' 'usage: check-github-actions-execution.sh --repo OWNER/REPO --run-id ID --workflow NAME_OR_ID --required-job NAME_OR_ID --expected-sha FULL_SHA [--required-conclusion success] [--format text|json]'
}

repo='' run_id='' workflow='' required_job='' expected_sha='' required='success' format='text'
while (($#)); do
    case "$1" in
        --repo) repo="${2-}"; shift 2 ;;
        --run-id) run_id="${2-}"; shift 2 ;;
        --workflow) workflow="${2-}"; shift 2 ;;
        --required-job) required_job="${2-}"; shift 2 ;;
        --expected-sha) expected_sha="${2-}"; shift 2 ;;
        --required-conclusion) required="${2-}"; shift 2 ;;
        --format) format="${2-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

emit() {
    local classification="$1" exit_code="$2" jobs="${3:-0}" steps="${4:-0}"
    if [[ "$format" == json ]]; then
        jq -cn --arg classification "$classification" --arg repo "$repo" \
            --arg workflow "$workflow" --arg required_job "$required_job" --arg sha "$expected_sha" \
            --arg source "github-api" --arg workflow_id "${workflow_id:-}" --arg run_id "${observed_run_id:-}" \
            --arg run_attempt "${run_attempt:-}" --arg event "${run_event:-}" --arg conclusion "${run_conclusion:-}" \
            --arg observed_at "${observed_at:-}" \
            --argjson jobs "$jobs" --argjson steps "$steps" \
            '{classification:$classification,evidence_source:$source,repository:$repo,workflow:$workflow,workflow_id:$workflow_id,required_job:$required_job,run_id:$run_id,run_attempt:$run_attempt,event:$event,conclusion:$conclusion,observed_at:$observed_at,expected_sha:$sha,jobs:$jobs,executed_steps:$steps}'
    else
        printf 'classification=%s evidence_source=github-api repository=%s workflow=%s workflow_id=%s required_job=%s run_id=%s run_attempt=%s event=%s conclusion=%s observed_at=%s expected_sha=%s jobs=%s executed_steps=%s\n' \
            "$classification" "$repo" "$workflow" "${workflow_id:-}" "$required_job" "${observed_run_id:-}" "${run_attempt:-}" "${run_event:-}" "${run_conclusion:-}" "${observed_at:-}" "$expected_sha" "$jobs" "$steps"
    fi
    exit "$exit_code"
}

command -v jq >/dev/null 2>&1 || { printf '%s\n' 'classification=indeterminate reason=missing_jq'; exit 2; }
[[ "$format" == text || "$format" == json ]] || emit indeterminate 2
[[ "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ && "$workflow" != '' && "$required_job" != '' && "$expected_sha" =~ ^[0-9a-fA-F]{40}$ ]] || emit indeterminate 2
[[ "$required" == success ]] || emit indeterminate 2

[[ "$run_id" =~ ^[1-9][0-9]*$ ]] || emit indeterminate 2

tmp=''
# shellcheck disable=SC2329
cleanup() { [[ -z "$tmp" ]] || rm -f "$tmp"; }
trap cleanup EXIT

command -v gh >/dev/null 2>&1 || emit indeterminate 2
tmp="$(mktemp -t github-actions-evidence.XXXXXX)"
run_json="$(gh api "/repos/${repo}/actions/runs/${run_id}" 2>/dev/null)" || emit indeterminate 2
jobs_json="$(gh api --paginate --slurp "/repos/${repo}/actions/runs/${run_id}/jobs?per_page=100" 2>/dev/null)" || emit indeterminate 2
jq -cn --arg repo "$repo" --argjson run "$run_json" --argjson pages "$jobs_json" '
  {schema_version:1,repository:$repo,
   workflow:{id:$run.workflow_id,name:$run.name,path:($run.path // "")},
   run:{id:$run.id,run_attempt:($run.run_attempt // 1),head_sha:$run.head_sha,status:$run.status,conclusion:$run.conclusion,event:$run.event,updated_at:$run.updated_at},
   jobs:([$pages[] | (.jobs // .workflow_jobs // [])[]])}' >"$tmp" || emit indeterminate 2
bundle="$tmp"

jq -e '
  .schema_version == 1 and
  (.repository | type == "string") and
  (.workflow | type == "object") and
  ((.workflow.id != null) or (.workflow.name | type == "string") or (.workflow.path | type == "string")) and
  (.run | type == "object") and (.run.head_sha | type == "string") and (.run.status | type == "string") and
  (.jobs | type == "array")
' "$bundle" >/dev/null 2>&1 || emit indeterminate 2

bundle_repo="$(jq -r '.repository' "$bundle")"
bundle_sha="$(jq -r '.run.head_sha' "$bundle")"
run_status="$(jq -r '.run.status' "$bundle")"
run_conclusion="$(jq -r '.run.conclusion // ""' "$bundle")"
workflow_id="$(jq -r '.workflow.id | tostring' "$bundle")"
observed_run_id="$(jq -r '.run.id | tostring' "$bundle")"
run_attempt="$(jq -r '.run.run_attempt | tostring' "$bundle")"
run_event="$(jq -r '.run.event // ""' "$bundle")"
observed_at="$(jq -r '.run.updated_at // ""' "$bundle")"
jobs="$(jq --arg job "$required_job" '[.jobs[] | select((.name == $job) or ((.id | tostring) == $job))] | length' "$bundle")"
total_jobs="$(jq '.jobs | length' "$bundle")"

[[ "$bundle_repo" == "$repo" ]] || emit indeterminate 2 "$jobs" 0
[[ "$bundle_sha" == "$expected_sha" ]] || emit sha-mismatch 1 "$jobs" 0

if ! jq -e --arg workflow "$workflow" '
  (.workflow.name == $workflow) or (.workflow.path == $workflow) or ((.workflow.id | tostring) == $workflow)
' "$bundle" >/dev/null; then
    emit workflow-mismatch 1 "$jobs" 0
fi

if [[ "$run_status" != completed ]]; then
    emit pending 1 "$jobs" 0
fi
if ((total_jobs == 0)); then
    [[ "$run_conclusion" == success ]] && emit indeterminate 2 0 0
    emit no-execution 1 0 0
fi
((jobs > 0)) || emit required-job-missing 1 0 0

executed_steps="$(jq --arg job "$required_job" '[.jobs[] | select((.name == $job) or ((.id | tostring) == $job)) | select((.runner_id // 0) > 0) | .steps[]? | select(.status == "completed" and .conclusion != "skipped")] | length' "$bundle")"
if ((executed_steps == 0)); then
    if [[ "$run_conclusion" == success ]]; then
        emit indeterminate 2 "$jobs" 0
    fi
    emit no-execution 1 "$jobs" 0
fi

required_jobs_green="$(jq --arg job "$required_job" '[.jobs[] | select((.name == $job) or ((.id | tostring) == $job)) | select(.conclusion != "success")] | length == 0' "$bundle")"
if [[ "$run_conclusion" == success && "$required_jobs_green" == true ]]; then
    emit executed-success 0 "$jobs" "$executed_steps"
fi
emit executed-failed 1 "$jobs" "$executed_steps"
