#!/usr/bin/env bash
set -euo pipefail
if command -v yq >/dev/null 2>&1; then
  yq --version
  exit 0
fi
curl -fsSL -o /tmp/yq_linux_amd64 \
  https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/yq_linux_amd64 yq
export PATH="/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.local/share/cursor-agent/versions/2026.11.13-eacade1:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/bin:/home/dev/.local/bin:/home/dev/.npm-global/bin:/home/dev/.config/orca/cli/bin:/home/dev/.local/bin:/home/dev/bin:/home/dev/.npm-global/bin:/home/dev/.minimax-code/bin:/home/dev/.cargo/bin:/opt/orca/v1.4.232/squashfs-root:/opt/orca/v1.4.232/squashfs-root/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/home/dev/aup/bin:/home/dev/aup/bin:/home/dev/aup/bin"
yq --version
