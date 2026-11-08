#!/usr/bin/env bash
set -euo pipefail
set -uo pipefail
url="${REGISTRY_URL:-https://api.cloudflare.com/client/v4/user/tokens/verify}"
[ -n "$CF_EXTRA" ] && url="${url}?${CF_EXTRA}"
body=$(curl -fsS -H "Authorization: Bearer ${TOKEN}" "$url" || true)
echo "Response body: ${body}"
case "$body" in
  *'"success":true'*) echo "cloudflare token live"; exit 0 ;;
  *) echo "::error::cloudflare token expired or invalid"; exit 89 ;;
esac
