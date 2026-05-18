#!/usr/bin/env bash
# preflight-validate-url.sh — ops-bot-url allowlist guard (PROD strict, non-PROD WARN).
#
# Inputs (env):
#   PREFLIGHT_OPS_BOT_URL        — URL string to validate.
#   PREFLIGHT_IS_PROD_CONTEXT    — 'true' if invoked from PROD trigger context
#                                  (push on main/master/release/*), else 'false'.
#
# Exit:
#   0  — URL canonical (PROD or non-PROD), or non-PROD non-canonical (WARN to stderr).
#   1  — PROD non-canonical (block deploy).
#
# Canonical URL: https://ops.arcanada.one/events
#
# Used by .github/actions/preflight-check/action.yml composite step
# "Validate ops-bot-url against PROD allowlist".

set -euo pipefail

readonly ALLOWLIST_REGEX='^https://ops\.arcanada\.one/events$'

url="${PREFLIGHT_OPS_BOT_URL:-}"
is_prod="${PREFLIGHT_IS_PROD_CONTEXT:-false}"

if [[ -z "$url" ]]; then
    echo "ERR: PREFLIGHT_OPS_BOT_URL is empty" >&2
    exit 1
fi

if [[ "$url" =~ $ALLOWLIST_REGEX ]]; then
    exit 0
fi

if [[ "$is_prod" == "true" ]]; then
    echo "ERR: ops-bot-url must match canonical https://ops.arcanada.one/events for PROD trigger contexts (got: $url)" >&2
    exit 1
fi

echo "WARN: ops-bot-url $url does not match canonical; non-PROD context, continuing" >&2
exit 0
