#!/usr/bin/env bash
# Verify a signed release tag against protected main, then pin its exact object.
set -euo pipefail
IFS=$'\n\t'

die() { echo "release tag verification failed: $1" >&2; exit 1; }
usage() {
  echo 'usage: verify-release-tag.sh classify --repo DIR --tag TAG --workflow-ref REF --allowed-signers FILE | recheck --repo DIR --tag TAG --release-sha SHA --tag-object SHA' >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
mode="$1"; shift
repo=""; tag=""; workflow_ref=""; allowed_signers=""; release_sha=""; tag_object=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || usage; repo="$2"; shift 2 ;;
    --tag) [[ $# -ge 2 ]] || usage; tag="$2"; shift 2 ;;
    --workflow-ref) [[ $# -ge 2 ]] || usage; workflow_ref="$2"; shift 2 ;;
    --allowed-signers) [[ $# -ge 2 ]] || usage; allowed_signers="$2"; shift 2 ;;
    --release-sha) [[ $# -ge 2 ]] || usage; release_sha="$2"; shift 2 ;;
    --tag-object) [[ $# -ge 2 ]] || usage; tag_object="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$repo" ]] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die 'repository is missing'
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(rc|alpha|beta|test)[0-9]+)?$ ]] || die 'tag format is invalid'
git -C "$repo" check-ref-format "refs/tags/$tag" >/dev/null || die 'tag ref is invalid'
case "$mode" in
  classify)
    [[ "$workflow_ref" == refs/heads/main ]] || die 'workflow was not dispatched from protected main'
    [[ -n "$allowed_signers" && -f "$repo/$allowed_signers" ]] || die 'allowed signers file is missing'
    ;;
  recheck)
    [[ "$release_sha" =~ ^[0-9a-f]{40}$ && "$tag_object" =~ ^[0-9a-f]{40}$ ]] || die 'pinned release identity is invalid'
    ;;
  *) usage ;;
esac
ref="refs/release-verification/${tag}/$(date +%s)-$$"
cleanup() { git -C "$repo" update-ref -d "$ref" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# A private ref avoids overwriting any checked-out or existing tag ref. The
# release job repeats this fetch and compares both immutable object identities.
git -C "$repo" fetch --quiet --no-tags origin "refs/tags/${tag}:${ref}" || die 'tag is absent or could not be fetched'
[[ "$(git -C "$repo" cat-file -t "$ref")" == tag ]] || die 'release tag is not annotated'
fetched_object="$(git -C "$repo" rev-parse "$ref")"
fetched_sha="$(git -C "$repo" rev-parse "${ref}^{commit}")"
[[ "$fetched_sha" =~ ^[0-9a-f]{40}$ ]] || die 'tag does not resolve to a commit'

case "$mode" in
  classify)
    git -C "$repo" -c "gpg.ssh.allowedSignersFile=$allowed_signers" verify-tag "$ref" >/dev/null || die 'tag signature is not trusted'
    main_sha="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" merge-base --is-ancestor "$fetched_sha" "$main_sha" || die 'tag target is not an ancestor of protected main'
    msg="$(git -C "$repo" for-each-ref "$ref" --format='%(contents)')"
    stamped="$(printf '%s\n' "$msg" | sed -n 's/^bump_level=//p' | head -1)"
    source_sha="$(printf '%s\n' "$msg" | sed -n 's/^history_bootstrap_source=//p' | head -1)"
    tree_sha="$(printf '%s\n' "$msg" | sed -n 's/^history_bootstrap_tree=//p' | head -1)"
    [[ -z "$source_sha" || "$source_sha" =~ ^[0-9a-f]{40}$ ]] || die 'bootstrap source pin is invalid'
    [[ -z "$tree_sha" || "$tree_sha" =~ ^[0-9a-f]{40}$ ]] || die 'bootstrap tree pin is invalid'
    printf 'release_sha=%s\nrelease_tag_object=%s\nworkflow_sha=%s\nstamped_bump_level=%s\nhistory_bootstrap_source=%s\nhistory_bootstrap_tree=%s\n' \
      "$fetched_sha" "$fetched_object" "$main_sha" "$stamped" "$source_sha" "$tree_sha"
    ;;
  recheck)
    [[ "$fetched_object" == "$tag_object" ]] || die 'tag object changed after classification'
    [[ "$fetched_sha" == "$release_sha" ]] || die 'tag target changed after classification'
    ;;
  *) usage ;;
esac
