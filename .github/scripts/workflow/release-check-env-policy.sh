#!/usr/bin/env bash
set -euo pipefail
bash dev-tools/check-release-env-policy.sh --check --live \
  --repo "$GITHUB_REPOSITORY"
