#!/usr/bin/env bash
set -euo pipefail
: "${GROUP_MEMBERS:?GROUP_MEMBERS required}"
result_dir="$RUNNER_TEMP/customer-delivery-result"
mkdir -p "$result_dir"
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --group-members "$GROUP_MEMBERS" \
  --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python" \
  --test-python-bin "$GITHUB_WORKSPACE/tests/customer-delivery-test-python.sh" \
  --platform macos \
  --result-dir "$result_dir"
