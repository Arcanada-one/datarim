#!/usr/bin/env bash
set -euo pipefail
bash .github/scripts/workflow/install-python-pkg-venv.sh bandit-extracted-venv 'bandit==1.9.4'
