#!/usr/bin/env bash
set -euo pipefail
# Pins must stay visible for scorecard-contract.bats (pkg==ver).
# Keep versions identical to tests/ci-requirements/framework-gates-human-reporting.txt.
python3 -m pip install --disable-pip-version-check 'pytest==9.2.0' 'pyyaml==6.0.3' 'jsonschema==4.26.0'
