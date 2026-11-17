#!/usr/bin/env bash
set -euo pipefail
workdir="$(mktemp -d "${RUNNER_TEMP:?}/cosign.XXXXXX")"
curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" -o "$workdir/cosign"
echo "${COSIGN_SHA256}  $workdir/cosign" | sha256sum -c -
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "$workdir/cosign" cosign)"
export PATH="$tool_bindir:$PATH"
cosign version
