#!/usr/bin/env bash
set -euo pipefail
: "${GROUP_MEMBERS:?GROUP_MEMBERS required}"
result_dir="$RUNNER_TEMP/customer-delivery-result"
mkdir -p "$result_dir"
skip_log="$result_dir/capability-skips.${CUSTOMER_DELIVERY_JOB_INDEX:-local}.txt"
: >"$skip_log"
export CUSTOMER_DELIVERY_SKIP_LOG="$skip_log"
# Hosted macOS images provide passwordless sudo → expected skip count 0.
export CUSTOMER_DELIVERY_RUNNER_CLASS="${CUSTOMER_DELIVERY_RUNNER_CLASS:-hosted-with-sudo}"
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --group-members "$GROUP_MEMBERS" \
  --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python" \
  --test-python-bin "$GITHUB_WORKSPACE/tests/customer-delivery-test-python.sh" \
  --platform macos \
  --result-dir "$result_dir"
