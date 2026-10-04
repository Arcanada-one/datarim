#!/usr/bin/env bash
# TUNE-0268 Phase 5 compatibility surface.
#
# The historic generic config-write design is superseded: current settings have
# separate canonical owners and some contain secrets. This command therefore
# exposes only non-secret derived state and refuses every mutation.

set -u

CLI_DIR_CONFIG_SUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR_CONFIG_SUB="$CLI_DIR_CONFIG_SUB/lib"

# shellcheck source=cli/lib/workspace.sh
. "$LIB_DIR_CONFIG_SUB/workspace.sh"
# shellcheck source=cli/lib/output.sh
. "$LIB_DIR_CONFIG_SUB/output.sh"

_config_validate_key() {
    local key="${1:-}"
    case "$key" in [a-z][a-z0-9_]*) ;; *) return 1 ;; esac
    case "$key" in *[!a-z0-9_]*) return 1 ;; esac
}

_config_emit_value() {
    local key="$1" value_json="$2" plain="$3" json="$4"
    if [ "$json" -eq 1 ]; then
        export DATARIM_CLI_CMD="config get" OUTPUT_MODE=json
        output_emit_json "$(jq -cn --arg key "$key" --argjson value "$value_json" '{key:$key,value:$value}')"
    else
        printf '%s\n' "$plain"
    fi
}

_config_get() {
    local key="" json=0 arg root version manifest status
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --json) json=1; shift ;;
            --config) output_emit_error "$(exit_code_of AAL_LOCKED_KEY)" AAL_LOCKED_KEY \
                "generic config files are superseded; --config is not supported" ;;
            -*) output_emit_error "$(exit_code_of MISUSE)" MISUSE "config get: unknown flag $arg" ;;
            *) [ -z "$key" ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "config get: extra argument $arg"
               key="$arg"; shift ;;
        esac
    done
    _config_validate_key "$key" || output_emit_error "$(exit_code_of MISUSE)" MISUSE "config get: safe key required"
    root="${DATARIM_ROOT:-${CLI_DIR_CONFIG_SUB%/cli}}"
    case "$key" in
        framework_version)
            [ -f "$root/VERSION" ] || output_emit_error "$(exit_code_of NOT_FOUND)" NOT_FOUND "framework VERSION is unavailable"
            version="$(tr -d '\r\n' < "$root/VERSION")"
            _config_emit_value "$key" "$(jq -Rn --arg value "$version" '$value')" "$version" "$json"
            ;;
        plugin_manifest_status)
            manifest="$(ws_resolve)/datarim/enabled-plugins.md"
            if [ -f "$manifest" ]; then status=present; else status=absent; fi
            _config_emit_value "$key" "$(jq -Rn --arg value "$status" '$value')" "$status" "$json"
            ;;
        *)
            output_emit_error "$(exit_code_of AAL_LOCKED_KEY)" AAL_LOCKED_KEY \
                "config key '$key' is managed by its canonical owner and is not exposed through this CLI"
            ;;
    esac
}

_config_set() {
    local key="${1:-}" value="${2:-}"
    _config_validate_key "$key" || output_emit_error "$(exit_code_of MISUSE)" MISUSE "config set: safe key required"
    [ -n "$value" ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "config set: value required"
    output_emit_error "$(exit_code_of AAL_LOCKED_KEY)" AAL_LOCKED_KEY \
        "generic config mutation is superseded; use the canonical owner for '$key'"
}

config_subcommand() {
    local op="${1:-}"; shift || true
    case "$op" in
        get) _config_get "$@" ;;
        set) _config_set "$@" ;;
        *) output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim config get|set ..." ;;
    esac
}
