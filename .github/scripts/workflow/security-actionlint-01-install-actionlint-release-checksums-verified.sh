#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"
curl -fsSL -o "/tmp/actionlint_checksums.txt" "${base}/actionlint_${ACTIONLINT_VERSION}_checksums.txt"
(cd /tmp && grep "${asset}" actionlint_checksums.txt | sha256sum -c -)
tar -xzf "/tmp/${asset}" -C /tmp actionlint
sudo install -m 0755 /tmp/actionlint /usr/local/bin/actionlint
actionlint --version
