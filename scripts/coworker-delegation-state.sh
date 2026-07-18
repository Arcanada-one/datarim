#!/usr/bin/env bash
# Resolve the workspace coworker delegation policy (TUNE-0105).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/plugin-system.sh
. "$SCRIPT_DIR/lib/plugin-system.sh"

usage() {
    cat <<'EOF'
Usage: coworker-delegation-state.sh [--workspace <root>]

Prints exactly one effective state on success:
  enabled   coworker delegation policy applies
  disabled  native agent I/O is permitted for the workspace
EOF
}

resolve_workspace_root() {
    local explicit="${1:-}"
    if [ -n "$explicit" ]; then
        [ -d "$explicit" ] || {
            echo "coworker-delegation-state: workspace not found: $explicit" >&2
            return 2
        }
        echo "$explicit"
        return 0
    fi
    if [ -n "${DR_PLUGIN_WORKSPACE:-}" ]; then
        [ -d "$DR_PLUGIN_WORKSPACE" ] || {
            echo "coworker-delegation-state: workspace not found: $DR_PLUGIN_WORKSPACE" >&2
            return 2
        }
        echo "$DR_PLUGIN_WORKSPACE"
        return 0
    fi

    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/datarim" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "coworker-delegation-state: datarim/ not found in cwd or any parent" >&2
    return 2
}

main() {
    local workspace=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --workspace)
                shift
                [ $# -gt 0 ] || {
                    usage >&2
                    echo "enabled"
                    return 2
                }
                workspace="$1"
                ;;
            -h|--help)
                usage
                return 0
                ;;
            *)
                echo "coworker-delegation-state: unknown argument: $1" >&2
                usage >&2
                echo "enabled"
                return 2
                ;;
        esac
        shift
    done

    local root manifest root_status=0
    root="$(resolve_workspace_root "$workspace")" || root_status=$?
    if [ "$root_status" -ne 0 ]; then
        echo "enabled"
        return "$root_status"
    fi
    manifest="$root/datarim/enabled-plugins.md"

    if [ -e "$manifest" ] && { [ ! -f "$manifest" ] || [ ! -r "$manifest" ]; }; then
        echo "coworker-delegation-state: manifest is not a readable regular file: $manifest" >&2
        echo "enabled"
        return 2
    fi
    if [ -f "$manifest" ]; then
        local validation_status=0
        validate_disabled_defaults_section "$manifest" || validation_status=$?
        if [ "$validation_status" -gt 1 ]; then
            echo "coworker-delegation-state: failed to read manifest: $manifest" >&2
            echo "enabled"
            return 2
        fi
        if [ "$validation_status" -eq 1 ]; then
            echo "enabled"
            return 0
        fi
    fi

    if manifest_default_is_disabled "$manifest" coworker-delegation; then
        echo "disabled"
    else
        echo "enabled"
    fi
}

main "$@"
