#!/usr/bin/env bash
set -euo pipefail
if ! command -v bats >/dev/null 2>&1; then
  bash .github/scripts/workflow/install-bats-apt.sh
  export PATH="${RUNNER_TEMP:?}/bats-prefix/bin:$PATH"
fi
bats dev-tools/tests/check-archive-landing.bats
