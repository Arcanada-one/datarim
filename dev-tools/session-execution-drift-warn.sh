#!/usr/bin/env bash
# session-execution-drift-warn.sh — SessionStart ADVISORY drift-warning
# (TUNE-0507, wiring the "Phase 1 ... NOT yet wired" note on the
# execution-hosts.yml header; TUNE-0472 Phase 2).
#
# For the current workspace's governing space, compares canon
# `spaces/<space>/space.yml § execution` against the machine-local routing
# cache `~/.claude/local/config/execution-hosts.yml` and prints ONE advisory
# line when there is drift, staleness, or a missing binding/cache. ADVISORY
# ONLY — it never blocks the session and ALWAYS exits 0.
#
# Space- and stack-agnostic: the governing space is derived from
# spaces/registry.yml (the `role: root-managing` entry) via the shared
# resolver lib — never hardcoded.
#
# SessionStart registration (machine-local — NOT committed; each machine wires
# its own ~/.claude/settings.json):
#
#   {
#     "hooks": {
#       "SessionStart": [
#         { "hooks": [
#             { "type": "command",
#               "command": "$HOME/.local/bin/session-execution-drift-warn" } ] }
#       ]
#     }
#   }
#
# install.sh symlinks ~/.local/bin/session-execution-drift-warn -> this file
# (setup_session_drift_warn_symlink), mirroring the other guard symlinks.
#
# NOT `set -e`: an advisory must never abort a session start. Failures degrade
# to silence.
# shellcheck shell=bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SELF_DIR/lib/execution-host.sh"
DRIFT="$SELF_DIR/check-execution-host-drift.sh"
DEFAULT_MAP="${HOME}/.claude/local/config/execution-hosts.yml"
MAP_PATH="${DATARIM_EXEC_HOSTS_MAP:-$DEFAULT_MAP}"

# --- resolve cwd: SessionStart stdin JSON (.cwd) if present, else $PWD -------
cwd=""
if [ ! -t 0 ]; then
    input="$(cat 2>/dev/null || true)"
    if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
        cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
    fi
fi
[ -n "$cwd" ] || cwd="$PWD"

# --- source resolver lib (best-effort) --------------------------------------
if [ -f "$LIB" ]; then
    # shellcheck source=/dev/null
    source "$LIB" 2>/dev/null || true
fi

# --- resolve workspace root -------------------------------------------------
root=""
if declare -F eh_resolve_workspace_root >/dev/null 2>&1; then
    root="$(eh_resolve_workspace_root "$cwd" 2>/dev/null || true)"
fi
[ -n "$root" ] || exit 0   # not a datarim workspace -> nothing to advise

# --- resolve governing space + canon path (space-agnostic) ------------------
canon="" space=""
if declare -F eh_canon_space_for_root >/dev/null 2>&1; then
    pair="$(eh_canon_space_for_root "$root" 2>/dev/null || true)"
    if [ -n "$pair" ]; then
        IFS=$'\t' read -r canon space <<< "$pair"
    fi
fi
# No canon execution mandate for this workspace -> nothing to advise.
[ -n "$canon" ] && [ -n "$space" ] || exit 0

warn() { printf '⚠ [execution-host] %s\n' "$1"; }

# --- cache absent: advise regeneration --------------------------------------
if [ ! -f "$MAP_PATH" ]; then
    warn "no machine-local routing cache ($MAP_PATH) for space '$space' — /dr-* host-routing falls back to canon. Regenerate: check-execution-host-drift.sh --fix --canon '$canon' --map '$MAP_PATH' --space '$space'"
    exit 0
fi

# --- run the canon<->cache report (best-effort) -----------------------------
if [ -f "$DRIFT" ]; then
    report="$(bash "$DRIFT" --report --canon "$canon" --map "$MAP_PATH" --space "$space" 2>/dev/null || true)"
    # Header line: "execution-host drift report (space=X): N finding(s)"
    n="$(printf '%s' "$report" | sed -n 's/.*: \([0-9][0-9]*\) finding.*/\1/p' | head -n1)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -gt 0 ]; then
        warn "canon<->cache drift/staleness for space '$space' ($n finding(s)) — canon wins. Reconcile: check-execution-host-drift.sh --fix --canon '$canon' --map '$MAP_PATH' --space '$space'"
    fi
fi
exit 0
