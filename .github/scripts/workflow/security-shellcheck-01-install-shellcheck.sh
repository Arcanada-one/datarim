#!/usr/bin/env bash
set -euo pipefail
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --version
  exit 0
fi
ver="v0.10.0"
mkdir -p "${RUNNER_TEMP:?}/bin"
curl -sSfL "https://github.com/koalaman/shellcheck/releases/download/${ver}/shellcheck-${ver}.linux.x86_64.tar.xz" \
  | tar -xJ -C "$RUNNER_TEMP/bin" "shellcheck-${ver}/shellcheck" --strip-components=1
chmod +x "$RUNNER_TEMP/bin/shellcheck"
echo "$RUNNER_TEMP/bin" >> "${GITHUB_PATH:?}"
export PATH="$RUNNER_TEMP/bin:$PATH"
shellcheck --version
