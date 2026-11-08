#!/usr/bin/env bash
set -euo pipefail
: "${BATS_SHARD:?BATS_SHARD matrix shard required}"
CUSTOMER_CI_PYTHON="$RUNNER_TEMP/discovery-venv/bin/python" \
  bash tests/run-bats-discovery.sh --shard "${BATS_SHARD}/8"
