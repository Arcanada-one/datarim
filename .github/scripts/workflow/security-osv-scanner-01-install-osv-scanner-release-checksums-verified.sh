#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}"
asset="osv-scanner_linux_amd64"
workdir="$(mktemp -d "${RUNNER_TEMP:?}/osv-scanner.XXXXXX")"
curl -fsSL -o "$workdir/${asset}" "${base}/${asset}"
curl -fsSL -o "$workdir/osv-scanner_SHA256SUMS" "${base}/osv-scanner_SHA256SUMS"
(cd "$workdir" && grep "${asset}" osv-scanner_SHA256SUMS | sha256sum -c -)
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "$workdir/${asset}" osv-scanner)"
export PATH="$tool_bindir:$PATH"
osv-scanner --version
