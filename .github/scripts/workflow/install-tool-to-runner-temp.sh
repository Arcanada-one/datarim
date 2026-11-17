#!/usr/bin/env bash
# Install a single already-downloaded binary into $RUNNER_TEMP/bin and put it
# on PATH for later steps. No sudo: self-hosted runners may require a password.
set -euo pipefail
src="${1:?source binary path required}"
name="${2:?tool name required}"
mkdir -p "${RUNNER_TEMP:?}/bin"
install -m 0755 "$src" "$RUNNER_TEMP/bin/$name"
echo "$RUNNER_TEMP/bin" >> "${GITHUB_PATH:?}"
export PATH="$RUNNER_TEMP/bin:$PATH"
