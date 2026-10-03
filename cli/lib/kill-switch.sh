#!/usr/bin/env bash
# cli/lib/kill-switch.sh — HALT sentinel check.
# Source: TUNE-0271 plan § Detailed Design 4.3.
#
# Contract:
#   - Sentinel path: ~/.config/datarim-cli/HALT (any content; presence = signal).
#   - Check runs as the FIRST line of every subcommand (even read-only).
#   - On presence → exit 17 with stderr message; no side effects.
#   - On absence → return 0 silently.
#
# Override for tests: DATARIM_CLI_HALT_PATH=<alt-path>.

set -u

CLI_KILL_SWITCH_EXIT=17

cli_kill_switch_path() {
    printf '%s' "${DATARIM_CLI_HALT_PATH:-${HOME}/.config/datarim-cli/HALT}"
}

check_kill_switch() {
    local path
    path="$(cli_kill_switch_path)"
    if [ -e "$path" ]; then
        printf '[kill-switch] datarim CLI halted by %s — remove file to resume\n' "$path" >&2
        return $CLI_KILL_SWITCH_EXIT
    fi
    return 0
}

# Helpers for `datarim audit halt|resume` subcommand.
kill_switch_engage() {
    local path
    path="$(cli_kill_switch_path)"
    mkdir -p "$(dirname "$path")"
    : > "$path"
    printf '[kill-switch] engaged: %s\n' "$path"
}

kill_switch_disengage() {
    local path
    path="$(cli_kill_switch_path)"
    if [ -e "$path" ]; then
        rm -f "$path"
        printf '[kill-switch] disengaged: %s removed\n' "$path"
    else
        printf '[kill-switch] already disengaged: %s absent\n' "$path"
    fi
}
