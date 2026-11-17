#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}"
asset="osv-scanner_linux_amd64"
curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"
curl -fsSL -o "/tmp/osv-scanner_SHA256SUMS" "${base}/osv-scanner_SHA256SUMS"
(cd /tmp && grep "${asset}" osv-scanner_SHA256SUMS | sha256sum -c -)
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "/tmp/${asset}" osv-scanner)"
export PATH="$tool_bindir:$PATH"
osv-scanner --version
