#!/usr/bin/env bash
# Install bats-core (and optional peers) via Homebrew on macOS runners.
set -euo pipefail
if [ "$#" -eq 0 ]; then
  set -- bats-core
fi
brew install "$@"
