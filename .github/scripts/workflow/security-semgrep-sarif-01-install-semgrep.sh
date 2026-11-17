#!/usr/bin/env bash
set -euo pipefail
bash .github/scripts/workflow/install-python-pkg-venv.sh semgrep-venv 'semgrep==1.176.0'
