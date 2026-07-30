#!/usr/bin/env bash
# next-free-id.sh — Deterministic task-ID selection with auto-bump on collision.
#
# Usage:
#   next-free-id.sh <PREFIX> <DATARIM_ROOT>
#
# Returns (stdout):  the next free ID in the form PREFIX-NNNN
# On collision:      auto-bumps to next free, emits a warning to stderr
# Exit codes:        0 = OK; 1 = usage/validation error
#
# The canonical formula:
#   candidate = max(claimed across documentation/archive ∪ datarim/tasks.md ∪ datarim/backlog.md) + 1
# If candidate is already claimed (parallel-session race), auto-bump to the next free ID.
#
# Security: S1 strict mode, regex-validate prefix arg, quote all expansions, no eval.

set -euo pipefail

# ── reservation store (TUNE-0285 race-window hardening) ──────────────────────
#
# The three claim surfaces above only become visible once a session has written
# an artifact. Between ID selection and that first write there is a workspace-
# shared TOCTOU window (reflection-TUNE-0280 § 1): two parallel `/dr-init`
# sessions can both select the same free ID. To close it we ATOMICALLY reserve
# the selected ID via a `mkdir` mutex under `datarim/.id-reservations/{ID}`
# BEFORE this helper returns, so the reservation spans the whole
# helper → agent → first-write sequence. `mkdir` is atomic on every POSIX
# filesystem (incl. macOS APFS): of two concurrent sessions computing the same
# candidate, exactly one `mkdir` wins; the loser bumps.
#
# Reversibility (a hard requirement of the task):
#   1. TTL self-expiry — a marker older than DATARIM_ID_RESERVATION_TTL seconds
#      (default 1800 / 30 min) is STALE and reclaimable, so a crashed session
#      never permanently burns an ID.
#   2. Explicit release — `next-free-id.sh --release <ID> <DATARIM_ROOT>`.
#   3. Manual — `rm -rf datarim/.id-reservations/<ID>`.
#   4. Idempotent GC of stale markers runs at the start of every selection.
# The marker is advisory: once the real artifact claims the ID on a canonical
# surface, a lingering marker is harmless (the surface already blocks reuse).

RESERVATION_SUBDIR="datarim/.id-reservations"

