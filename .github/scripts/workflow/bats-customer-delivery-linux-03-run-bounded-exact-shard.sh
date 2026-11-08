#!/usr/bin/env bash
set -euo pipefail
: "${GROUP_MEMBERS:?GROUP_MEMBERS required}"
result_dir="$RUNNER_TEMP/customer-delivery-result"
mkdir -p "$result_dir"
# Each logical shard keeps its own timeout and result JSON. A partial
# failure still records siblings; the aggregate fails on any missing
# required logical result.
/usr/bin/python3 tests/run-customer-delivery-shard.py \
  --group-members "$GROUP_MEMBERS" \
  --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python" \
  --platform linux \
  --result-dir "$result_dir"
