#!/usr/bin/env bash
set -euo pipefail
if command -v bats >/dev/null 2>&1; then
  bats --version
  exit 0
fi
sudo find /etc/apt/sources.list.d -type f \
  \( -name '*microsoft*' -o -name '*azure-cli*' \) -delete
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends bats
