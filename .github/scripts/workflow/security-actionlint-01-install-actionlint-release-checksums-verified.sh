#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"
curl -fsSL -o "/tmp/actionlint_checksums.txt" "${base}/actionlint_${ACTIONLINT_VERSION}_checksums.txt"
(cd /tmp && grep "${asset}" actionlint_checksums.txt | sha256sum -c -)
tar -xzf "/tmp/${asset}" -C /tmp actionlint
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/actionlint actionlint
export PATH="/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.local/share/cursor-agent/versions/2026.11.13-eacade1:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.cargo/bin:/opt/orca/v1.4.232/squashfs-root:/opt/orca/v1.4.232/squashfs-root/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/home/dev/aup/bin:/home/dev/aup/bin:/home/dev/aup/bin"
actionlint --version
