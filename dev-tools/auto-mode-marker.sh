#!/usr/bin/env bash
# auto-mode-marker.sh — manage the autonomous-mode marker file
#
# The marker is written PER-TASK at <DIR>/datarim/.auto/<TASK-ID>.mode
# (collision-safe in a shared parallel workspace). The legacy single file
# <DIR>/datarim/.auto-mode-active is still READ as a fallback for one
# deprecation window (a hand-run /dr-auto that wrote the old file keeps
# working); writers always target the per-task path.
#
# Optional delegated-dispatch hardening: --dispatch-session binds the marker to
# one live tmux session (the load-bearing anti-forgery control — the agent-side
# contract also requires the marker to be untracked by git and within TTL).
# --nonce is accepted for forward compatibility but is NOT load-bearing on a
# single-operator private mesh (session-binding + gitignore + TTL already close
# the planted-marker threat). When either is supplied the marker is honoured
# only if it matches. A local hand-run supplies neither and is unaffected.
#
# Verbs:
#   reassert --root <DIR> --task-id <ID> [--space <NAME>] [--nonce <HEX>] [--dispatch-session <NAME>]
#     Idempotent. If the effective marker is absent, unparseable, holds a
#     different task_id, is older than 24 hours, or (when expected) fails the
#     nonce / dispatch-session binding, rewrite the per-task marker with the
#     given values. If a valid current marker already exists, no-op.
#     Exits 0 when the marker is valid for <ID> afterward; exits 2 on bad args.
#
#   subagent-active --root <DIR> --task-id <ID> --auto-signal <true|false> [--nonce <HEX>] [--dispatch-session <NAME>]
#     Models the relaxed subagent activation contract:
#       "active"    (exit 0) — marker valid for task_id (incl. nonce/session
#                              binding when expected) AND --auto-signal is true.
#       "non-auto"  (exit 0) — any other condition (fail-safe).
#     Deliberately does NOT read DATARIM_AUTO_MODE — proving the env-var is
#     not required for a spawned subagent carrying an explicit auto-signal.
#
#   resolve --root <DIR> --task-id <ID>
#     Print the effective marker path (per-task file if present, else legacy).
#     Single source of truth for consumers — no duplicated fallback logic.
#
# MARKER_RELPATH (legacy) and MARKER_DIR_RELPATH (per-task dir) are the two
# constants that locate markers inside the workspace root.
#
# Exit codes:
#   0  — operation succeeded (reassert: marker valid; subagent-active: decision
#        printed; resolve: path printed)
#   2  — usage / argument error (fired BEFORE any success output)

set -euo pipefail

MARKER_RELPATH="datarim/.auto-mode-active"

# ── Argument parsing ──────────────────────────────────────────────────────────

VERB="${1:-}"
shift || true

ROOT=""
TASK_ID=""
AUTO_SIGNAL=""
SPACE_NAME=""
NONCE=""
DISPATCH_SESSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root)       ROOT="$2";        shift 2 ;;
        --task-id)    TASK_ID="$2";     shift 2 ;;
        --auto-signal) AUTO_SIGNAL="$2"; shift 2 ;;
        --space)       SPACE_NAME="$2";  shift 2 ;;
        --nonce)      NONCE="$2";       shift 2 ;;
        --dispatch-session) DISPATCH_SESSION="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | head -40 | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: unknown flag: $1" >&2
            exit 2
            ;;
    esac
done

# ── Input validation ──────────────────────────────────────────────────────────

usage_error() {
    echo "ERROR: $*" >&2
    exit 2
}

if [ -z "$VERB" ]; then
    usage_error "verb required: reassert | subagent-active"
fi

if [ -z "$ROOT" ]; then
    usage_error "--root is required"
fi

if [ ! -d "$ROOT" ]; then
    usage_error "--root '${ROOT}' does not exist or is not a directory"
fi

if [ -z "$TASK_ID" ]; then
    usage_error "--task-id is required"
fi

if ! [[ "$TASK_ID" =~ ^[A-Z]{2,10}-[0-9]{4}$ ]]; then
    usage_error "--task-id must match ^[A-Z]{2,10}-[0-9]{4}\$, got: ${TASK_ID}"
fi

