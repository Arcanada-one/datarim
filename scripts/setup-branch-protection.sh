#!/usr/bin/env bash
# Apply branch + tag protection rules to the public framework repo.
#
# Idempotent: safe to re-run. Uses the GitHub REST API via `gh api`.
#
# Required:
#   - gh CLI authenticated as an org owner with admin:repo scope.
#   - GH_REPO (default: Arcanada-one/datarim).
#   - REQUIRED_CHECKS (comma-separated; defaults to current required
#     CI jobs).
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
REQUIRED_CHECKS="${REQUIRED_CHECKS:-security,sanity-dual-copy,bats,dev-tools-lint,network-exposure-lint,public-surface-lint}"

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
echo "[1/3] Applying branch protection to ${BRANCH}..."

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
    "required_pull_request_reviews": {
        "dismiss_stale_reviews": True,
        "require_code_owner_reviews": True,
        "required_approving_review_count": 1,
        "require_last_push_approval": True,
    },
    "restrictions": None,
    "required_linear_history": True,
    "allow_force_pushes": False,
    "allow_deletions": False,
    "required_conversation_resolution": True,
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

# 2. Required signature on protected branch (optional hardening).
echo
echo "[2/3] Requiring signed commits on ${BRANCH}..."
gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "repos/${GH_REPO}/branches/${BRANCH}/protection/required_signatures" \
    >/dev/null || echo "  (signed-commits requirement already set or not supported)"

# 3. Tag protection rule.
echo
echo "[3/3] Applying tag protection pattern ${TAG_PATTERN}..."
existing="$(gh api "repos/${GH_REPO}/tags/protection" --jq '.[] | select(.pattern == "'"${TAG_PATTERN}"'") | .id' 2>/dev/null || true)"
if [[ -n "${existing}" ]]; then
    echo "  pattern already protected (id=${existing}); skipping create."
else
    gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        "repos/${GH_REPO}/tags/protection" \
        -f pattern="${TAG_PATTERN}"
fi

echo
echo "Done. Current protection state for ${BRANCH}:"
gh api "repos/${GH_REPO}/branches/${BRANCH}/protection" --jq '{
    enforce_admins: .enforce_admins.enabled,
    require_code_owner_reviews: .required_pull_request_reviews.require_code_owner_reviews,
    required_approving_review_count: .required_pull_request_reviews.required_approving_review_count,
    required_status_checks: .required_status_checks.contexts,
    allow_force_pushes: .allow_force_pushes.enabled,
    allow_deletions: .allow_deletions.enabled,
    required_linear_history: .required_linear_history.enabled
}'

echo
echo "Tag protection patterns:"
gh api "repos/${GH_REPO}/tags/protection" --jq '.[].pattern'
