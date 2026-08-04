#!/usr/bin/env bash
# tdd-enforcement-state.sh — stateless resolver for the workspace TDD
# enforcement policy (trusted default-on plugin `tdd-enforcement`).
#
# Prints exactly one word on stdout:
#   required — strict test-first sequencing applies (default and fail-safe)
#   optional — the operator disabled the default via `/dr-plugin disable
#              tdd-enforcement`; test timing is the implementer's choice, but
#              meaningful automated tests and every downstream quality gate
#              remain mandatory.
#
# State is re-read from the target workspace manifest
# (`datarim/enabled-plugins.md`) at every invocation — never cached. Missing,
# malformed, duplicate, indented, or substring policy content resolves to
# `required` so callers fail closed.
#
# Workspace resolution mirrors /dr-plugin: DR_PLUGIN_WORKSPACE, else walk up
# from cwd looking for a datarim/ marker. An unresolvable workspace prints
# `required` (fail closed) and exits 0.
#
# Exit codes: 0 success; 64 usage error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/plugin-system.sh
. "$SCRIPT_DIR/lib/plugin-system.sh"

usage() {
    cat <<'EOF'
tdd-enforcement-state.sh — print the workspace TDD enforcement policy

USAGE: tdd-enforcement-state.sh [--help]

Prints "required" (strict test-first sequencing; default and fail-safe) or
"optional" (operator opted out via the plugin manager). Exit 0 on success.
EOF
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "tdd-enforcement-state: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
fi

ws=""
if [ -n "${DR_PLUGIN_WORKSPACE:-}" ]; then
    ws="$DR_PLUGIN_WORKSPACE"
else
    dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/datarim" ]; then
            ws="$dir"
            break
        fi
        dir="$(dirname "$dir")"
    done
fi

if [ -z "$ws" ]; then
    # No workspace resolvable — fail closed to the stricter policy.
    echo "required"
    exit 0
fi

disabled_defaults_state "$ws/datarim/enabled-plugins.md" tdd-enforcement
