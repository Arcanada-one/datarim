#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}"
asset="trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz"
curl -fsSL -o "/tmp/${asset}" "${base}/${asset}"
curl -fsSL -o "/tmp/trufflehog_checksums.txt" "${base}/trufflehog_${TRUFFLEHOG_VERSION}_checksums.txt"
(cd /tmp && grep "${asset}" trufflehog_checksums.txt | sha256sum -c -)
tar -xzf "/tmp/${asset}" -C /tmp trufflehog
bash .github/scripts/workflow/install-tool-to-runner-temp.sh /tmp/trufflehog trufflehog
export PATH="$RUNNER_TEMP/bin:$PATH"
trufflehog --version
