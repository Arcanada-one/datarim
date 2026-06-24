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

# Surface 1 — archive
if [[ -d "$ARCHIVE_DIR" ]]; then
    grep -roh --include="*.md" "${PREFIX}-[0-9]\{4\}" "$ARCHIVE_DIR" 2>/dev/null >> "$TMPFILE" || true
fi

# Surface 2 — tasks.md
if [[ -f "$TASKS_FILE" ]]; then
    grep -oh "${PREFIX}-[0-9]\{4\}" "$TASKS_FILE" 2>/dev/null >> "$TMPFILE" || true
fi

# Surface 3 — backlog.md
if [[ -f "$BACKLOG_FILE" ]]; then
    grep -oh "${PREFIX}-[0-9]\{4\}" "$BACKLOG_FILE" 2>/dev/null >> "$TMPFILE" || true
fi

# ── compute max ───────────────────────────────────────────────────────────────

MAX_NUM=0
while IFS= read -r id; do
    # Extract the numeric portion (4 digits after the dash)
    num="${id#*-}"
    num="${num#0*}"  # strip leading zeros for arithmetic — handle "0000" edge case
    num="${num:-0}"
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num > MAX_NUM )); then
        MAX_NUM="$num"
    fi
done < "$TMPFILE"

# ── candidate = max + 1 ───────────────────────────────────────────────────────

CANDIDATE=$(( MAX_NUM + 1 ))

# ── collision probe: is candidate already claimed? ───────────────────────────
# A parallel-session race may have written the candidate ID between our scan
# and now. Re-probe to confirm the candidate is still free; auto-bump if not.

is_claimed() {
    local id="$1"
    grep -rqh --include="*.md" "${id}" "$ARCHIVE_DIR" 2>/dev/null && return 0
    [[ -f "$TASKS_FILE" ]] && grep -qh "${id}" "$TASKS_FILE" 2>/dev/null && return 0
    [[ -f "$BACKLOG_FILE" ]] && grep -qh "${id}" "$BACKLOG_FILE" 2>/dev/null && return 0
    return 1
}

CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"

if is_claimed "$CANDIDATE_ID"; then
    # Auto-bump: find next free ID — no operator prompt (design §6)
    echo "WARNING: ID ${CANDIDATE_ID} already claimed (parallel-session race) — auto-bumping to next free ID" >&2
    while is_claimed "$CANDIDATE_ID"; do
        CANDIDATE=$(( CANDIDATE + 1 ))
        CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"
    done
fi

# ── emit the chosen ID ────────────────────────────────────────────────────────

printf '%s\n' "$CANDIDATE_ID"
