#!/usr/bin/env bash
set -euo pipefail
if ! command -v yq >/dev/null 2>&1; then
  sudo wget -qO /usr/local/bin/yq \
    https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
  sudo chmod +x /usr/local/bin/yq
fi
yq --version
