#!/usr/bin/env bash
set -euo pipefail
: "${RELEASE_TAG_OBJECT:?RELEASE_TAG_OBJECT required}"
"$RUNNER_TEMP/verify-release-tag.sh" recheck --repo . --tag "$TAG" \
  --release-sha "$RELEASE_SHA" --tag-object "$RELEASE_TAG_OBJECT"
