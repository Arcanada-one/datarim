#!/usr/bin/env bash
# Apply branch + tag protection rules to the public framework repo.
#
# Idempotent: safe to re-run. Uses the GitHub REST API via `gh api`.
#
# Required:
#   - gh CLI authenticated as an org owner with admin:repo scope.
#   - GH_REPO (default: Arcanada-one/datarim).
#   - REQUIRED_CHECKS (comma-separated; defaults to currently-green
#     job names — see "Required status checks" notes below).
#
# Policy (autonomous-agent mode):
#   - No human PR-review wall (`required_pull_request_reviews: null`).
#     The agent identity is the maintainer; review gating would
#     permanently block self-merging and Dependabot updates.
#   - Status-check gating is the only hard floor: PRs (and pushes to
#     main) must pass the curated set below.
#   - Force-push, deletions, non-linear merges blocked.
#   - enforce_admins=true — the agent does not need to bypass the
#     status-check floor; if a check fails, the right action is to fix
#     the underlying issue, not bypass the gate.
#   - Tag protection via Repository Ruleset (legacy
#     /tags/protection endpoint is deprecated).
#
# Required status checks: start with the currently-green job names
# only. Expanding the set requires the baseline-red jobs (actionlint,
# bandit-extracted, doc-refs, markdown-policy, regression-bats,
# semgrep, shellcheck-extracted, task-id-gate, zizmor) to be cleaned
# first — otherwise the gate permanently blocks merges.
#
# Usage:
#   ./scripts/setup-branch-protection.sh
#   GH_REPO=Arcanada-one/datarim-fork ./scripts/setup-branch-protection.sh
#
# Output: prints the resolved protection settings as JSON.

set -euo pipefail

GH_REPO="${GH_REPO:-Arcanada-one/datarim}"
BRANCH="${BRANCH:-main}"
TAG_PATTERN="${TAG_PATTERN:-v*}"
TAG_RULESET_NAME="${TAG_RULESET_NAME:-Protect release tags}"
REQUIRED_CHECKS="${REQUIRED_CHECKS:-shellcheck,gitleaks,bandit,osv-scanner,trufflehog,diff-mirrored-scopes}"

if ! command -v gh >/dev/null 2>&1; then
    echo "::error::gh CLI not found in PATH" >&2
    exit 2
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "::error::gh not authenticated; run 'gh auth login' first" >&2
    exit 2
fi

echo "Target: ${GH_REPO} branch=${BRANCH} tag-pattern=${TAG_PATTERN}"
echo "Required status checks: ${REQUIRED_CHECKS}"

# Build the required-status-checks contexts array as JSON.
checks_json="$(printf '%s\n' "${REQUIRED_CHECKS}" \
    | tr ',' '\n' \
    | python3 -c 'import json,sys; print(json.dumps([s.strip() for s in sys.stdin if s.strip()]))')"

# 1. Branch protection on main.
echo
echo "[1/2] Applying branch protection to ${BRANCH}..."

payload="$(python3 - "${checks_json}" <<'PY'
import json
import sys

contexts = json.loads(sys.argv[1])
payload = {
    "required_status_checks": {
        "strict": True,
        "contexts": contexts,
    },
    "enforce_admins": True,
    "required_pull_request_reviews": None,
    "restrictions": None,
    "required_linear_history": True,
    "allow_force_pushes": False,
    "allow_deletions": False,
    "required_conversation_resolution": False,
    "block_creations": False,
    "lock_branch": False,
    "allow_fork_syncing": True,
}
print(json.dumps(payload))
PY
)"

echo "${payload}" \
    | gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        "repos/${GH_REPO}/branches/${BRANCH}/protection" \
        --input -

# 2. Tag protection via Repository Ruleset (legacy /tags/protection deprecated).
echo
echo "[2/2] Applying tag protection ruleset \"${TAG_RULESET_NAME}\" (pattern refs/tags/${TAG_PATTERN})..."
existing_id="$(gh api "repos/${GH_REPO}/rulesets" --jq '.[] | select(.name == "'"${TAG_RULESET_NAME}"'" and .target == "tag") | .id' 2>/dev/null | head -1)"
ruleset_payload="$(python3 - "${TAG_PATTERN}" <<'PY'
import json
import sys
pattern = sys.argv[1]
payload = {
    "name": "PLACEHOLDER",
    "target": "tag",
    "enforcement": "active",
    "conditions": {
        "ref_name": {
            "include": [f"refs/tags/{pattern}"],
            "exclude": [],
        },
    },
    "rules": [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {"type": "update"},
    ],
    "bypass_actors": [],
}
print(json.dumps(payload))
PY
)"
# Inject the runtime-resolved name (avoids shell quoting in heredoc).
ruleset_payload="${ruleset_payload/PLACEHOLDER/${TAG_RULESET_NAME}}"

if [[ -n "${existing_id}" ]]; then
    echo "  ruleset already exists (id=${existing_id}); applying PUT to refresh."
    echo "${ruleset_payload}" \
        | gh api \
            --method PUT \
            -H "Accept: application/vnd.github+json" \
            "repos/${GH_REPO}/rulesets/${existing_id}" \
            --input - >/dev/null
else
    echo "${ruleset_payload}" \
        | gh api \
            --method POST \
            -H "Accept: application/vnd.github+json" \
            "repos/${GH_REPO}/rulesets" \
            --input - >/dev/null
fi

echo
echo "Done. Current protection state for ${BRANCH}:"
gh api "repos/${GH_REPO}/branches/${BRANCH}/protection" --jq '{
    enforce_admins: .enforce_admins.enabled,
    required_status_checks: .required_status_checks.contexts,
    required_pull_request_reviews: .required_pull_request_reviews,
    allow_force_pushes: .allow_force_pushes.enabled,
    allow_deletions: .allow_deletions.enabled,
    required_linear_history: .required_linear_history.enabled
}'

echo
echo "Tag rulesets:"
gh api "repos/${GH_REPO}/rulesets" --jq '.[] | select(.target == "tag") | {id, name, enforcement, pattern: .conditions.ref_name.include}' 2>/dev/null || true
