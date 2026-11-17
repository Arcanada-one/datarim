#!/usr/bin/env bash
set -euo pipefail
report_path="${RUNNER_TEMP:?}/gitleaks.sarif"
gitleaks detect --redact --no-banner --exit-code 1 \
  --log-opts="--all" \
  --report-format sarif --report-path "$report_path"
