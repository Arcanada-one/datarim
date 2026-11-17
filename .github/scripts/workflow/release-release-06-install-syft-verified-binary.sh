#!/usr/bin/env bash
set -euo pipefail
asset="syft_${SYFT_VERSION#v}_linux_amd64.tar.gz"
workdir="$(mktemp -d "${RUNNER_TEMP:?}/syft.XXXXXX")"
curl -fsSL "https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/${asset}" -o "$workdir/${asset}"
echo "${SYFT_SHA256}  $workdir/${asset}" | sha256sum -c -
tar -xzf "$workdir/${asset}" -C "$workdir" syft
tool_bindir="$(bash .github/scripts/workflow/install-tool-to-runner-temp.sh "$workdir/syft" syft)"
export PATH="$tool_bindir:$PATH"
syft version
