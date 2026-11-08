#!/usr/bin/env bash
set -euo pipefail
set -uo pipefail
if [ -z "${DH_USER:-}" ]; then
  echo "::error::dockerhub provider requires secrets.dockerhub_username"
  exit 89
fi
url="${REGISTRY_URL:-https://hub.docker.com/v2/users/login}"
code=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${DH_USER}\",\"password\":\"${TOKEN}\"}" \
  "$url")
echo "HTTP status: $code"
case "$code" in
  200) echo "dockerhub creds live"; exit 0 ;;
  401) echo "::error::dockerhub creds expired or invalid (HTTP 401)"; exit 89 ;;
  *) echo "::error::dockerhub probe unexpected HTTP $code (treat as expired)"; exit 89 ;;
esac
