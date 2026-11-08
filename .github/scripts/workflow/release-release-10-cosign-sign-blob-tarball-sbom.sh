#!/usr/bin/env bash
set -euo pipefail
for f in "$TARBALL" "$SBOM" human-outcome-reporting.zip datarim-human-reporting-integration.zip; do
  cosign sign-blob --bundle "${f}.cosign.bundle" --yes "$f"
  test -s "${f}.cosign.bundle"
done
