#!/usr/bin/env bash
set -euo pipefail
workdir="$(mktemp -d "${RUNNER_TEMP:?}/gitleaks.XXXXXX")"
curl -fsSL -o "$workdir/gitleaks.tar.gz" \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
actual="$(sha256sum "$workdir/gitleaks.tar.gz" | awk '{print $1}')"
if [ "$actual" != "$GITLEAKS_SHA256" ]; then
  echo "::error::gitleaks tarball SHA256 mismatch (expected $GITLEAKS_SHA256, got $actual)"
  exit 1
fi
tar -xzf "$workdir/gitleaks.tar.gz" -C "$workdir" gitleaks
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "$workdir/gitleaks" gitleaks)"
export PATH="$tool_bindir:$PATH"
gitleaks version
