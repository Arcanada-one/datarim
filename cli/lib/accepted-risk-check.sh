#!/usr/bin/env bash
# cli/lib/accepted-risk-check.sh — invocation-time AAL gate.
# Source: TUNE-0271 plan § Detailed Design 4.4.
#
# Wraps dev-tools/check-accepted-risk-aal.sh with a 1-hour cache.
# Returns:
#   0   entry valid, not expired
#   23  entry missing/expired → caller MUST abort + critical notifier
#   1   validator IO error

set -u

CLI_AAL_EXIT_EXPIRED=23
CLI_AAL_CACHE_TTL="${DATARIM_CLI_AAL_CACHE_TTL:-3600}"

aal_check() {
    local task="${1:-TUNE-0268}"
    local repo_root validator risk_file cache_dir cache_key cache_file age mtime risk_hash
    repo_root="${DATARIM_ROOT:-$(_aal_find_root)}"
    validator="$repo_root/dev-tools/check-accepted-risk-aal.sh"
    risk_file="$repo_root/accepted-risk-aal.yml"
    if [ ! -x "$validator" ]; then
        printf '[aal-check] validator not found at %s\n' "$validator" >&2
        return 1
    fi
    cache_dir="${TMPDIR:-/tmp}/datarim-cli-aal-cache"
    mkdir -p "$cache_dir"
    if [ -f "$risk_file" ]; then
        risk_hash="$(shasum -a 256 "$risk_file" | awk '{print $1}')"
    else
        risk_hash="missing"
    fi
    cache_key=$(printf '%s' "$task-$validator-$risk_hash" | shasum -a 256 | awk '{print $1}')
    cache_file="$cache_dir/$cache_key"
    if [ -f "$cache_file" ]; then
        # GNU `stat -f %m` succeeds but prints filesystem prose, so probe the
        # GNU form first and fall back to the BSD/macOS form.
        mtime="$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || printf '0')"
        case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
        age=$(( $(date -u +%s) - mtime ))
        if [ "$age" -lt "$CLI_AAL_CACHE_TTL" ]; then
            return 0
        fi
    fi
    local rc
    if "$validator" --task "$task"; then
        : > "$cache_file"
        return 0
    else
        rc=$?
    fi
    if [ "$rc" -eq 23 ]; then
        return $CLI_AAL_EXIT_EXPIRED
    fi
    return "$rc"
}

_aal_find_root() {
    local d
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$d/.." && pwd
}
