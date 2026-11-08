#!/usr/bin/env bash
set -euo pipefail
tag="$RELEASE_TAG"
identity="$(dev-tools/verify-release-tag.sh classify --repo . --tag "$tag" \
  --workflow-ref "$EXPECTED_REF" --allowed-signers .github/ssh-signing-allowed-signers)"
release_sha="$(printf '%s\n' "$identity" | sed -n 's/^release_sha=//p')"
release_tag_object="$(printf '%s\n' "$identity" | sed -n 's/^release_tag_object=//p')"
workflow_sha="$(printf '%s\n' "$identity" | sed -n 's/^workflow_sha=//p')"
stamped="$(printf '%s\n' "$identity" | sed -n 's/^stamped_bump_level=//p')"
case "$stamped" in patch|minor|major) ;; *) echo "::error::missing/invalid bump_level stamp" >&2; exit 1 ;; esac
previous_tag=""
classification_sha="$release_sha"
root_release=false
if git rev-parse --verify "${release_sha}^" >/dev/null 2>&1; then
  # Ordinary releases retain the existing ancestor-tag path.
  while IFS= read -r candidate; do
    if [[ "$candidate" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(rc|alpha|beta|test)[0-9]+)?$ ]]; then
      previous_tag="$candidate"
      break
    fi
  done < <(git tag --merged "${release_sha}^" --list 'v*' --sort=-v:refname)
else
  # An authorized history cutover must preserve the tree of a source
  # prepared through the ordinary PR path. Its signed tag pins that
  # source; classify the genuine commit range, not a rewritten message.
  root_release=true
  source_sha="$(printf '%s\n' "$identity" | sed -n 's/^history_bootstrap_source=//p')"
  tree_sha="$(printf '%s\n' "$identity" | sed -n 's/^history_bootstrap_tree=//p')"
  [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]]
  [[ "$tree_sha" =~ ^[0-9a-f]{40}$ ]]
  git fetch --no-tags origin "$source_sha"
  bootstrap="$(python3 dev-tools/check-history-bootstrap.py --repo . --mode release \
    --source-sha "$source_sha" --release-sha "$release_sha" --tree-sha "$tree_sha")"
  previous_tag="$(printf '%s\n' "$bootstrap" | sed -n 's/^baseline_tag=//p')"
  classification_sha="$source_sha"
  test "$tag" = "v$(printf '%s\n' "$bootstrap" | sed -n 's/^version=//p')"
fi
test -n "$previous_tag"
ci_output="$(dev-tools/release-classify.sh --repo . --from "$previous_tag" --to "$classification_sha" --api-diff auto)"
ci="$(printf '%s\n' "$ci_output" | sed -n 's/^bump_level=//p' | head -1)"
api_diff="$(printf '%s\n' "$ci_output" | sed -n 's/^api_diff=//p' | head -1)"
rationale="$(printf '%s\n' "$ci_output" | sed -n 's/^rationale=//p' | head -1)"
case "$ci" in patch|minor|major) ;; *) echo "::error::invalid classifier bump" >&2; exit 1 ;; esac
if [ "$root_release" = true ]; then
  # The explicit bootstrap contract permits only its next patch.
  if [ "$ci" != patch ] || [ "$stamped" != patch ]; then
    echo "::error::bootstrap source range and signed tag must both classify as patch" >&2
    exit 1
  fi
fi
case "$api_diff" in clean|unavailable) ;; *) echo "::error::invalid API-diff result" >&2; exit 1 ;; esac
test -n "$rationale"
rank() { case "$1" in patch) echo 1;; minor) echo 2;; major) echo 3;; *) echo 0;; esac; }
if [ "$(rank "$ci")" -ge "$(rank "$stamped")" ]; then final="$ci"; else final="$stamped"; fi
{
  echo "bump_level=${final}"
  echo "release_sha=${release_sha}"
  echo "release_tag_object=${release_tag_object}"
  echo "workflow_sha=${workflow_sha}"
  echo "release_tag=${tag}"
  echo "root_release=${root_release}"
} >> "$GITHUB_OUTPUT"
if [ "$ci" = "major" ] && [ "$stamped" != "major" ]; then
  echo "::error::CI classified MAJOR but the tag stamped '${stamped}' — aborting" >&2
  exit 1
fi
