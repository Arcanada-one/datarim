#!/usr/bin/env bash
set -euo pipefail
asset="syft_${SYFT_VERSION#v}_linux_amd64.tar.gz"
curl -fsSL "https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/${asset}" -o "/tmp/${asset}"
echo "${SYFT_SHA256}  /tmp/${asset}" | sha256sum -c -
tar -xzf "/tmp/${asset}" -C /tmp syft
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/syft syft
export PATH="$RUNNER_TEMP/bin:$PATH"
syft version
