#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}"
asset="trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz"
workdir="$(mktemp -d "${RUNNER_TEMP:?}/trufflehog.XXXXXX")"
curl -fsSL -o "$workdir/${asset}" "${base}/${asset}"
curl -fsSL -o "$workdir/trufflehog_checksums.txt" "${base}/trufflehog_${TRUFFLEHOG_VERSION}_checksums.txt"
(cd "$workdir" && grep "${asset}" trufflehog_checksums.txt | sha256sum -c -)
tar -xzf "$workdir/${asset}" -C "$workdir" trufflehog
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "$workdir/trufflehog" trufflehog)"
export PATH="$tool_bindir:$PATH"
trufflehog --version