if [ -n "$SPACE_NAME" ] && ! [[ "$SPACE_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    usage_error "--space must be a safe lowercase slug, got: ${SPACE_NAME}"
fi

# Delegated-dispatch binding fields (optional). When present they harden the
# marker against a planted/replayed file: a delegated agent honours the marker
# only if BOTH the one-time nonce and the owning tmux session name match what
# the live dispatch generated. A local hand-run of /dr-auto passes neither and
# keeps working (no-nonce path).
if [ -n "$NONCE" ] && ! [[ "$NONCE" =~ ^[a-f0-9]{16,64}$ ]]; then
    usage_error "--nonce must be lowercase hex 16-64 chars, got: ${NONCE}"
fi

if [ -n "$DISPATCH_SESSION" ] && ! [[ "$DISPATCH_SESSION" =~ ^dr-[a-z0-9][a-z0-9-]*-[A-Z]{2,10}-[0-9]{4}$ ]]; then
    usage_error "--dispatch-session must match ^dr-<space>-<TASK-ID>\$, got: ${DISPATCH_SESSION}"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# Per-task marker path (collision-safe in a shared parallel workspace — each
# task owns its own file under datarim/.auto/, superseding the single-file
# legacy marker that could hold only one task_id). The legacy path is still
# READ as a fallback (see _resolve_marker_path) so a hand-run /dr-auto that
# wrote the old single file keeps working for one deprecation window.
MARKER_DIR_RELPATH="datarim/.auto"
PER_TASK_MARKER_PATH="${ROOT}/${MARKER_DIR_RELPATH}/${TASK_ID}.mode"
LEGACY_MARKER_PATH="${ROOT}/${MARKER_RELPATH}"

# _resolve_marker_path: echo the effective marker path for reads — the per-task
# file when it exists, else the legacy single file. Writers always target the
# per-task path.
_resolve_marker_path() {
    if [ -f "$PER_TASK_MARKER_PATH" ]; then
        printf '%s\n' "$PER_TASK_MARKER_PATH"
    else
        printf '%s\n' "$LEGACY_MARKER_PATH"
    fi
}

# MARKER_PATH is the WRITE target (always per-task). Reads go through
# _resolve_marker_path so the legacy file is honoured when the new one is absent.
MARKER_PATH="$PER_TASK_MARKER_PATH"

# _iso_now: emit UTC timestamp in ISO 8601 format
_iso_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true
}

# _write_marker: (re)write the per-task marker file with the given task_id.
# Optional nonce + dispatch_session lines are emitted only when supplied (the
# delegated-dispatch path); a local hand-run omits them.
_write_marker() {
    local task_id="$1"
    local ts marker_dir
    ts="$(_iso_now)"
    marker_dir="$(dirname "${MARKER_PATH}")"
    # Create the per-task marker directory with restrictive perms (0700) — it
    # holds an authorisation signal, not shareable data.
    mkdir -p "${marker_dir}"
    chmod 0700 "${marker_dir}" 2>/dev/null || true
    # Write via heredoc with quoted values (S1 compliance — no unquoted expansion)
    cat > "${MARKER_PATH}" <<YAML
task_id: ${task_id}
activated_at: ${ts}
activated_by: /dr-auto
mode: resume
space: ${SPACE_NAME}
nonce: ${NONCE}
dispatch_session: ${DISPATCH_SESSION}
YAML
    chmod 0600 "${MARKER_PATH}" 2>/dev/null || true
}

# _marker_is_valid: exit 0 if the effective marker (per-task file preferred,
# legacy single file as fallback) is present, parseable, holds the expected
# task_id, was created within the last 24 hours, and — when the caller supplied
# --nonce / --dispatch-session (the delegated path) — the marker's nonce and
# dispatch_session match. Any mismatch (planted/replayed/stale) → return 1
# (fail-safe → the caller treats the run as non-auto).
_marker_is_valid() {
    local expected_id="$1"
    local mpath
    mpath="$(_resolve_marker_path)"

    [ -f "${mpath}" ] || return 1

    # Check task_id field matches
    local file_id
    file_id=$(grep -m1 '^task_id:' "${mpath}" | sed 's/^task_id:[[:space:]]*//' 2>/dev/null) || return 1
    [ "${file_id}" = "${expected_id}" ] || return 1

    if [ -n "$SPACE_NAME" ]; then
        local file_space
        file_space=$(grep -m1 '^space:' "${mpath}" | sed 's/^space:[[:space:]]*//' 2>/dev/null) || return 1
        [ "$file_space" = "$SPACE_NAME" ] || return 1
    fi

    # Nonce binding: when the caller expects a nonce (delegated dispatch), the
    # file MUST carry the same nonce. A planted or replayed marker without the
    # live one-time nonce is rejected. Absent expectation → legacy/hand-run path,
    # nonce not checked.
    if [ -n "$NONCE" ]; then
        local file_nonce
        file_nonce=$(grep -m1 '^nonce:' "${mpath}" | sed 's/^nonce:[[:space:]]*//' 2>/dev/null) || return 1
        [ "${file_nonce}" = "${NONCE}" ] || return 1
    fi

    # Dispatch-session binding: when expected, the marker must name the same
    # owning tmux session — a marker written for a different session is stale.
    if [ -n "$DISPATCH_SESSION" ]; then
        local file_sess
        file_sess=$(grep -m1 '^dispatch_session:' "${mpath}" | sed 's/^dispatch_session:[[:space:]]*//' 2>/dev/null) || return 1
        [ "${file_sess}" = "${DISPATCH_SESSION}" ] || return 1
    fi

    # Check age: accept marker only if it was written within 24 hours (86400 s).
    # Probe GNU date first; fall back to BSD stat.
    local now_epoch mtime_epoch age
    now_epoch=$(date +%s 2>/dev/null) || now_epoch=0

    if [ "$now_epoch" -gt 0 ]; then
        # Try GNU stat -c then BSD stat -f
        if mtime_epoch=$(stat -c '%Y' "${mpath}" 2>/dev/null); then
            age=$(( now_epoch - mtime_epoch ))
        elif mtime_epoch=$(stat -f '%m' "${mpath}" 2>/dev/null); then
            age=$(( now_epoch - mtime_epoch ))
        else
            # Cannot determine age; treat as valid rather than discarding
            age=0
        fi
        [ "$age" -le 86400 ] || return 1
    fi

    return 0
}

# ── Verb: reassert ────────────────────────────────────────────────────────────

_verb_reassert() {
    if _marker_is_valid "${TASK_ID}"; then
        # Valid marker already in place — idempotent no-op
        exit 0
    fi

    # Marker absent, stale, or mismatched — (re)write it
    _write_marker "${TASK_ID}"

    # Defensive invariant: confirm the file now passes validation
    if ! _marker_is_valid "${TASK_ID}"; then
        echo "ERROR: internal invariant violated: marker was written but fails validation" >&2
        exit 2
    fi

    exit 0
}

# ── Verb: subagent-active ─────────────────────────────────────────────────────

_verb_subagent_active() {
    if [ -z "$AUTO_SIGNAL" ]; then
        usage_error "--auto-signal is required for subagent-active"
    fi

    if [ "$AUTO_SIGNAL" != "true" ] && [ "$AUTO_SIGNAL" != "false" ]; then
        usage_error "--auto-signal must be true|false, got: ${AUTO_SIGNAL}"
    fi

    # Relaxed activation contract (env-var NOT consulted — not inherited by Agent tool):
    #   active  iff  auto-signal=true  AND  marker valid for task_id
    #   non-auto in every other case (fail-safe)
    if [ "$AUTO_SIGNAL" = "true" ] && _marker_is_valid "${TASK_ID}"; then
        # Defensive invariant: both conditions confirmed above before printing
        echo "active"
    else
        echo "non-auto"
    fi

    exit 0
}

# ── Verb: resolve ─────────────────────────────────────────────────────────────

# resolve — print the effective marker path for the task (per-task file when it
# exists, else the legacy single file). Single source of truth for consumers so
# the per-task/legacy fallback logic is not duplicated across the 8+ call sites.
_verb_resolve() {
    _resolve_marker_path
    exit 0
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

case "$VERB" in
    reassert)
        _verb_reassert
        ;;
    subagent-active)
        _verb_subagent_active
        ;;
    resolve)
        _verb_resolve
        ;;
    *)
        usage_error "unknown verb '${VERB}': use reassert | subagent-active | resolve"
        ;;
esac
