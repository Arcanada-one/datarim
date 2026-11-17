#!/usr/bin/env bash
set -euo pipefail
# Container jobs mount the workspace with a host uid; mark it safe for git.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-$(pwd)}"
test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD_SHA"
