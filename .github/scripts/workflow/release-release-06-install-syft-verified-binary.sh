#!/usr/bin/env bash
set -euo pipefail
asset="syft_${SYFT_VERSION#v}_linux_amd64.tar.gz"
curl -fsSL "https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/${asset}" -o "/tmp/${asset}"
echo "${SYFT_SHA256}  /tmp/${asset}" | sha256sum -c -
tar -xzf "/tmp/${asset}" -C /tmp syft
sudo install -m 0755 /tmp/syft /usr/local/bin/syft
syft version
