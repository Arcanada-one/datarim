#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}"
asset="osv-scanner_linux_amd64"
curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"
curl -fsSL -o "/tmp/osv-scanner_SHA256SUMS" "${base}/osv-scanner_SHA256SUMS"
(cd /tmp && grep "${asset}" osv-scanner_SHA256SUMS | sha256sum -c -)
sudo install -m 0755 "/tmp/${asset}" /usr/local/bin/osv-scanner
osv-scanner --version
