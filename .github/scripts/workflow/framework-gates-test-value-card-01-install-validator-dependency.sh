#!/usr/bin/env bash
set -euo pipefail
# Pins must stay visible for scorecard-contract.bats (pkg==ver).
# Keep versions identical to tests/ci-requirements/framework-gates-test-value-card.txt.
python3 -m pip install --disable-pip-version-check 'pyyaml==6.0.2'
