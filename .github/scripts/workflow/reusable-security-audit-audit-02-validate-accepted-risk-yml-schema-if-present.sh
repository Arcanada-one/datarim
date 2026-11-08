#!/usr/bin/env bash
set -euo pipefail
if [ -f "$ACCEPTED_RISK_PATH" ]; then
  bash ./.datarim/dev-tools/check-security-policy.sh \
    --validate-yaml "$ACCEPTED_RISK_PATH"
else
  echo "accepted-risk.yml not present at $ACCEPTED_RISK_PATH — skipping schema validation"
fi
