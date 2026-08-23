#!/usr/bin/env bash
# cli/lib/accepted-risk-check.sh — invocation-time AAL gate.
# Source: TUNE-0271 plan § Detailed Design 4.4.
#
# Wraps dev-tools/check-accepted-risk-aal.sh. The validator runs on every
# invocation: a cross-process success cache would let caller-controlled cache
# bytes bypass expiry enforcement.
# Returns:
#   0   entry valid, not expired
#   23  entry missing/expired → caller MUST abort + critical notifier
#   1   validator IO error

set -u

CLI_AAL_EXIT_EXPIRED=23

aal_check() {
    local task="${1:-TUNE-0268}"
    local repo_root validator rc
    repo_root="$(_aal_find_root)"
    validator="$repo_root/dev-tools/check-accepted-risk-aal.sh"
    if [ ! -x "$validator" ]; then
        printf '[aal-check] validator not found at %s\n' "$validator" >&2
        return 1
    fi
    if "$validator" --task "$task"; then
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
