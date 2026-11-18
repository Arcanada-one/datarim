#!/usr/bin/env bash
set -euo pipefail
# Batched runner jobs: group size comes from tests/ci-slot-baseline.json
# (measured peak concurrency), not a fixed workflow constant. Flat
# logical inventory for --check-results is unchanged. Linux only — macOS
# matrix generation is not emitted (hosted runners forbidden; coverage NOT_MEASURED).
echo "linux=$(/usr/bin/python3 tests/run-customer-delivery-shard.py --matrix-jobs linux)" >> "$GITHUB_OUTPUT"
