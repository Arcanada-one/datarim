#!/usr/bin/env bash
set -euo pipefail
echo "::error::unknown provider: ${PROVIDER} — supported: npm, pypi, cloudflare, dockerhub"
exit 2
