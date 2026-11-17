#!/usr/bin/env bash
# Install a single already-downloaded binary under $RUNNER_TEMP and put it on
# PATH for later steps. No sudo. Prefer the stable $RUNNER_TEMP/bin path that
# callers export in the same step; if a privileged helper left it root-owned,
# fall back to a fresh mktemp directory and print that path on stdout.
set -euo pipefail
src="${1:?source binary path required}"
name="${2:?tool name required}"
bindir="${RUNNER_TEMP:?}/bin"
if [ -e "$bindir" ] && [ ! -w "$bindir" ]; then
  mv "$bindir" "${RUNNER_TEMP}/bin.root-owned.$$" 2>/dev/null || true
fi
if ! mkdir -p "$bindir" 2>/dev/null || [ ! -w "$bindir" ]; then
  bindir="$(mktemp -d "${RUNNER_TEMP}/toolbin.XXXXXX")"
fi
install -m 0755 "$src" "$bindir/$name"
echo "$bindir" >> "${GITHUB_PATH:?}"
# Same-step callers: export PATH="$(...)/bin:$PATH" still works when bindir is
# the stable path; when we fell back, they must use the printed path.
printf '%s\n' "$bindir"
