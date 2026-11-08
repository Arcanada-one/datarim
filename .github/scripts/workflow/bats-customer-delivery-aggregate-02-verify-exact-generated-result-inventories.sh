#!/usr/bin/env bash
set -euo pipefail
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --check-results linux "$RUNNER_TEMP/customer-delivery-results/linux"
if [[ "$RUN_HOSTED_MACOS" == true ]]; then
  /usr/bin/python3 tests/run-customer-delivery-shard.py \
    --check-results macos "$RUNNER_TEMP/customer-delivery-results/macos"
else
  echo "macOS coverage: NOT_MEASURED (hosted lane disabled; see documentation/reference/ci-runner-routing.md)" >> "$GITHUB_STEP_SUMMARY"
fi
