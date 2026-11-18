#!/usr/bin/env bash
set -euo pipefail
# General self-hosted pool lacks passwordless sudo → two visible capability skips.
export CUSTOMER_DELIVERY_RUNNER_CLASS="${CUSTOMER_DELIVERY_RUNNER_CLASS:-ci-general}"
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --check-results linux "$RUNNER_TEMP/customer-delivery-results/linux"
# macOS/BSD customer-delivery and portability coverage is NOT_MEASURED: this
# repository forbids GitHub-hosted runners and the fleet has no macOS self-hosted
# runner. Linux inventory success does not establish BSD/macOS acceptance.
echo "macOS/BSD coverage: NOT_MEASURED (no hosted runners; no macOS self-hosted runner in fleet)" >> "$GITHUB_STEP_SUMMARY"
