#!/usr/bin/env bash
set -euo pipefail
mapfile -d '' mds < <(find skills agents commands templates docs -name '*.md' -print0 2>/dev/null || true)
if [ "${#mds[@]}" -eq 0 ]; then
  echo "no markdown files in scoped dirs"
  exit 0
fi
mkdir -p _extracted
bash tests/security/extract-code-blocks.sh -o _extracted "${mds[@]}"
