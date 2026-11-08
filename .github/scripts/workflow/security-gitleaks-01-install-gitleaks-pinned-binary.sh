#!/usr/bin/env bash
set -euo pipefail
curl -fsSL -o /tmp/gitleaks.tar.gz \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
actual="$(sha256sum /tmp/gitleaks.tar.gz | awk '{print $1}')"
if [ "$actual" != "$GITLEAKS_SHA256" ]; then
  echo "::error::gitleaks tarball SHA256 mismatch (expected $GITLEAKS_SHA256, got $actual)"
  exit 1
fi
tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
sudo install -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks
gitleaks version
