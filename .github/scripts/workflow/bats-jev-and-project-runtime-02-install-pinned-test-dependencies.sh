#!/usr/bin/env bash
set -euo pipefail
python3 -m venv "$RUNNER_TEMP/jev-venv"
# --python-only: this job runs unittest and nothing else. The apt
# fixtures (jq, shellcheck, socat) and the bats/yq toolchain belong to
# the bats shards, and pulling them in here made the job fail on a
# runner that has no socat and no passwordless sudo -- over tools it
# never invokes. Measured by running the full contract set with jq,
# socat and bats hidden from PATH: all suites OK.
bash tests/ci-install-bats-deps.sh --python-only \
  --python-bin "$RUNNER_TEMP/jev-venv/bin/python"
