#!/usr/bin/env bash
set -euo pipefail
if find _extracted -name '*.py' | head -1 | grep -q .; then
  bandit -r _extracted -ll -ii
else
  echo "no extracted python blocks"
fi
