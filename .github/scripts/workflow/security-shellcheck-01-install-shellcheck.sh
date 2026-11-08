#!/usr/bin/env bash
set -euo pipefail
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --version
  exit 0
fi
# GitHub-hosted images occasionally ship transiently broken Microsoft
# apt entries; shellcheck comes from Ubuntu, so disable those sources
# inside this job instead of letting external repo drift block release.
sudo find /etc/apt/sources.list.d -type f \
  \( -name '*microsoft*' -o -name '*azure-cli*' \) -delete
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends shellcheck
