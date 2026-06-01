#!/usr/bin/env bash
# provision-release-env.sh — provision a GitHub deployment environment for a
# tag-driven release pipeline, with a tag-aware deployment-branch-policy.
#
# A tag-driven publish (`on: push: tags: ['v*']`) routes through a GitHub
# deployment environment. GitHub's DEFAULT environment policy is
# `deployment_branch_policy.protected_branches=true`, which matches only
# protected BRANCHES and silently EXCLUDES tags — so the very first tag-driven
# publish is rejected with «Tag vX.Y.Z is not allowed to deploy due to
# environment protection rules». This script sets the correct policy up front:
# `custom_branch_policies=true` plus a `{name:'v*', type:'tag'}`
# deployment-branch-policy. The manual-approval environment additionally keeps
# its `required_reviewers` rule (pass --reviewers).
#
# Safety contract: DRY-RUN BY DEFAULT. Without --apply the script only prints
# the gh-api calls it would make; no PUT/POST fires. Re-running with --apply is
# idempotent: the environment PUT is idempotent on GitHub's side, and the tag
# policy is only POSTed when an identical one is not already present.
#
# API:
#   provision-release-env.sh --repo <owner/name> --env <name>
#                            [--tag-policy 'v*'] [--reviewers <slug>...] [--apply]
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
                                [--tag-policy 'v*'] [--reviewers <slug>]... [--apply]

  --repo <owner/name>   Target repository (e.g. Arcanada-one/coworker). Required.
  --env  <name>         Deployment environment name (e.g. release-auto). Required.
  --tag-policy <glob>   Tag pattern to allow (default: v*).
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
APPLY=0
REVIEWERS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO="${2:-}"; shift 2 ;;
        --env)        ENV_NAME="${2:-}"; shift 2 ;;
        --tag-policy) TAG_POLICY="${2:-}"; shift 2 ;;
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

echo "==> Provisioning ${ENV_NAME} on ${REPO} (tag-policy='${TAG_POLICY}', apply=${APPLY})"

# 1. Read existing tag policies first (idempotency check + ordering contract).
#    A read is non-mutating, so it runs in both modes.
existing="$($GH_API_CMD "$POLICY_PATH" 2>/dev/null || true)"

# 2. PUT the environment with a custom (tag-capable) branch policy. GitHub wants
#    the nested deployment_branch_policy as a JSON object; required_reviewers (on
#    the manual env) is a JSON array of {type, id-or-slug} entries. Build the
#    body as JSON and pipe it via --input -.
reviewer_json=""
for entry in "${REVIEWERS[@]:-}"; do
    [ -n "$entry" ] || continue
    # entry is validated <User|Team>:<numeric-id>. GitHub's required_reviewers
    # API identifies reviewers by numeric id, not slug.
    rtype="${entry%%:*}"
    rid="${entry##*:}"
    reviewer_json="${reviewer_json:+${reviewer_json},}{\"type\":\"${rtype}\",\"id\":${rid}}"
done
if [ -n "$reviewer_json" ]; then
    put_body="{\"deployment_branch_policy\":{\"custom_branch_policies\":true,\"protected_branches\":false},\"required_reviewers\":[${reviewer_json}]}"
else
    put_body="{\"deployment_branch_policy\":{\"custom_branch_policies\":true,\"protected_branches\":false}}"
fi
gh_call --body "$put_body" -X PUT "$ENV_PATH"

# 3. POST the tag deployment-branch-policy, but only if an identical one is not
#    already present (idempotency — avoid duplicate policies on re-run).
if printf '%s' "$existing" | grep -qF "\"name\":\"${TAG_POLICY}\"" 2>/dev/null; then
    echo "==> tag policy '${TAG_POLICY}' already present — skipping POST"
else
    gh_call --body "{\"name\":\"${TAG_POLICY}\",\"type\":\"tag\"}" -X POST "$POLICY_PATH"
fi

echo "==> Done (${ENV_NAME})."
