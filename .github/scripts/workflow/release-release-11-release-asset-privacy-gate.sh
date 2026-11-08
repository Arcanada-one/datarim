#!/usr/bin/env bash
set -euo pipefail
test -n "${PERSONAL_ID_OVERLAY_B64:-}"
overlay="$(mktemp)"
trap 'rm -f "$overlay"' EXIT
printf '%s' "$PERSONAL_ID_OVERLAY_B64" | base64 --decode > "$overlay"
export DATARIM_PERSONAL_ID_OVERLAY="$overlay"
python3 scripts/verify-personal-id-overlay-revision.py --overlay "$overlay"
assets=(
  "$TARBALL" "${TARBALL}.sha256" "$SBOM"
  human-outcome-reporting.zip human-outcome-reporting.zip.sha256
  datarim-human-reporting-integration.zip
  datarim-human-reporting-integration.zip.sha256
  "${TARBALL}.cosign.bundle" "${SBOM}.cosign.bundle"
  human-outcome-reporting.zip.cosign.bundle
  datarim-human-reporting-integration.zip.cosign.bundle
)
for asset in "${assets[@]}"; do
  test -s "$asset" && test -f "$asset" && test ! -L "$asset"
done
scan_args=()
for asset in "${assets[@]}"; do scan_args+=(--asset "$asset"); done
python3 scripts/release_privacy_scan.py --overlay "$overlay" \
  --expected-identity "https://github.com/${GITHUB_REPOSITORY}/.github/workflows/release.yml@refs/heads/main" \
  "${scan_args[@]}"
