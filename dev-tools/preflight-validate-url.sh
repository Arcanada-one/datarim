#!/usr/bin/env bash
# Exact HTTPS /events endpoint guard. All contexts fail closed before host checks.
# PREFLIGHT_ALLOWED_HOSTS: caller-controlled newline-separated DNS hostnames.
# PREFLIGHT_OPS_BOT_URL: endpoint; no credentials, port, query or fragment allowed.
# No default host or URL is authorized. Diagnostics never echo caller values.
set -euo pipefail
export LC_ALL=C

reject() { echo "ERR: $1" >&2; exit 1; }
url="${PREFLIGHT_OPS_BOT_URL:-}"
hosts="${PREFLIGHT_ALLOWED_HOSTS:-}"
[[ -n "$url" ]] || reject 'PREFLIGHT_OPS_BOT_URL is empty'
[[ -n "$hosts" && ${#hosts} -le 16384 ]] || reject 'allowed_hosts must be a nonempty bounded DNS hostname list'

count=0
matched=false
while IFS= read -r host || [[ -n "$host" ]]; do
    count=$((count + 1))
    [[ $count -le 64 && ${#host} -le 253 && "$host" =~ ^[a-z0-9.-]+$ && "$host" == *.* && "$host" != *..* ]] || reject 'allowed_hosts contains an invalid DNS hostname'
    # Alphabetic final label excludes IP literals; no wildcard or suffix matching.
    [[ "${host##*.}" =~ ^[a-z][a-z0-9-]*$ ]] || reject 'allowed_hosts must contain DNS hostnames, not IP literals'
    IFS='.' read -r -a labels <<< "$host"
    for label in "${labels[@]}"; do
        [[ ${#label} -ge 1 && ${#label} -le 63 && "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || reject 'allowed_hosts contains an invalid DNS label'
    done
    [[ "$host" != *. ]] || reject 'allowed_hosts contains a trailing dot'
    if [[ "$url" == "https://$host/events" ]]; then matched=true; fi
    # Validate every entry even after a match: malformed policy must never pass.
done < <(printf '%s' "$hosts")
[[ "$matched" == true ]] || reject 'ops-bot-url must match an allowed HTTPS /events endpoint'
