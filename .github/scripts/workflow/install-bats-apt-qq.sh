#!/usr/bin/env bash
# Quiet apt bats install (framework-gates / security variants).
set -euo pipefail
sudo apt-get update -qq
sudo apt-get install -y -qq bats
