#!/usr/bin/env bash
set -euo pipefail
if command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck already present: $(command -v shellcheck)"
  exit 0
fi
ver="v0.10.0"
curl -sSfL "https://github.com/koalaman/shellcheck/releases/download/${ver}/shellcheck-${ver}.linux.x86_64.tar.xz" \
  | tar -xJ -C "$RUNNER_TEMP" "shellcheck-${ver}/shellcheck" --strip-components=1
chmod +x "$RUNNER_TEMP/shellcheck"
echo "$RUNNER_TEMP" >> "$GITHUB_PATH"
echo "shellcheck ${ver} provisioned to RUNNER_TEMP"
