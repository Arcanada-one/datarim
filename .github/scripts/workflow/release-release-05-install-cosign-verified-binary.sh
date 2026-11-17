#!/usr/bin/env bash
set -euo pipefail
curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" -o /tmp/cosign
echo "${COSIGN_SHA256}  /tmp/cosign" | sha256sum -c -
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/cosign cosign
export PATH="/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.local/share/cursor-agent/versions/2026.11.13-eacade1:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.cargo/bin:/opt/orca/v1.4.232/squashfs-root:/opt/orca/v1.4.232/squashfs-root/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/home/dev/aup/bin:/home/dev/aup/bin:/home/dev/aup/bin"
cosign version
