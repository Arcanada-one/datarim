#!/usr/bin/env bash
set -euo pipefail
curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" -o /tmp/cosign
echo "${COSIGN_SHA256}  /tmp/cosign" | sha256sum -c -
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/cosign cosign
export PATH="$RUNNER_TEMP/bin:$PATH"
cosign version
