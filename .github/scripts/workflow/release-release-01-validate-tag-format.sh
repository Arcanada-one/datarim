#!/usr/bin/env bash
set -euo pipefail
tag="$RELEASE_TAG"
target_sha="$RELEASE_SHA"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(rc|alpha|beta|test)[0-9]+)?$ ]]; then
  echo "::error::tag '$tag' does not match release format ^v\\d+\\.\\d+\\.\\d+(-(rc|alpha|beta|test)\\d+)?$"
  exit 1
fi
[[ "$target_sha" =~ ^[0-9a-f]{40}$ ]]
{
  echo "TAG=$tag"
  echo "VERSION=${tag#v}"
  echo "RELEASE_SHA=$target_sha"
} >> "$GITHUB_ENV"
if [[ "$tag" =~ -(rc|alpha|beta|test)[0-9]+$ ]]; then
  echo "IS_PRERELEASE=true" >> "$GITHUB_ENV"
else
  echo "IS_PRERELEASE=false" >> "$GITHUB_ENV"
fi
