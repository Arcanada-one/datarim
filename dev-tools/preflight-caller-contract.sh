#!/usr/bin/env bash
# Fail-closed structural validation for registered preflight-check consumers.
# The caller job is intentionally capability-free: checkout plus this immutable
# action only. Vault, Ops Bot, Docker, and the deploy broker are never contacted.

set -euo pipefail
IFS=$'\n\t'

readonly REQUIRED_YQ_VERSION="v4.44.3"
readonly DATARIM_REPOSITORY="Arcanada-one/datarim"
readonly CONTRACT_JOB="preflight-caller-contract"
readonly DEPLOY_JOB="deploy"
readonly CONTRACT_ACTION="Arcanada-one/datarim/.github/actions/preflight-caller-contract"
readonly PREFLIGHT_ACTION="Arcanada-one/datarim/.github/actions/preflight-check"
readonly CHECKOUT_ACTION="actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
# shellcheck disable=SC2016 # GitHub expressions are intentionally literal.
readonly VAULT_ADDR_EXPRESSION='${{ vars.VAULT_ADDR }}'
# shellcheck disable=SC2016 # GitHub expressions are intentionally literal.
readonly WORKFLOW_SHA_EXPRESSION='${{ github.workflow_sha }}'
readonly OPS_BOT_URL="https://ops.arcanada.ai/events"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_env() {
    local name="$1"
    [ "${!name+x}" = x ] || fail "runtime.${name}: missing"
}

yaml_true() {
    local expression="$1"
    local field="$2"
    if ! "$yq_bin" eval -e "$expression" "$workflow_file" >/dev/null 2>&1; then
        fail "${field}: contract violation"
    fi
}

yaml_read() {
    local expression="$1"
    local field="$2"
    if ! YAML_VALUE="$("$yq_bin" eval -r "$expression" "$workflow_file" 2>/dev/null)"; then
        fail "${field}: invalid query target"
    fi
}

registry_read() {
    local expression="$1"
    local field="$2"
    if ! REGISTRY_VALUE="$("$yq_bin" eval -er "$expression" "$registry_file" 2>/dev/null)"; then
        fail "registry.${field}: missing consumer binding"
    fi
}

for required_name in \
    GITHUB_WORKSPACE \
    PREFLIGHT_CALLER_ACTION_REPOSITORY \
    PREFLIGHT_CALLER_ACTION_REF \
    PREFLIGHT_CALLER_GITHUB_REPOSITORY \
    PREFLIGHT_CALLER_WORKFLOW_REF \
    PREFLIGHT_CALLER_WORKFLOW_SHA \
    PREFLIGHT_CALLER_VAULT_ADDR \
    PREFLIGHT_CALLER_YQ_BIN; do
    require_env "$required_name"
done

yq_bin="$PREFLIGHT_CALLER_YQ_BIN"
if [ ! -f "$yq_bin" ] || [ ! -x "$yq_bin" ] || [ -L "$yq_bin" ]; then
    fail "tool.yq: required ${REQUIRED_YQ_VERSION} is unavailable"
