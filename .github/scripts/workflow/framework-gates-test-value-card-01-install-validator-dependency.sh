#!/usr/bin/env bash
set -euo pipefail
# Pins must stay visible for scorecard-contract.bats (pkg==ver).
# Keep versions identical to tests/ci-requirements/framework-gates-test-value-card.txt.
bash .github/scripts/workflow/install-python-pkg-venv.sh test-value-card-venv 'pyyaml==6.0.3'
