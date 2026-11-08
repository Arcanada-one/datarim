#!/usr/bin/env bash
set -euo pipefail
cd plugins/dr-orchestrate
bash tests/contract/run-schemathesis.sh \
  --base-url http://127.0.0.1:8090 \
  --max-examples 20