fi
yq_version="$("$yq_bin" --version 2>/dev/null)"
[[ "$yq_version" =~ version[[:space:]]${REQUIRED_YQ_VERSION//./\.}$ ]] || \
    fail "tool.yq: required ${REQUIRED_YQ_VERSION} is unavailable"

action_repository="$PREFLIGHT_CALLER_ACTION_REPOSITORY"
action_ref="$PREFLIGHT_CALLER_ACTION_REF"
github_repository="$PREFLIGHT_CALLER_GITHUB_REPOSITORY"
workflow_ref="$PREFLIGHT_CALLER_WORKFLOW_REF"
workflow_sha="$PREFLIGHT_CALLER_WORKFLOW_SHA"
vault_addr="$PREFLIGHT_CALLER_VAULT_ADDR"

[ "$action_repository" = "$DATARIM_REPOSITORY" ] || fail "runtime.github.action_repository: unexpected"
[[ "$action_ref" =~ ^[0-9a-f]{40}$ ]] || fail "runtime.github.action_ref: immutable commit required"
[[ "$github_repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "runtime.github.repository: invalid"
[[ "$workflow_sha" =~ ^[0-9a-f]{40}$ ]] || fail "runtime.github.workflow_sha: immutable commit required"

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
registry_file="${script_root}/.github/actions/preflight-caller-contract/consumers.yml"
"$yq_bin" eval -e '."schema-version" == 1 and (.consumers | type == "!!map")' "$registry_file" >/dev/null 2>&1 || \
    fail "registry: invalid schema"
export REGISTRY_REPOSITORY="$github_repository"
registry_read '.consumers[strenv(REGISTRY_REPOSITORY)]."service-name"' "${github_repository}.service-name"
service_name="$REGISTRY_VALUE"
registry_read '.consumers[strenv(REGISTRY_REPOSITORY)]."ops-bot-agent"' "${github_repository}.ops-bot-agent"
ops_bot_agent="$REGISTRY_VALUE"
registry_read '.consumers[strenv(REGISTRY_REPOSITORY)]."ops-bot-key-secret-name"' "${github_repository}.ops-bot-key-secret-name"
ops_bot_key_secret_name="$REGISTRY_VALUE"
registry_read '.consumers[strenv(REGISTRY_REPOSITORY)]."deploy-if"' "${github_repository}.deploy-if"
deploy_if="$REGISTRY_VALUE"

[[ "$service_name" =~ ^[a-z0-9-]+$ ]] || fail "registry.${github_repository}.service-name: invalid"
[[ "$ops_bot_agent" =~ ^[a-z0-9-]+$ ]] || fail "registry.${github_repository}.ops-bot-agent: invalid"
[ "$ops_bot_agent" = "$service_name" ] || fail "registry.${github_repository}.ops-bot-agent: identity mismatch"
[[ "$ops_bot_key_secret_name" =~ ^[A-Z_][A-Z0-9_]*$ ]] || \
    fail "registry.${github_repository}.ops-bot-key-secret-name: invalid"
if [ -z "$deploy_if" ]; then
    fail "registry.${github_repository}: incomplete deploy binding"
fi

workflow_with_repository="${workflow_ref%@*}"
[ "$workflow_with_repository" != "$workflow_ref" ] || fail "runtime.github.workflow_ref: invalid"
case "$workflow_with_repository" in
    "$github_repository"/*) workflow_path="${workflow_with_repository#"$github_repository"/}" ;;
    *) fail "runtime.github.workflow_ref: repository mismatch" ;;
esac
[[ "$workflow_path" =~ ^\.github/workflows/[A-Za-z0-9_.-]+\.(yml|yaml)$ ]] || \
    fail "runtime.github.workflow_ref: workflow path invalid"

workflow_file="${GITHUB_WORKSPACE%/}/${workflow_path}"
if [ ! -f "$workflow_file" ] || [ -L "$workflow_file" ]; then
    fail "workflow: caller file unavailable"
fi
workspace_root="$(cd "$GITHUB_WORKSPACE" 2>/dev/null && pwd -P)" || fail "runtime.github.workspace: unavailable"
git_root="$(git -C "$workspace_root" rev-parse --show-toplevel 2>/dev/null)" || fail "runtime.github.workspace: git checkout required"
[ "$git_root" = "$workspace_root" ] || fail "runtime.github.workspace: checkout root mismatch"
head_sha="$(git -C "$workspace_root" rev-parse HEAD 2>/dev/null)" || fail "runtime.github.workflow_sha: checkout unavailable"
[ "$head_sha" = "$workflow_sha" ] || fail "runtime.github.workflow_sha: checkout mismatch"
git -C "$workspace_root" cat-file -e "${workflow_sha}:${workflow_path}" 2>/dev/null || fail "workflow: caller commit path unavailable"
committed_workflow_hash="$(git -C "$workspace_root" rev-parse "${workflow_sha}:${workflow_path}" 2>/dev/null)" || \
    fail "workflow: caller commit path unavailable"
working_workflow_hash="$(git -C "$workspace_root" hash-object "$workflow_file" 2>/dev/null)" || fail "workflow: caller file unreadable"
[ "$working_workflow_hash" = "$committed_workflow_hash" ] || fail "workflow: caller file differs from workflow_sha"
"$yq_bin" eval -e '.jobs | type == "!!map"' "$workflow_file" >/dev/null 2>&1 || fail "workflow: invalid YAML jobs map"

[ -n "$vault_addr" ] || fail "inputs.vault-addr: empty"
[[ ! "$vault_addr" =~ [[:space:]] ]] || fail "inputs.vault-addr: whitespace forbidden"
[[ "$vault_addr" =~ ^https?://[^/[:space:]]+ ]] || fail "inputs.vault-addr: HTTP(S) URL required"
authority="${vault_addr#*://}"
authority="${authority%%[/?#]*}"
[[ "$authority" != *"@"* ]] || fail "inputs.vault-addr: credentials forbidden"
port=""
if [[ "$authority" =~ ^\[[0-9A-Fa-f:.]+\](:([0-9]{1,5}))?$ ]]; then
    port="${BASH_REMATCH[2]:-}"
elif [[ "$authority" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:([0-9]{1,5}))?$ ]]; then
    port="${BASH_REMATCH[3]:-}"
else
    fail "inputs.vault-addr: valid authority required"
fi
if [ -n "$port" ] && (( 10#$port < 1 || 10#$port > 65535 )); then
    fail "inputs.vault-addr: valid port required"
fi

export EXPECTED_CONTRACT_USE="${CONTRACT_ACTION}@${action_ref}"
export EXPECTED_PREFLIGHT_USE="${PREFLIGHT_ACTION}@${action_ref}"
export EXPECTED_CHECKOUT_USE="$CHECKOUT_ACTION"
export EXPECTED_SERVICE_NAME="$service_name"
export EXPECTED_OPS_BOT_AGENT="$ops_bot_agent"
export EXPECTED_SECRET_NAME="$ops_bot_key_secret_name"
# shellcheck disable=SC2016 # GitHub expression delimiters are intentional.
export EXPECTED_SECRET_EXPRESSION='${{ secrets.'"${ops_bot_key_secret_name}"' }}'
export EXPECTED_VAULT_EXPRESSION="$VAULT_ADDR_EXPRESSION"
export EXPECTED_WORKFLOW_SHA_EXPRESSION="$WORKFLOW_SHA_EXPRESSION"
export EXPECTED_OPS_BOT_URL="$OPS_BOT_URL"
export EXPECTED_DEPLOY_IF="$deploy_if"

yaml_true '(.on | type) == "!!map" and (.on | has("pull_request")) and
    (((.on.pull_request | type) == "!!null") or
     (((.on.pull_request | type) == "!!map") and ((.on.pull_request | length) == 0)))' \
    ".on.pull_request"
yaml_true '.jobs."preflight-caller-contract" | type == "!!map"' ".jobs.${CONTRACT_JOB}"
yaml_true '.jobs.deploy | type == "!!map"' ".jobs.${DEPLOY_JOB}"
yaml_true '(.jobs."preflight-caller-contract" | keys | sort | join(",")) == "permissions,runs-on,steps,timeout-minutes"' \
    ".jobs.${CONTRACT_JOB}.capabilities"
yaml_true '.jobs."preflight-caller-contract"."runs-on" == "ubuntu-latest"' ".jobs.${CONTRACT_JOB}.runs-on"
yaml_true '.jobs."preflight-caller-contract"."timeout-minutes" == 5' ".jobs.${CONTRACT_JOB}.timeout-minutes"
yaml_true '(.jobs."preflight-caller-contract".permissions | keys | join(",")) == "contents" and
    .jobs."preflight-caller-contract".permissions.contents == "read"' ".jobs.${CONTRACT_JOB}.permissions"
yaml_true '.jobs."preflight-caller-contract".steps | length == 2' ".jobs.${CONTRACT_JOB}.steps"
yaml_true '(.jobs."preflight-caller-contract".steps[0] | keys | sort | join(",")) == "uses,with" and
    .jobs."preflight-caller-contract".steps[0].uses == strenv(EXPECTED_CHECKOUT_USE) and
    (.jobs."preflight-caller-contract".steps[0].with | keys | sort | join(",")) == "persist-credentials,ref" and
    (.jobs."preflight-caller-contract".steps[0].with."persist-credentials" | tostring) == "false" and
    .jobs."preflight-caller-contract".steps[0].with.ref == strenv(EXPECTED_WORKFLOW_SHA_EXPRESSION)' \
    ".jobs.${CONTRACT_JOB}.steps.checkout"
yaml_true '(.jobs."preflight-caller-contract".steps[1] | keys | sort | join(",")) == "uses,with" and
    .jobs."preflight-caller-contract".steps[1].uses == strenv(EXPECTED_CONTRACT_USE) and
    (.jobs."preflight-caller-contract".steps[1].with | keys | join(",")) == "vault-addr" and
    .jobs."preflight-caller-contract".steps[1].with."vault-addr" == strenv(EXPECTED_VAULT_EXPRESSION)' \
    ".jobs.${CONTRACT_JOB}.steps.contract"

yaml_true '([.jobs.deploy.needs] | flatten | map(select(. == "preflight-caller-contract")) | length) > 0' \
    ".jobs.${DEPLOY_JOB}.needs"
yaml_true '.jobs.deploy | has("continue-on-error") | not' ".jobs.${DEPLOY_JOB}.continue-on-error"
yaml_true '(.jobs.deploy.if | tostring) == strenv(EXPECTED_DEPLOY_IF)' ".jobs.${DEPLOY_JOB}.if"
yaml_true '.jobs.deploy.env.VAULT_ADDR == strenv(EXPECTED_VAULT_EXPRESSION)' ".jobs.${DEPLOY_JOB}.env.VAULT_ADDR"

yaml_true '[.jobs[]?.steps[]? | select((.uses // "") |
    test("^Arcanada-one/datarim/\\.github/actions/preflight-check@"))] | length == 1' \
    ".jobs.${DEPLOY_JOB}.steps.uses"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))] | length == 1' \
    ".jobs.${DEPLOY_JOB}.steps.uses"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0] |
    ([keys[] | select(. != "id" and . != "name" and . != "uses" and . != "with")] | length) == 0' \
    ".jobs.${DEPLOY_JOB}.steps.preflight-shape"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].id == "preflight"' \
    ".jobs.${DEPLOY_JOB}.steps.id"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].with."service-name" == strenv(EXPECTED_SERVICE_NAME)' \
    ".jobs.${DEPLOY_JOB}.steps.with.service-name"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].with."ops-bot-agent" == strenv(EXPECTED_OPS_BOT_AGENT)' \
    ".jobs.${DEPLOY_JOB}.steps.with.ops-bot-agent"
yaml_true '([.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].with."ops-bot-emit" | tostring) == "true"' \
    ".jobs.${DEPLOY_JOB}.steps.with.ops-bot-emit"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].with."ops-bot-key" == strenv(EXPECTED_SECRET_EXPRESSION)' \
    ".jobs.${DEPLOY_JOB}.steps.with.ops-bot-key"
yaml_true '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].with."ops-bot-url" == strenv(EXPECTED_OPS_BOT_URL)' \
    ".jobs.${DEPLOY_JOB}.steps.with.ops-bot-url"

yaml_read '[.jobs.deploy.steps | to_entries[] | select(.value.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].key' \
    ".jobs.${DEPLOY_JOB}.steps.uses"
preflight_step_index="$YAML_VALUE"
[ "$preflight_step_index" = 0 ] || fail ".jobs.${DEPLOY_JOB}.steps.order: preflight must be first"
yaml_true '[.jobs.deploy.steps[]? | select(has("continue-on-error"))] | length == 0' \
    ".jobs.${DEPLOY_JOB}.steps.continue-on-error"
yaml_true '[.jobs.deploy.steps | to_entries[] | select(.key > 0) |
    select(((.value.if // "") | tostring) |
      test("(?i)(always|failure|cancelled|success)[[:space:]]*\\("))] | length == 0' \
    ".jobs.${DEPLOY_JOB}.steps.if"

yaml_read '[.jobs.deploy.steps[]? | select(.uses == strenv(EXPECTED_PREFLIGHT_USE))][0].with."extra-checks" // ""' \
    ".jobs.${DEPLOY_JOB}.steps.with.extra-checks"
extra_checks="$YAML_VALUE"
vault_enabled=false
while IFS= read -r check_name; do
    if [[ "$check_name" =~ ^[[:space:]]*vault[[:space:]]*$ ]]; then
        vault_enabled=true
        break
    fi
done <<< "$extra_checks"
[ "$vault_enabled" = true ] || fail ".jobs.${DEPLOY_JOB}.steps.with.extra-checks: exact vault token required"

printf '%s\n' "preflight caller contract: PASS"
