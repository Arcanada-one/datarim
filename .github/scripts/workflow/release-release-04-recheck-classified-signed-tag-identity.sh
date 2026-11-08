#!/usr/bin/env bash
set -euo pipefail
"$RUNNER_TEMP/verify-release-tag.sh" recheck --repo . --tag "$RELEASE_TAG" \
  --release-sha "$RELEASE_SHA" --tag-object "$RELEASE_TAG_OBJECT"
