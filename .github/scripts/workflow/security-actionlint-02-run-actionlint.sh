#!/usr/bin/env bash
set -euo pipefail
# ci-general / docker are org self-hosted labels (bats.yml). Declared via -ignore
# rather than .github/actionlint.yaml (retired surface per scorecard-contract).
actionlint -color \
  -ignore 'label "ci-general" is unknown' \
  -ignore 'label "docker" is unknown'
