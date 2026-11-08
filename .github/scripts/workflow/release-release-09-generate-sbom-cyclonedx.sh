#!/usr/bin/env bash
set -euo pipefail
sbom="datarim-${TAG}-sbom.cdx.json"
syft scan dir:. -o "cyclonedx-json=${sbom}"
# Sanity: bomFormat must be CycloneDX, components array non-empty.
jq -e '.bomFormat == "CycloneDX" and (.components | length > 0)' "$sbom" > /dev/null
echo "SBOM=$sbom" >> "$GITHUB_ENV"
