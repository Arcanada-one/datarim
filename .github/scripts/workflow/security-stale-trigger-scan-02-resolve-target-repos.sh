#!/usr/bin/env bash
set -euo pipefail
if [ -n "${TARGET_REPOS_INPUT:-}" ]; then
  echo "list=$TARGET_REPOS_INPUT" >> "$GITHUB_OUTPUT"
else
  echo "list=${TARGET_REPOS_ORG:-}" >> "$GITHUB_OUTPUT"
fi
