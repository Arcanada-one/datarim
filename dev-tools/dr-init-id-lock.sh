#!/usr/bin/env bash
# dr-init-id-lock.sh — atomic task-ID claim marker for the /dr-init race window.
#
# Closes the TOCTOU window between /dr-init's ID-collision probe and the first
# artifact write (tasks.md). `next-free-id.sh` is best-effort (max+1 + re-probe)
# but two sessions can still compute the same candidate and both pass the probe
# before either writes tasks.md. This helper makes the CLAIM itself atomic: a
# session mkdir's a per-ID marker directory; a second session's mkdir of the
# same marker fails, so exactly one session owns the ID during the write window.
#
# mkdir-based (macOS-portable — no flock dependency), matching the repo idiom
# used by append-init-task-qa.sh and the plugin system.
#
# Usage:
#   dr-init-id-lock.sh acquire <TASK-ID> <DATARIM_ROOT>
#   dr-init-id-lock.sh release <TASK-ID> <DATARIM_ROOT>
#   dr-init-id-lock.sh list    <PREFIX>  <DATARIM_ROOT>
#
# acquire: mkdir datarim/.locks/<TASK-ID>.init-lock (atomic claim).
#   exit 0 — claim acquired (or a stale marker older than DR_INIT_LOCK_TTL was
#            reclaimed). The caller now owns the ID for the write window.
#   exit 1 — a LIVE marker is held by another session (collision) — the caller
#            MUST bump to the next candidate and retry.
#   exit 2 — usage / validation error.
# release: rmdir the marker. Idempotent — exit 0 whether or not it existed.
# list:    print each held (marker present) TASK-ID for <PREFIX>, one per line.
#          Used by next-free-id.sh as a 4th claim surface so in-flight IDs are
#          visible to a concurrent allocator.
#
# Env: DR_INIT_LOCK_TTL — seconds after which a marker is stale and reclaimable
#      (default 900). A marker outlives its session only on a crash between
#      acquire and release; the TTL bounds how long that wedges the ID.
#
# Security: S1 strict mode, regex-validate all args, quote every expansion, no eval.

set -euo pipefail

TTL="${DR_INIT_LOCK_TTL:-900}"

usage() {
    sed -n '2,24p' "$0"
    exit 2
}

[[ $# -ge 1 ]] || usage
ACTION="$1"; shift

TASKID_RE='^[A-Z]{2,10}-[0-9]{4}$'
PREFIX_RE='^[A-Z]{2,10}$'

# Marker mtime in epoch seconds (portable: try GNU stat, then BSD stat).
_marker_mtime() {
    local d="$1"
    stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo 0
}

# 0 if the marker is stale (older than TTL), 1 otherwise.
_is_stale() {
    local d="$1" mtime now age
    mtime="$(_marker_mtime "$d")"
    now="$(date +%s)"
    age=$(( now - mtime ))
    [[ "$age" -ge "$TTL" ]]
}

case "$ACTION" in
    acquire)
        [[ $# -eq 2 ]] || usage
        TASK_ID="$1"; ROOT="$2"
        [[ "$TASK_ID" =~ $TASKID_RE ]] || { echo "ERROR: invalid task ID '$TASK_ID'" >&2; exit 2; }
        [[ -d "$ROOT/datarim" ]] || { echo "ERROR: no datarim/ under '$ROOT'" >&2; exit 2; }
        LOCK_DIR="$ROOT/datarim/.locks"
        mkdir -p "$LOCK_DIR"
        MARKER="$LOCK_DIR/${TASK_ID}.init-lock"
        if mkdir "$MARKER" 2>/dev/null; then
            printf 'pid=%s\nacquired=%s\n' "$$" "$(date +%s)" > "$MARKER/owner" 2>/dev/null || true
            echo "acquired: ${TASK_ID}"
            exit 0
        fi
        # mkdir failed — marker exists. Reclaim only if stale.
        if _is_stale "$MARKER"; then
            echo "WARNING: reclaiming stale init-lock for ${TASK_ID} (age >= ${TTL}s)" >&2
            rm -rf "$MARKER"
            if mkdir "$MARKER" 2>/dev/null; then
                printf 'pid=%s\nacquired=%s\n' "$$" "$(date +%s)" > "$MARKER/owner" 2>/dev/null || true
                echo "acquired: ${TASK_ID} (reclaimed stale)"
                exit 0
            fi
        fi
        echo "COLLISION: ${TASK_ID} is claimed by a live session — bump and retry" >&2
        exit 1
        ;;
    release)
        [[ $# -eq 2 ]] || usage
        TASK_ID="$1"; ROOT="$2"
        [[ "$TASK_ID" =~ $TASKID_RE ]] || { echo "ERROR: invalid task ID '$TASK_ID'" >&2; exit 2; }
        MARKER="$ROOT/datarim/.locks/${TASK_ID}.init-lock"
        rm -rf "$MARKER" 2>/dev/null || true
        echo "released: ${TASK_ID}"
        exit 0
        ;;
    list)
        [[ $# -eq 2 ]] || usage
        PREFIX="$1"; ROOT="$2"
        [[ "$PREFIX" =~ $PREFIX_RE ]] || { echo "ERROR: invalid prefix '$PREFIX'" >&2; exit 2; }
        LOCK_DIR="$ROOT/datarim/.locks"
        [[ -d "$LOCK_DIR" ]] || exit 0
        for m in "$LOCK_DIR/${PREFIX}-"[0-9][0-9][0-9][0-9].init-lock; do
            [[ -d "$m" ]] || continue
            base="$(basename "$m")"
            printf '%s\n' "${base%.init-lock}"
        done
        exit 0
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "ERROR: unknown action '$ACTION'" >&2
        usage
        ;;
esac
