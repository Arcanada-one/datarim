#!/usr/bin/env bash
# check-agent-ci-wip.sh — ARC-CI-11 advisory WIP gate for agent PR pushes.
#
# Counts open pull requests in a repository that still have pending GitHub
# Actions checks. Agents should run this before pushing a new head so faster
# pushes do not only grow the CI queue. Exit codes:
#   0  under or equal to limit
#   2  over limit (advisory refusal; does not mutate git)
#   1  usage / tool failure
#
# Default limit is 2 concurrent open PRs with pending checks. Override with
# AGENT_CI_WIP_LIMIT. This script never purchases runners and never changes
# branch protection.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-agent-ci-wip.sh [--repo OWNER/NAME] [--limit N] [--author LOGIN]

Environment:
  AGENT_CI_WIP_LIMIT   default limit when --limit is omitted (default: 2)
EOF
}

REPO="Arcanada-one/datarim"
LIMIT="${AGENT_CI_WIP_LIMIT:-2}"
AUTHOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?}"
      shift 2
      ;;
    --author)
      AUTHOR="${2:?}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]]; then
  echo "limit must be a positive integer, got: $LIMIT" >&2
  exit 1
fi

if [[ -z "$AUTHOR" ]]; then
  AUTHOR="$(gh api user --jq .login)"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

gh pr list -R "$REPO" --state open --author "$AUTHOR" --limit 50 \
  --json number,url,statusCheckRollup,headRefName >"$tmp"

LIMIT="$LIMIT" REPO="$REPO" AUTHOR="$AUTHOR" python3 - "$tmp" <<'PY'
import json
import os
import sys

path = sys.argv[1]
limit = int(os.environ["LIMIT"])
repo = os.environ["REPO"]
author = os.environ["AUTHOR"]
prs = json.loads(open(path, encoding="utf-8").read())

pending = []
for pr in prs:
    rollup = pr.get("statusCheckRollup") or []
    has_pending = False
    for check in rollup:
        status = (check.get("status") or "").upper()
        conclusion = (check.get("conclusion") or "").upper()
        state = (check.get("state") or "").upper()
        if status in {"QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"} and not conclusion:
            has_pending = True
            break
        if state in {"PENDING", "EXPECTED"}:
            has_pending = True
            break
    if has_pending:
        pending.append(pr)

count = len(pending)
print(f"repo={repo} author={author} open_with_pending_checks={count} limit={limit}")
for pr in pending:
    print(f"  #{pr.get('number')} {pr.get('headRefName')} {pr.get('url')}")

if count > limit:
    print(
        f"ARC-CI-11: over agent CI WIP limit ({count}>{limit}). "
        "Finish or close pending PRs before pushing another head.",
        file=sys.stderr,
    )
    sys.exit(2)
sys.exit(0)
PY
