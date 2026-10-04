#!/usr/bin/env bash
# gates/gate-no-secrets.sh — reject a skill candidate that leaks secret-like tokens.
#
# argv[1] = candidate file, argv[2] = skill level (unused; uniform signature).
# exit 0 = clean, exit 1 = secret-like content found, exit 2 = usage error.
#
# Heuristic, fail-closed: flags assignments/keys that look like credentials.
# A generated skill should never embed secrets; any hit blocks the PR.

set -o pipefail

usage() { echo "Usage: $(basename "$0") <candidate-file> [skill-level]" >&2; }

main() {
    local candidate=${1:-}
    [ -n "$candidate" ] || { usage; exit 2; }
    [ -f "$candidate" ] || { echo "gate-no-secrets: file not found: $candidate" >&2; exit 2; }

    # key/value patterns that look like real credentials (value present).
    local pattern='(api[_-]?key|secret|password|passwd|token|bearer|private[_-]?key|aws_secret)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'

    local hits
    hits=$(grep -niE "$pattern" "$candidate" || true)
    if [ -n "$hits" ]; then
        echo "gate-no-secrets: secret-like content in candidate:" >&2
        printf '%s\n' "$hits" | head -5 >&2
        exit 1
    fi
    exit 0
}

main "$@"
