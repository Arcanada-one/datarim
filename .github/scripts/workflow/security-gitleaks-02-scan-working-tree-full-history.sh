#!/usr/bin/env bash
set -euo pipefail
gitleaks detect --redact --no-banner --exit-code 1 \
  --log-opts="--all" \
  --report-format sarif --report-path /tmp/gitleaks.sarif
