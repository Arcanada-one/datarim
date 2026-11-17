#!/usr/bin/env bash
set -euo pipefail
asset="syft_${SYFT_VERSION#v}_linux_amd64.tar.gz"
curl -fsSL "https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/${asset}" -o "/tmp/${asset}"
echo "${SYFT_SHA256}  /tmp/${asset}" | sha256sum -c -
tar -xzf "/tmp/${asset}" -C /tmp syft
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/syft syft
export PATH="/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.local/share/cursor-agent/versions/2026.11.13-eacade1:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.cargo/bin:/opt/orca/v1.4.232/squashfs-root:/opt/orca/v1.4.232/squashfs-root/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/home/dev/aup/bin:/home/dev/aup/bin:/home/dev/aup/bin"
syft version
