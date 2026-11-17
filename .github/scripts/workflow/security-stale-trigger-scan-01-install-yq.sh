#!/usr/bin/env bash
set -euo pipefail
if command -v yq >/dev/null 2>&1; then
  yq --version
  exit 0
fi
curl -fsSL -o /tmp/yq_linux_amd64 \
  https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/yq_linux_amd64 yq)"
export PATH="$tool_bindir:$PATH"
yq --version
