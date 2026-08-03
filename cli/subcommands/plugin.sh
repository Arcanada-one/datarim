#!/usr/bin/env bash
# TUNE-0268 Phase 5 — thin wrapper over the canonical dr-plugin controller.
# This file never edits plugin state itself.

set -u

CLI_DIR_PLUGIN_SUB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR_PLUGIN_SUB="$CLI_DIR_PLUGIN_SUB/lib"

# shellcheck source=cli/lib/output.sh
. "$LIB_DIR_PLUGIN_SUB/output.sh"
# shellcheck source=cli/lib/exit-codes.sh
. "$LIB_DIR_PLUGIN_SUB/exit-codes.sh"
DR_PLUGIN_SCRIPT="${CLI_DIR_PLUGIN_SUB%/cli}/scripts/dr-plugin.sh"

_plugin_invoke() {
    [ -x "$DR_PLUGIN_SCRIPT" ] || output_emit_error "$(exit_code_of DEPENDENCY_MISSING)" DEPENDENCY_MISSING \
        "canonical plugin controller is unavailable"
    "$DR_PLUGIN_SCRIPT" "$@"
}

plugin_subcommand() {
    local op="${1:-}"; shift || true
    case "$op" in
        list)
            [ $# -eq 0 ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim plugin list"
            _plugin_invoke list
            ;;
        enable|disable)
            [ $# -eq 1 ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim plugin $op <target>"
            _plugin_invoke "$op" "$1"
            ;;
        sync)
            [ $# -eq 0 ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim plugin sync"
            _plugin_invoke sync
            ;;
        doctor)
            case $# in 0) _plugin_invoke doctor ;; 1) [ "$1" = "--fix" ] || output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim plugin doctor [--fix]"; _plugin_invoke doctor --fix ;; *) output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim plugin doctor [--fix]" ;; esac
            ;;
        *) output_emit_error "$(exit_code_of MISUSE)" MISUSE "usage: datarim plugin list|enable|disable|sync|doctor" ;;
    esac
}
