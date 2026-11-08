#!/usr/bin/env bash
set -euo pipefail
set -uo pipefail
url="${REGISTRY_URL:-https://upload.pypi.org/legacy/}"
code=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${TOKEN}" "$url")
echo "HTTP status: $code"
case "$code" in
  200|405) echo "pypi token accepted by upload endpoint"; exit 0 ;;
  401|403) echo "::error::pypi token expired or invalid (HTTP $code)"; exit 89 ;;
  *) echo "::error::pypi probe unexpected HTTP $code (treat as expired)"; exit 89 ;;
esac
