#!/usr/bin/env bash
set -euo pipefail
base="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
workdir="$(mktemp -d "${RUNNER_TEMP:?}/actionlint.XXXXXX")"
curl -fsSL -o "$workdir/${asset}" "${base}/${asset}"
curl -fsSL -o "$workdir/actionlint_checksums.txt" "${base}/actionlint_${ACTIONLINT_VERSION}_checksums.txt"
(cd "$workdir" && grep "${asset}" actionlint_checksums.txt | sha256sum -c -)
tar -xzf "$workdir/${asset}" -C "$workdir" actionlint
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "$workdir/actionlint" actionlint)"
export PATH="$tool_bindir:$PATH"
actionlint --version
