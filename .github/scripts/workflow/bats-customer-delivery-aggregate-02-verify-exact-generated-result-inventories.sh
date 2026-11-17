#!/usr/bin/env bash
set -euo pipefail
# General self-hosted pool lacks passwordless sudo → two visible capability skips.
export CUSTOMER_DELIVERY_RUNNER_CLASS="${CUSTOMER_DELIVERY_RUNNER_CLASS:-ci-general}"
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --check-results linux "$RUNNER_TEMP/customer-delivery-results/linux"
if [[ "$RUN_HOSTED_MACOS" == true ]]; then
  CUSTOMER_DELIVERY_RUNNER_CLASS=hosted-with-sudo \
  /usr/bin/python3 tests/run-customer-delivery-shard.py \
    --check-results macos "$RUNNER_TEMP/customer-delivery-results/macos"
else
  echo "macOS coverage: NOT_MEASURED (hosted lane disabled; see documentation/reference/ci-runner-routing.md)" >> "$GITHUB_STEP_SUMMARY"
fi
