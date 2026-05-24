#!/usr/bin/env bash
# workspace.sh — shared workspace-root resolver для Datarim CLI subcommands.
# Walks up from $PWD looking for `datarim/` subdirectory; honours
# DATARIM_WORKSPACE_ROOT env var as authoritative override.
#
# Public API:
#   ws_resolve   — prints workspace root к stdout

[[ -n "${_WORKSPACE_LOADED:-}" ]] && return 0
_WORKSPACE_LOADED=1

ws_resolve() {
    if [[ -n "${DATARIM_WORKSPACE_ROOT:-}" ]]; then
        printf '%s' "$DATARIM_WORKSPACE_ROOT"
        return
    fi
    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        if [[ -d "$d/datarim" ]]; then
            printf '%s' "$d"
            return
        fi
        d="$(dirname "$d")"
    done
    printf '%s' "$HOME/arcanada"
}

# Defensive regex validation для user-supplied TASK-ID args.
# Caller MUST invoke this before using TARGET_ID в file path construction —
# path-traversal defense (TASK-ID containing `..`, slashes, or shell metachars).
# Matches canonical Datarim task ID shape: PREFIX-NNNN[A] (PREFIX uppercase + digits, 4-digit number, optional letter suffix).
ws_validate_task_id() {
    local id="${1-}"
    [[ "$id" =~ ^[A-Z][A-Z0-9]+-[0-9]+[A-Z]?$ ]]
}
