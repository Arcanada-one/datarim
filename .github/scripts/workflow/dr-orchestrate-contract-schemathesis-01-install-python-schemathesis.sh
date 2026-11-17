#!/usr/bin/env bash
set -euo pipefail
bash .github/scripts/workflow/install-python-pkg-venv.sh schemathesis-venv 'schemathesis==4.25.2'
