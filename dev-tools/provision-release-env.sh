#!/usr/bin/env bash
# provision-release-env.sh — provision a GitHub deployment environment for a
# release pipeline dispatched from protected main for one authenticated tag.
#
# The environment must admit the trusted workflow ref (`main`). A `v*` tag
# policy is retained for compatible tag-triggered consumers. This script sets
# `custom_branch_policies=true`, preserves existing protection rules whenever
# the environment must be updated, and creates exact branch/tag policy entries.
# The manual-approval environment additionally keeps its `required_reviewers`
# rule (pass --reviewers to set or replace it).
#
# Safety contract: DRY-RUN BY DEFAULT. Without --apply the script only prints
# the gh-api calls it would make; no PUT/POST fires. Re-running with --apply is
# idempotent: the environment PUT is idempotent on GitHub's side, and each deployment
# policy is only POSTed when an identical one is not already present.
#
# API:
#   provision-release-env.sh --repo <owner/name> --env <name>
#                            [--tag-policy 'v*'] [--branch-policy main]
#                            [--reviewers <type:id>...] [--apply]
# Exit: 0 provisioned (or dry-run clean); 2 usage error; 3 gh/runtime error.
#
# Security: S1 — strict mode; --repo and --env regex-validated; the GitHub API
# command is injected via GH_API_CMD (default `gh api`) for testability; no
# eval, no secrets touched (gh handles auth from the operator's own login).

set -euo pipefail

GH_API_CMD="${GH_API_CMD:-gh api}"

usage() {
    cat >&2 <<'EOF'
Usage: provision-release-env.sh --repo <owner/name> --env <name>
                                [--tag-policy 'v*'] [--branch-policy main]
                                [--reviewers <type:id>]... [--apply]

  --repo <owner/name>   Target repository (e.g. Arcanada-one/coworker). Required.
  --env  <name>         Deployment environment name (e.g. release-auto). Required.
  --tag-policy <glob>   Tag pattern to allow (default: v*).
  --branch-policy <glob> Branch pattern to allow (default: main).
  --reviewers <type:id> Add a required_reviewers entry. <type> is User or Team;
                        <id> is the NUMERIC GitHub id (slugs are not accepted by
                        the API — resolve with `gh api users/<login> --jq .id`
                        or `gh api orgs/<org>/teams/<slug> --jq .id`). Repeatable.
                        Omit for an auto (no-approval) environment.
  --apply               Perform the mutating gh-api calls. Default is dry-run.

Default is DRY-RUN: it prints the planned calls and changes nothing.
EOF
    exit 2
}

REPO=""
ENV_NAME=""
TAG_POLICY="v*"
BRANCH_POLICY="main"
APPLY=0
REVIEWERS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO="${2:-}"; shift 2 ;;
        --env)        ENV_NAME="${2:-}"; shift 2 ;;
        --tag-policy)    TAG_POLICY="${2:-}"; shift 2 ;;
        --branch-policy) BRANCH_POLICY="${2:-}"; shift 2 ;;
        --reviewers)
            [[ "${2:-}" =~ ^(User|Team):[0-9]+$ ]] \
                || { echo "ERROR: --reviewers must be <User|Team>:<numeric-id>: '${2:-}'" >&2; usage; }
            REVIEWERS+=("$2"); shift 2 ;;
        --apply)      APPLY=1; shift ;;
        -h|--help)    usage ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage ;;
    esac
done

[ -n "$REPO" ] || { echo "ERROR: --repo is required" >&2; usage; }
[ -n "$ENV_NAME" ] || { echo "ERROR: --env is required" >&2; usage; }

