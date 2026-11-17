#!/usr/bin/env bash
# Install a single already-downloaded binary into a fresh $RUNNER_TEMP directory
# and put it on PATH for later steps. No sudo. Use a unique directory each time:
# a sticky $RUNNER_TEMP/bin may be left root-owned on persistent self-hosted hosts.
set -euo pipefail
src="${1:?source binary path required}"
name="${2:?tool name required}"
bindir="$(mktemp -d "${RUNNER_TEMP:?}/toolbin.XXXXXX")"
install -m 0755 "$src" "$bindir/$name"
echo "$bindir" >> "${GITHUB_PATH:?}"
export PATH="$bindir:$PATH"
