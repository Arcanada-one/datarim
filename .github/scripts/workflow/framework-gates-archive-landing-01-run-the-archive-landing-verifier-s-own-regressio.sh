#!/usr/bin/env bash
set -euo pipefail
if ! command -v bats >/dev/null 2>&1; then
  sudo apt-get update -qq && sudo apt-get install -y -qq bats
fi
bats dev-tools/tests/check-archive-landing.bats
