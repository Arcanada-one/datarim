#!/usr/bin/env bash
set -euo pipefail
# ci-general is the org's self-hosted CI lane label (bats.yml). Declared via
# -ignore rather than .github/actionlint.yaml (retired surface per scorecard-contract).
actionlint -color -ignore 'label "ci-general" is unknown'