# S1 input validation — owner/name and a single safe path component.
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || { echo "ERROR: --repo must be <owner/name>: '$REPO'" >&2; usage; }
[[ "$ENV_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
    || { echo "ERROR: --env must be a single safe name: '$ENV_NAME'" >&2; usage; }
[[ "$TAG_POLICY" =~ ^[A-Za-z0-9._*?/-]+$ ]] \
    || { echo "ERROR: unsafe --tag-policy: '$TAG_POLICY'" >&2; usage; }
[[ "$BRANCH_POLICY" =~ ^[A-Za-z0-9._*?/-]+$ ]] \
    || { echo "ERROR: unsafe --branch-policy: '$BRANCH_POLICY'" >&2; usage; }
command -v jq >/dev/null 2>&1 \
    || { echo "ERROR: jq is required" >&2; exit 3; }

# gh-api invocation: dry-run prints, --apply executes. Word-split GH_API_CMD so
# the default "gh api" and a test stub path both work. An optional JSON body is
# piped to the command via stdin (GitHub requires nested objects as JSON, not
# bracket-notation -f fields).
gh_call() {
    local body=""
    if [ "${1:-}" = "--body" ]; then
        body="$2"; shift 2
    fi
    if [ "$APPLY" -eq 1 ]; then
        if [ -n "$body" ]; then
            # shellcheck disable=SC2086  # GH_API_CMD is a trusted, space-split command prefix
            printf '%s' "$body" | $GH_API_CMD "$@" --input -
        else
            # shellcheck disable=SC2086  # GH_API_CMD is a trusted, space-split command prefix
            $GH_API_CMD "$@"
        fi
    else
        if [ -n "$body" ]; then
            echo "DRY-RUN: ${GH_API_CMD} $* --input - <<< ${body}"
        else
            echo "DRY-RUN: ${GH_API_CMD} $*"
        fi
    fi
}

ENV_PATH="repos/${REPO}/environments/${ENV_NAME}"
POLICY_PATH="${ENV_PATH}/deployment-branch-policies"

echo "==> Provisioning ${ENV_NAME} on ${REPO} (tag='${TAG_POLICY}', branch='${BRANCH_POLICY}', apply=${APPLY})"

# Read both resources before mutation. The environment response is used to
# preserve wait timer, self-review, and existing required reviewers if a PUT is
# necessary. Policy entries are checked as exact name/type tuples.
existing_env="$($GH_API_CMD "$ENV_PATH" 2>/dev/null || true)"
existing_policies="$($GH_API_CMD "$POLICY_PATH" 2>/dev/null || true)"

custom_ready=0
if jq -e '.deployment_branch_policy.custom_branch_policies == true and .deployment_branch_policy.protected_branches == false' \
    <<< "$existing_env" >/dev/null 2>&1; then
    custom_ready=1
fi

# Explicit reviewers intentionally update the protection rule. Otherwise an
# already custom-enabled environment needs no PUT, which is the safest way to
# preserve every server-side setting.
if [[ "$custom_ready" -eq 1 && "${#REVIEWERS[@]}" -eq 0 ]]; then
    echo "==> environment already uses custom branch policies — preserving protection rules"
else
    reviewer_json=""
    if [[ "${#REVIEWERS[@]}" -gt 0 ]]; then
        for entry in "${REVIEWERS[@]}"; do
            rtype="${entry%%:*}"
            rid="${entry##*:}"
            reviewer_json="${reviewer_json:+${reviewer_json},}{\"type\":\"${rtype}\",\"id\":${rid}}"
        done
        reviewer_json="[${reviewer_json}]"
    else
        reviewer_json="$(jq -c '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]? | {type: .type, id: .reviewer.id}]' <<< "$existing_env" 2>/dev/null || printf '[]')"
    fi
    wait_timer="$(jq -r '[.protection_rules[]? | select(.type == "wait_timer") | .wait_timer][0] // 0' <<< "$existing_env" 2>/dev/null || printf '0')"
    prevent_self_review="$(jq -r '.prevent_self_review // false' <<< "$existing_env" 2>/dev/null || printf 'false')"
    [[ "$wait_timer" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid live wait_timer" >&2; exit 3; }
    [[ "$prevent_self_review" == true || "$prevent_self_review" == false ]] \
        || { echo "ERROR: invalid live prevent_self_review" >&2; exit 3; }

    put_body="{\"deployment_branch_policy\":{\"custom_branch_policies\":true,\"protected_branches\":false},\"wait_timer\":${wait_timer},\"prevent_self_review\":${prevent_self_review}"
    if [[ "$reviewer_json" != "[]" ]]; then
        put_body+=",\"required_reviewers\":${reviewer_json}"
    fi
    put_body+="}"
    gh_call --body "$put_body" -X PUT "$ENV_PATH"
fi

ensure_policy() {
    local policy_name="$1"
    local policy_type="$2"
    if jq -e --arg name "$policy_name" --arg type "$policy_type" \
        '.branch_policies[]? | select(.name == $name and .type == $type)' \
        <<< "$existing_policies" >/dev/null 2>&1; then
        echo "==> ${policy_type} policy '${policy_name}' already present — skipping POST"
    else
        gh_call --body "{\"name\":\"${policy_name}\",\"type\":\"${policy_type}\"}" -X POST "$POLICY_PATH"
    fi
}

ensure_policy "$TAG_POLICY" tag
ensure_policy "$BRANCH_POLICY" branch

echo "==> Done (${ENV_NAME})."
