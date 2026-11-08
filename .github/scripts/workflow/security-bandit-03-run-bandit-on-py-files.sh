#!/usr/bin/env bash
set -euo pipefail
if find . -name '*.py' -not -path './.git/*' -not -path './_extracted/*' -not -path './tests/security/fixtures/sast-unsafe.py' | head -1 | grep -q .; then
  bandit -r . -ll -ii -x ./_extracted,./.git,./tests/security/fixtures/sast-unsafe.py
else
  echo "no python sources"
fi
