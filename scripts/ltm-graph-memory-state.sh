#!/usr/bin/env bash
# Resolve the workspace LTM graph-memory policy (TUNE-0103).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/plugin-system.sh
. "$SCRIPT_DIR/lib/plugin-system.sh"

usage() {
    cat <<'EOF'
Usage: ltm-graph-memory-state.sh [--workspace <root>]

Prints exactly one effective state:
  enabled   a separately configured LTM adapter may be used
  disabled  no graph-memory operation is authorized
EOF
}

resolve_workspace_root() {
    local explicit="${1:-}"
    if [ -n "$explicit" ]; then
        [ -d "$explicit" ] || {
            echo "ltm-graph-memory-state: workspace not found: $explicit" >&2
            return 2
        }
        echo "$explicit"
        return 0
    fi
    if [ -n "${DR_PLUGIN_WORKSPACE:-}" ]; then
        [ -d "$DR_PLUGIN_WORKSPACE" ] || {
            echo "ltm-graph-memory-state: workspace not found: $DR_PLUGIN_WORKSPACE" >&2
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
    echo "ltm-graph-memory-state: datarim/ not found in cwd or any parent" >&2
    return 2
}

main() {
    local workspace=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --workspace)
                shift
                [ $# -gt 0 ] || { echo "disabled"; usage >&2; return 2; }
                workspace="$1"
                ;;
            -h|--help)
                usage
                return 0
                ;;
            *)
                echo "disabled"
                echo "ltm-graph-memory-state: unknown argument: $1" >&2
                usage >&2
                return 2
                ;;
        esac
        shift
    done

    local root manifest policy status=0
    root="$(resolve_workspace_root "$workspace")" || {
        status=$?
        echo "disabled"
        return "$status"
    }
    manifest="$root/datarim/enabled-plugins.md"

    if [ -e "$manifest" ] && { [ ! -f "$manifest" ] || [ ! -r "$manifest" ]; }; then
        echo "disabled"
        echo "ltm-graph-memory-state: manifest is not a readable regular file: $manifest" >&2
        return 2
    fi

    policy="$(manifest_builtin_metadata_status "$manifest" ltm-graph-memory)" || status=$?
    if [ "$status" -ne 0 ]; then
        echo "disabled"
        echo "ltm-graph-memory-state: failed to read manifest: $manifest" >&2
        return "$status"
    fi
    if [ "$policy" = "enabled" ]; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

main "$@"
