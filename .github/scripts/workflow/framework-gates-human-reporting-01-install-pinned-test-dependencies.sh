#!/usr/bin/env bash
set -euo pipefail
# Pins must stay visible for scorecard-contract.bats (pkg==ver).
# Keep versions identical to tests/ci-requirements/framework-gates-human-reporting.txt.
python3 -m pip install --disable-pip-version-check 'pytest==8.3.5' 'pyyaml==6.0.2' 'jsonschema==4.23.0'
