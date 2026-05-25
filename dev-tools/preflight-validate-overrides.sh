#!/usr/bin/env bash
# preflight-validate-overrides.sh — schema gate for `severity-overrides` action input.
#
# Inputs (env):
#   PREFLIGHT_SEVERITY_OVERRIDES — JSON object string (e.g. '{"min_free_disk_gb": 5}').
#                                  Empty string ⇒ no-op (exit 0).
#   GITHUB_ENV                   — path to GitHub Actions env file (appended on success).
#                                  Optional; falls back to /dev/null when unset.
#
# Schema:
#   - top-level type ≡ object
#   - keys ∈ allowlist (see ALLOWLIST_KEYS below)
#   - values are integers (jq: type=number AND value%1==0)
#
# On valid input writes `PREFLIGHT_<UPPERCASE_KEY>=value` to $GITHUB_ENV for each entry.
#
# Exit:
#   0 — valid (or empty input).
#   1 — invalid (non-object / non-allowlisted key / non-integer value / malformed JSON).
#
# Used by .github/actions/preflight-check/action.yml composite step
# "Validate and export severity-overrides".

set -euo pipefail

readonly ALLOWLIST_KEYS='^(min_free_disk_gb|disk_warn_percent|disk_fail_percent|ram_warn_percent|ram_fail_percent|loadavg_fatal_multiplier)$'

overrides="${PREFLIGHT_SEVERITY_OVERRIDES:-}"
github_env="${GITHUB_ENV:-/dev/null}"

if [[ -z "$overrides" ]]; then
    exit 0
fi

if ! printf '%s' "$overrides" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERR: severity-overrides must be a JSON object" >&2
    exit 1
fi

while IFS=$'\t' read -r key value; do
    if ! [[ "$key" =~ $ALLOWLIST_KEYS ]]; then
        echo "ERR: severity-overrides key '$key' not in allowlist" >&2
        exit 1
    fi
    if ! printf '%s' "$value" | jq -e 'type == "number" and . == floor' >/dev/null 2>&1; then
        echo "ERR: severity-overrides value for '$key' must be integer (got: $value)" >&2
        exit 1
    fi
    upper_key="PREFLIGHT_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
    printf '%s=%s\n' "$upper_key" "$value" >> "$github_env"
done < <(printf '%s' "$overrides" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