# --release mode: `next-free-id.sh --release <ID> <DATARIM_ROOT>`
if [[ "${1:-}" == "--release" ]]; then
    if [[ $# -lt 3 ]]; then
        echo "Usage: next-free-id.sh --release <ID> <DATARIM_ROOT>" >&2
        exit 1
    fi
    REL_ID="$2"
    REL_ROOT="$3"
    # Strict-validate the ID before any filesystem op (Security S1 — no traversal)
    if ! [[ "$REL_ID" =~ ^[A-Z]{2,10}-[0-9]{4,}$ ]]; then
        echo "ERROR: invalid ID '${REL_ID}' for --release — expected PREFIX-NNNN" >&2
        exit 1
    fi
    if [[ ! -d "$REL_ROOT" ]]; then
        echo "ERROR: DATARIM_ROOT '${REL_ROOT}' does not exist or is not a directory" >&2
        exit 1
    fi
    rm -rf "${REL_ROOT:?}/${RESERVATION_SUBDIR}/${REL_ID:?}" 2>/dev/null || true
    exit 0
fi

# ── argument validation ──────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
    echo "Usage: next-free-id.sh <PREFIX> <DATARIM_ROOT>" >&2
    exit 1
fi

PREFIX="$1"
DATARIM_ROOT="$2"

# Regex-validate prefix: 2–10 uppercase letters only (Security S1)
if ! [[ "$PREFIX" =~ ^[A-Z]{2,10}$ ]]; then
    echo "ERROR: invalid prefix '${PREFIX}' — must be 2–10 uppercase letters" >&2
    exit 1
fi

if [[ ! -d "$DATARIM_ROOT" ]]; then
    echo "ERROR: DATARIM_ROOT '${DATARIM_ROOT}' does not exist or is not a directory" >&2
    exit 1
fi

# ── reservation config + helpers (TUNE-0285) ─────────────────────────────────

RESERVE_DIR="${DATARIM_ROOT}/${RESERVATION_SUBDIR}"

# TTL after which an untouched reservation is considered stale (crashed session)
RESERVATION_TTL="${DATARIM_ID_RESERVATION_TTL:-1800}"
if ! [[ "$RESERVATION_TTL" =~ ^[0-9]+$ ]]; then
    RESERVATION_TTL=1800
fi

# Age of a reservation marker in seconds. A missing/unreadable epoch is treated
# as age 0 (fresh) — this protects the narrow window where a concurrent winner
# has mkdir'd the marker but not yet written its epoch; such a marker is never
# auto-stolen (it clears via TTL once its epoch lands, or via --release).
_reservation_age() {
    local marker="$1" now epoch
    now="$(date +%s)"
    epoch="$(cat "${marker}/epoch" 2>/dev/null)" || epoch=""
    if ! [[ "$epoch" =~ ^[0-9]+$ ]]; then
        echo 0
        return 0
    fi
    echo $(( now - epoch ))
}

# A reservation is "fresh" (counts as claimed) when its marker exists and its
# age is within the TTL.
_reservation_is_fresh() {
    local id="$1"
    local marker="${RESERVE_DIR}/${id}"
    [[ -d "$marker" ]] || return 1
    (( $(_reservation_age "$marker") <= RESERVATION_TTL ))
}

# Idempotent sweep: reclaim (rmdir) any reservation older than the TTL.
_reservation_gc() {
    [[ -d "$RESERVE_DIR" ]] || return 0
    local marker
    for marker in "$RESERVE_DIR"/*/; do
        [[ -d "$marker" ]] || continue
        if (( $(_reservation_age "$marker") > RESERVATION_TTL )); then
            rm -rf "$marker" 2>/dev/null || true
        fi
    done
}

# Atomically reserve an ID. Returns 0 on success (marker created + stamped),
# 1 when a FRESH reservation already holds it (lost the race → caller bumps).
# A stale marker is reclaimed and re-taken.
_reservation_try() {
    local id="$1"
    local marker="${RESERVE_DIR}/${id}"
    if mkdir "$marker" 2>/dev/null; then
        date +%s > "${marker}/epoch" 2>/dev/null || true
        echo "$$" > "${marker}/pid" 2>/dev/null || true
        return 0
    fi
    # Marker already exists — reclaim only if stale, else we lost the race.
    if ! _reservation_is_fresh "$id"; then
        rm -rf "$marker" 2>/dev/null || true
        if mkdir "$marker" 2>/dev/null; then
            date +%s > "${marker}/epoch" 2>/dev/null || true
            echo "$$" > "${marker}/pid" 2>/dev/null || true
            return 0
        fi
    fi
    return 1
}

# ── collect all claimed IDs for this prefix ──────────────────────────────────

# Surface 1: documentation/archive (any subdirectory)
# Surface 2: datarim/tasks.md
# Surface 3: datarim/backlog.md
#
# Pattern: PREFIX-NNNN at a word boundary — extract the numeric part

TASKS_FILE="${DATARIM_ROOT}/datarim/tasks.md"
BACKLOG_FILE="${DATARIM_ROOT}/datarim/backlog.md"
ARCHIVE_DIR="${DATARIM_ROOT}/documentation/archive"

# Gather all matching IDs from all three surfaces into a temp file
TMPFILE="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '${TMPFILE}'" EXIT

# Surface 1 — archive. The canonical claim for an archived task is its
# `archive-{ID}.md` FILENAME, not arbitrary ID mentions in document bodies.
# A prior content-grep (`grep -roh ... "$ARCHIVE_DIR"`) scooped up illustrative
# IDs cited inside archive prose (e.g. fixture IDs like PREFIX-9999 documented in
# a test write-up), inflating the max and excluding exactly the "test fixtures"
# the canon says to ignore. Extract from filenames instead.
if [[ -d "$ARCHIVE_DIR" ]]; then
    find "$ARCHIVE_DIR" -type f -name "archive-${PREFIX}-[0-9][0-9][0-9][0-9].md" 2>/dev/null \
        | grep -oh "${PREFIX}-[0-9]\{4\}" 2>/dev/null >> "$TMPFILE" || true
fi

# Surface 2 — tasks.md
if [[ -f "$TASKS_FILE" ]]; then
    grep -oh "${PREFIX}-[0-9]\{4\}" "$TASKS_FILE" 2>/dev/null >> "$TMPFILE" || true
fi

# Surface 3 — backlog.md
if [[ -f "$BACKLOG_FILE" ]]; then
    grep -oh "${PREFIX}-[0-9]\{4\}" "$BACKLOG_FILE" 2>/dev/null >> "$TMPFILE" || true
fi

# Surface 4 — in-flight init-lock markers (datarim/.locks/<ID>.init-lock). A
# concurrent /dr-init that has claimed an ID but not yet written tasks.md is
# invisible to surfaces 1–3; the marker directory makes that claim visible so
# max+1 skips it. Any present marker is treated as claimed (conservative — a
# stale marker only inflates max slightly and is never reused). See
# dr-init-id-lock.sh.
LOCK_DIR="${DATARIM_ROOT}/datarim/.locks"
if [[ -d "$LOCK_DIR" ]]; then
    for _m in "$LOCK_DIR/${PREFIX}-"[0-9][0-9][0-9][0-9].init-lock; do
        [[ -d "$_m" ]] || continue
        _b="$(basename "$_m")"; _b="${_b%.init-lock}"
        printf '%s\n' "$_b" >> "$TMPFILE"
    done
fi

# ── compute max ───────────────────────────────────────────────────────────────

MAX_NUM=0
while IFS= read -r id; do
    # Extract the numeric portion (4 digits after the dash)
    num="${id#*-}"
    # Validate as 1+ digits, then force base-10 in arithmetic. A bare `(( 058 ))`
    # is parsed as octal, so any zero-padded digit >= 8 (e.g. 0058, 0079, 0090)
    # would error and be silently skipped — corrupting the max. `10#` pins base-10
    # for any number of leading zeros, including the all-zero "0000" edge case.
    if [[ "$num" =~ ^[0-9]+$ ]] && (( 10#$num > MAX_NUM )); then
        MAX_NUM=$(( 10#$num ))
    fi
done < "$TMPFILE"

# ── candidate = max + 1 ───────────────────────────────────────────────────────

CANDIDATE=$(( MAX_NUM + 1 ))

# ── collision probe: is candidate already claimed? ───────────────────────────
# A parallel-session race may have written the candidate ID between our scan
# and now. Re-probe to confirm the candidate is still free; auto-bump if not.

is_claimed() {
    local id="$1"
    # Archive claim = an `archive-{id}.md` file exists (filename surface), not a
    # prose mention of the id inside some other archive document. Mirror Surface 1.
    find "$ARCHIVE_DIR" -type f -name "archive-${id}.md" 2>/dev/null | grep -q . && return 0
    [[ -f "$TASKS_FILE" ]] && grep -qh "${id}" "$TASKS_FILE" 2>/dev/null && return 0
    [[ -f "$BACKLOG_FILE" ]] && grep -qh "${id}" "$BACKLOG_FILE" 2>/dev/null && return 0
    # Surface 4 — an in-flight init-lock marker is an atomic claim by a
    # concurrent session that has not yet written tasks.md.
    [[ -d "${DATARIM_ROOT}/datarim/.locks/${id}.init-lock" ]] && return 0
    # Surface 4 (TUNE-0285) — a FRESH reservation marker held by a parallel
    # session in the read→write window counts as claimed.
    _reservation_is_fresh "$id" && return 0
    return 1
}

# ── atomic select-and-reserve loop (TUNE-0285) ───────────────────────────────
# GC stale reservations first, then walk candidates: skip any that is claimed
# on a real surface OR by a fresh reservation, and atomically reserve the first
# free one. The mkdir mutex inside _reservation_try is the true guarantee — a
# candidate that slips past is_claimed but loses the concurrent mkdir causes a
# bump, so two simultaneous sessions can never emit the same ID.

mkdir -p "$RESERVE_DIR" 2>/dev/null || true
_reservation_gc

CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"
warned=0
while : ; do
    if is_claimed "$CANDIDATE_ID"; then
        if (( warned == 0 )); then
            echo "WARNING: ID ${CANDIDATE_ID} already claimed (parallel-session race) — auto-bumping to next free ID" >&2
            warned=1
        fi
        CANDIDATE=$(( CANDIDATE + 1 ))
        CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"
        continue
    fi
    if _reservation_try "$CANDIDATE_ID"; then
        break
    fi
    # Lost the atomic mkdir race to a parallel session — bump.
    if (( warned == 0 )); then
        echo "WARNING: ID ${CANDIDATE_ID} reserved by a parallel session — auto-bumping to next free ID" >&2
        warned=1
    fi
    CANDIDATE=$(( CANDIDATE + 1 ))
    CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"
done

# ── emit the chosen ID ────────────────────────────────────────────────────────

printf '%s\n' "$CANDIDATE_ID"
