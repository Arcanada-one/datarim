#!/usr/bin/env bash
# Install bats from apt for Ubuntu GitHub-hosted runners.
# Kept out of workflow `run:` bodies so the graph verifier sees only a static
# `bash .github/scripts/workflow/install-bats-apt.sh` invocation.
set -euo pipefail
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends bats
