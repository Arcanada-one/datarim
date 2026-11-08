#!/usr/bin/env bash
set -euo pipefail
[[ "$WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]]
git cat-file -e "${WORKFLOW_SHA}^{commit}"
git show "${WORKFLOW_SHA}:dev-tools/verify-release-tag.sh" > "$RUNNER_TEMP/verify-release-tag.sh"
chmod 0755 "$RUNNER_TEMP/verify-release-tag.sh"
