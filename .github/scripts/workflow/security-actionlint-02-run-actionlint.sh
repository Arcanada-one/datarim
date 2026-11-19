#!/usr/bin/env bash
set -euo pipefail
# ci-general is the org's self-hosted CI lane label (bats.yml). Declared via
# -ignore rather than .github/actionlint.yaml (retired surface per scorecard-contract).
# job.workflow_sha is documented for reusable workflows; actionlint 1.7.7's job
# schema omits it (rhysd/actionlint#647/#757). Ignore that false positive so the
# datarim_ref equality gate can bind the called-workflow pin.
actionlint -color \
  -ignore 'label "ci-general" is unknown' \
  -ignore 'property "workflow_sha" is not defined'
