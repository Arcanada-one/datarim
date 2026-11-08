#!/usr/bin/env bash
set -euo pipefail
: "${SUITE:?SUITE required}"
: "${SHARD:?SHARD required}"
result_dir="$RUNNER_TEMP/customer-delivery-result"
shard="$SHARD"
mkdir -p "$result_dir"
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --suite "$SUITE" --shard "$SHARD" \
  --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python" \
  --test-python-bin "$GITHUB_WORKSPACE/tests/customer-delivery-test-python.sh" \
  --platform macos \
  --result-file "$result_dir/${SUITE}-${shard//\//-}.json"
