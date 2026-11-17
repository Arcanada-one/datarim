#!/usr/bin/env bash
set -euo pipefail
curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" -o /tmp/cosign
echo "${COSIGN_SHA256}  /tmp/cosign" | sha256sum -c -
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/cosign cosign)"
export PATH="$tool_bindir:$PATH"
cosign version
