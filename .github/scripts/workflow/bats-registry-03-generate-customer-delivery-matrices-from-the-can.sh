#!/usr/bin/env bash
set -euo pipefail
echo "linux=$(/usr/bin/python3 tests/run-customer-delivery-shard.py --matrix linux)" >> "$GITHUB_OUTPUT"
echo "macos=$(/usr/bin/python3 tests/run-customer-delivery-shard.py --matrix macos)" >> "$GITHUB_OUTPUT"
