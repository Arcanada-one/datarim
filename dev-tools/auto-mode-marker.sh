#!/usr/bin/env bash
# auto-mode-marker.sh — manage the autonomous-mode marker file
#
# Verbs:
#   reassert --root <DIR> --task-id <ID> [--space <NAME>]
#     Idempotent. If <DIR>/datarim/.auto-mode-active is absent, unparseable,
#     holds a different task_id, or is older than 24 hours, rewrite it with
#     the given task_id and optional space binding. If a valid current marker
#     already exists, no-op.
#     Exits 0 when the marker is valid for <ID> afterward; exits 2 on bad args.
#
#   subagent-active --root <DIR> --task-id <ID> --auto-signal <true|false>
#     Models the relaxed subagent activation contract:
#       "active"    (exit 0) — marker exists, parses, task_id matches AND
#                              --auto-signal is true.
#       "non-auto"  (exit 0) — any other condition (fail-safe).
#     Deliberately does NOT read DATARIM_AUTO_MODE — proving the env-var is
#     not required for a spawned subagent carrying an explicit auto-signal.
#
# MARKER_RELPATH is the single constant that locates the marker inside the
# workspace root. A future rename changes only this one line.
#
# Exit codes:
#   0  — operation succeeded (reassert: marker valid; subagent-active: decision printed)
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

while [ $# -gt 0 ]; do
    case "$1" in
        --root)       ROOT="$2";        shift 2 ;;
        --task-id)    TASK_ID="$2";     shift 2 ;;
        --auto-signal) AUTO_SIGNAL="$2"; shift 2 ;;
        --space)       SPACE_NAME="$2";  shift 2 ;;
        -h|--help)
            grep '^#' "$0" | head -30 | sed 's/^# \?//'
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

# ── Helpers ───────────────────────────────────────────────────────────────────

MARKER_PATH="${ROOT}/${MARKER_RELPATH}"

# _iso_now: emit UTC timestamp in ISO 8601 format
_iso_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true
}

# _write_marker: (re)write the marker file with the given task_id
_write_marker() {
    local task_id="$1"
    local ts
    ts="$(_iso_now)"
    # Write via heredoc with quoted values (S1 compliance — no unquoted expansion)
    cat > "${MARKER_PATH}" <<YAML
task_id: ${task_id}
activated_at: ${ts}
activated_by: /dr-auto
mode: resume
space: ${SPACE_NAME}
YAML
}

# _marker_is_valid: exit 0 if the marker at MARKER_PATH is present, parseable,
# holds the expected task_id, and was created within the last 24 hours.
_marker_is_valid() {
    local expected_id="$1"

    [ -f "${MARKER_PATH}" ] || return 1

    # Check task_id field matches
    local file_id
    file_id=$(grep -m1 '^task_id:' "${MARKER_PATH}" | sed 's/^task_id:[[:space:]]*//' 2>/dev/null) || return 1
    [ "${file_id}" = "${expected_id}" ] || return 1

    if [ -n "$SPACE_NAME" ]; then
        local file_space
        file_space=$(grep -m1 '^space:' "${MARKER_PATH}" | sed 's/^space:[[:space:]]*//' 2>/dev/null) || return 1
        [ "$file_space" = "$SPACE_NAME" ] || return 1
    fi

    # Check age: accept marker only if it was written within 24 hours (86400 s).
    # Probe GNU date first; fall back to BSD stat.
    local now_epoch mtime_epoch age
    now_epoch=$(date +%s 2>/dev/null) || now_epoch=0

    if [ "$now_epoch" -gt 0 ]; then
        # Try GNU stat -c then BSD stat -f
        if mtime_epoch=$(stat -c '%Y' "${MARKER_PATH}" 2>/dev/null); then
            age=$(( now_epoch - mtime_epoch ))
        elif mtime_epoch=$(stat -f '%m' "${MARKER_PATH}" 2>/dev/null); then
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

# ── Dispatch ──────────────────────────────────────────────────────────────────

case "$VERB" in
    reassert)
        _verb_reassert
        ;;
    subagent-active)
        _verb_subagent_active
        ;;
    *)
        usage_error "unknown verb '${VERB}': use reassert | subagent-active"
        ;;
esac
