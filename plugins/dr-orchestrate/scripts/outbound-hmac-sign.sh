#!/usr/bin/env bash
# outbound-hmac-sign.sh — HMAC-SHA256 signing for outbound escalation events.
# Computes X-Signature and X-Timestamp headers; posts payload to callback URL.
#
# Public functions:
#   sign_and_post <url> <secret> <payload>   — sign + POST via curl
#   compute_sig   <secret> <ts> <payload>    — return hex signature only
#   get_timestamp                             — return current unix epoch
#
# Signature scheme: HMAC-SHA256( "${timestamp}${payload}", secret )
# Header: X-Signature: hmac-sha256=<hex64>
#         X-Timestamp: <unix-epoch>
set -euo pipefail

get_timestamp() {
  date +%s
}

# compute_sig <secret> <timestamp> <payload> → hex string (stdout)
compute_sig() {
  local secret="$1"; local ts="$2"; local payload="$3"
  printf '%s' "${ts}${payload}" \
    | openssl dgst -sha256 -hmac "$secret" \
    | awk '{print $2}'
}

# sign_and_post <url> <secret> <payload>
# Posts payload with HMAC signature headers. Exits non-zero on curl error.
# Curl errors are propagated; callers should handle gracefully.
sign_and_post() {
  local url="$1"; local secret="$2"; local payload="$3"
  local ts sig
  ts="$(get_timestamp)"
  sig="$(compute_sig "$secret" "$ts" "$payload")"
  curl -fsS \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Signature: hmac-sha256=${sig}" \
    -H "X-Timestamp: ${ts}" \
    -d "$payload" \
    "$url"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { printf 'usage: outbound-hmac-sign.sh <fn> [args]\n' >&2; exit 2; }
  "$fn" "$@"
fi
