#!/usr/bin/env bash
set -euo pipefail
curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" -o /tmp/cosign
echo "${COSIGN_SHA256}  /tmp/cosign" | sha256sum -c -
sudo install -m 0755 /tmp/cosign /usr/local/bin/cosign
cosign version
