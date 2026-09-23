#!/usr/bin/env bash
# project-state.sh — lazy project-state resolution for dr-orchestrate scripts.
#
# Datarim is project-local: there is no $HOME fallback, and a script that needs
# per-project state must refuse when no project runtime is in scope. The refusal
# itself is correct. What is NOT correct is refusing at *expansion* time.
#
# `${DATARIM_RUNTIME:?...}` aborts the moment the parameter is expanded, even
# when the expanded value is immediately discarded. That turned "this script
# may need state" into "this script cannot run at all", and it aborted callers
# mid-way — session_close in tmux_manager.sh had already killed the tmux
# session before the expansion aborted it, so it neither retired the pane's
# state nor reported whether the kill succeeded.
#
# These helpers keep the refusal and move it to the point of use.
#
# Usage:
#   dr_orch_state_root            -> prints the state root, or fails (rc 1) with
#                                    a message on stderr when none is in scope.
#   dr_orch_state_root_or_empty   -> prints the state root, or prints nothing and
#                                    succeeds when none is in scope. For bounded
#                                    read-only paths where a missing state dir is
#                                    simply "no state to read" and callers already
#                                    treat an absent file as empty.
#
# Neither helper ever resolves under $HOME. With no runtime and no explicit
# override, there is no path — not a home-shaped one.

dr_orch_state_root() {
    local resolved="${DR_ORCH_STATE_DIR:-${STATE_DIR:-}}"
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi
    if [ -n "${DATARIM_RUNTIME:-}" ]; then
        printf '%s/state/orchestrate\n' "$DATARIM_RUNTIME"
        return 0
    fi
    echo 'dr-orchestrate: project runtime required for per-project state' >&2
    return 1
}

dr_orch_state_root_or_empty() {
    local resolved="${DR_ORCH_STATE_DIR:-${STATE_DIR:-}}"
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi
    if [ -n "${DATARIM_RUNTIME:-}" ]; then
        printf '%s/state/orchestrate\n' "$DATARIM_RUNTIME"
        return 0
    fi
    printf '%s\n' ''
    return 0
}
