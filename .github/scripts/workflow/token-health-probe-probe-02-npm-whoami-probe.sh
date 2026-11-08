#!/usr/bin/env bash
set -euo pipefail
set -uo pipefail
url="${REGISTRY_URL:-https://registry.npmjs.org}"
# curl -H Bearer against /-/whoami: returns {"username":"..."} on valid,
# empty {} or error on expired/invalid.
body=$(curl -fsS -H "Authorization: Bearer ${TOKEN}" "${url}/-/whoami" || true)
echo "Response body: ${body}"
case "$body" in
  *'"username"'*) echo "npm token live"; exit 0 ;;
  *) echo "::error::npm token expired or invalid (whoami returned no username)"; exit 89 ;;
esac
