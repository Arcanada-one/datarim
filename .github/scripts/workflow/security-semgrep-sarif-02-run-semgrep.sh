#!/usr/bin/env bash
set -euo pipefail
set +e
semgrep scan --config .semgrep.yml --error --sarif --output semgrep.sarif \
  --exclude tests/security/fixtures \
  --exclude _extracted \
  .
scan_status=$?
set -e
jq -e '.runs | type == "array"' semgrep.sarif >/dev/null
if [ "$scan_status" -ne 0 ]; then
  jq -e '[.runs[].results[]?] | length > 0' semgrep.sarif >/dev/null
fi
exit "$scan_status"
