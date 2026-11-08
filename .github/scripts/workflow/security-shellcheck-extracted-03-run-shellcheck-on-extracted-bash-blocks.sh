#!/usr/bin/env bash
set -euo pipefail
mapfile -d '' files < <(find _extracted -name '*.sh' -print0 2>/dev/null || true)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no extracted shell blocks"
  exit 0
fi
shellcheck --severity=warning --shell=bash "${files[@]}"
