#!/usr/bin/env bash
set -euo pipefail
shellcheck --version
mapfile -d '' files < <(find . -name '*.sh' -not -path './.git/*' -print0)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no shell scripts found"
  exit 0
fi
shellcheck --severity=warning "${files[@]}"
