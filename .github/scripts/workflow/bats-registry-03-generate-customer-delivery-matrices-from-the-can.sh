#!/usr/bin/env bash
set -euo pipefail
# Batched runner jobs: group size comes from tests/ci-slot-baseline.json
# (measured peak concurrency), not a fixed workflow constant. Flat
# logical inventory for --check-results is unchanged.
echo "linux=$(/usr/bin/python3 tests/run-customer-delivery-shard.py --matrix-jobs linux)" >> "$GITHUB_OUTPUT"
echo "macos=$(/usr/bin/python3 tests/run-customer-delivery-shard.py --matrix-jobs macos)" >> "$GITHUB_OUTPUT"
