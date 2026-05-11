#!/usr/bin/env bash
# check-agent0017-live.sh — V-AC-11: manual gate before setting DR_ORCH_ESCALATION_DEVBOT_URL.
# Probes AGENT-0017 (devbot) healthz + smoke POST /prompts.
# Run this script BEFORE setting DR_ORCH_ESCALATION_DEVBOT_URL in production.
#
# Usage:
#   check-agent0017-live.sh [--base-url <url>] [--token <bearer>]
#
# Exit codes:
#   0 — both probes pass (safe to set DR_ORCH_ESCALATION_DEVBOT_URL)
#   1 — healthz failed
#   2 — /prompts smoke probe failed
#   3 — base URL not provided and DR_ORCH_DEVBOT_CHECK_URL not set
set -euo pipefail

BASE_URL="${DR_ORCH_DEVBOT_CHECK_URL:-}"
TOKEN="${DR_ORCH_DEVBOT_CHECK_TOKEN:-}"
TIMEOUT=10

while (( $# > 0 )); do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --token)    TOKEN="$2";    shift 2 ;;
    -h|--help)
      printf 'usage: check-agent0017-live.sh [--base-url <url>] [--token <bearer>]\n' >&2
      exit 0
      ;;
    *) printf 'ERR: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$BASE_URL" ]]; then
  printf 'ERR: base URL required. Set DR_ORCH_DEVBOT_CHECK_URL or pass --base-url\n' >&2
  exit 3
fi

BASE_URL="${BASE_URL%/}"

# Probe 1: GET /healthz → expect 200
printf 'Probing GET %s/healthz ...\n' "$BASE_URL"
HTTP_CODE="$(curl -fsS --max-time "$TIMEOUT" \
  -o /dev/null \
  -w '%{http_code}' \
  "$BASE_URL/healthz" 2>/dev/null || printf '000')"
if [[ "$HTTP_CODE" != "200" ]]; then
  printf 'FAIL: /healthz returned HTTP %s (expected 200)\n' "$HTTP_CODE" >&2
  exit 1
fi
printf 'PASS: /healthz → %s\n' "$HTTP_CODE"

# Probe 2: POST /prompts with minimal smoke payload → expect 202
printf 'Probing POST %s/prompts ...\n' "$BASE_URL"
SMOKE_PAYLOAD='{"session_id":"livecheck00","command":"dr-status","ts":"2026-05-11T00:00:00Z"}'
AUTH_HEADER=""
if [[ -n "$TOKEN" ]]; then
  AUTH_HEADER="-H Authorization: Bearer ${TOKEN}"
fi
# shellcheck disable=SC2086
HTTP_CODE2="$(curl -fsS --max-time "$TIMEOUT" \
  -X POST \
  -H "Content-Type: application/json" \
  ${AUTH_HEADER:+"-H" "Authorization: Bearer ${TOKEN}"} \
  -d "$SMOKE_PAYLOAD" \
  -o /dev/null \
  -w '%{http_code}' \
  "$BASE_URL/prompts" 2>/dev/null || printf '000')"
if [[ "$HTTP_CODE2" -lt 200 ]] || [[ "$HTTP_CODE2" -ge 300 ]]; then
  printf 'FAIL: /prompts returned HTTP %s (expected 2xx)\n' "$HTTP_CODE2" >&2
  exit 2
fi
printf 'PASS: /prompts → %s\n' "$HTTP_CODE2"

printf '\nAll checks passed. Safe to set DR_ORCH_ESCALATION_DEVBOT_URL=%s\n' "$BASE_URL"
exit 0
