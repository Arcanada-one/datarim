#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}"
asset="osv-scanner_linux_amd64"
curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"
curl -fsSL -o "/tmp/osv-scanner_SHA256SUMS" "${base}/osv-scanner_SHA256SUMS"
(cd /tmp && grep "${asset}" osv-scanner_SHA256SUMS | sha256sum -c -)
bash .github/scripts/workflow/install-tool-to-runner-temp.sh "/tmp/${asset}" osv-scanner
export PATH="/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.local/share/cursor-agent/versions/2026.11.13-eacade1:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.cargo/bin:/opt/orca/v1.4.232/squashfs-root:/opt/orca/v1.4.232/squashfs-root/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/home/dev/aup/bin:/home/dev/aup/bin:/home/dev/aup/bin"
osv-scanner --version
