#!/usr/bin/env bash
# prune-backlog-terminal.sh — data-loss-safe backlog terminal-task pruner
#
# Classifies every entry in datarim/backlog.md and removes only entries whose
# status is terminal AND whose corresponding archive doc exists. Entries that
# are terminal but lack an archive doc are PRESERVED and surfaced (never silently
# dropped) — the "data-loss-safe" contract that prevents destroying the last
# record of an un-archived task.
#
# The canonical backlog holds only pending / blocked-pending / cancelled (transient).
# Terminal statuses (done / archived / completed) and terminal-cancelled entries
# WITH a corresponding documentation/archive/*/archive-{ID}.md are prunable.
#
# Single responsibility: this script MUST NOT be merged with datarim-doctor.sh
# (see CLAUDE.md § Validation Discipline — orthogonal concerns get orthogonal tools).
# Both /dr-doctor and /dr-dream invoke this script directly.
#
# Usage:
#   prune-backlog-terminal.sh --root <KB_root> --check   (dry-run; exit 0)
#   prune-backlog-terminal.sh --root <KB_root> --fix     (rewrite backlog.md)
#
# Exit codes:
#   0  clean / operation succeeded
#   1  usage error (no mode flag)
#   2  tool error (atomic write failed)
#
# Security (S1): set -euo pipefail; anchored ID regex; no eval; atomic mv;
# passes shellcheck -S warning. Glob-guard for archive-doc presence: compgen
# constrained to resolved subpath; no path traversal.

set -euo pipefail

# ---------- constants --------------------------------------------------------

# Terminal statuses whose presence in backlog.md indicates a stale entry.
# Transient "cancelled" (no archive doc) is kept; only terminal-cancelled
# (where an archive/cancelled/archive-{ID}.md exists) is prunable.
_TERMINAL_RE='^(done|archived|completed|cancelled)$'

# Anchored task-ID regex (same as task-id-gate.sh / pre-archive-check.sh).
_ID_RE='^[A-Z]{2,10}-[0-9]{4}$'

# ---------- helpers ----------------------------------------------------------

_usage() {
    printf 'Usage: %s --root <KB_root> (--check | --fix)\n' "$(basename "$0")" >&2
    exit 1
}

# Extract the task ID from a canonical backlog one-liner:
#   "- TUNE-0001 · done · …"  → "TUNE-0001"
_extract_id() {  # $1=line → stdout id or empty
    local id
    id="$(printf '%s' "$1" | sed -n 's/^- \([A-Z][A-Z0-9]*-[0-9][0-9]*\) .*/\1/p')"
    printf '%s' "$id"
}

# Extract the status field from a canonical one-liner (second · token):
#   "- TUNE-0001 · done · …" → "done"
_extract_status() {  # $1=line → stdout status or empty
    printf '%s' "$1" | awk -F' · ' 'NF>=2{print $2}'
}

# Check whether an archive doc exists for the given ID under any area subdir.
# Uses a glob; treats the glob as present if at least one file is found.
_archive_exists() {  # $1=archive_root $2=id → returns 0 (exists) or 1 (absent)
    local archive_root="$1" id="$2"
    # Validate id before interpolation.
    if ! printf '%s' "$id" | grep -qE "$_ID_RE"; then
        return 1
    fi
    # Glob across all area subdirs; compgen returns 0 if at least one match.
    if compgen -G "${archive_root}/*/archive-${id}.md" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ---------- argument parsing -------------------------------------------------

ROOT=""
MODE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            ROOT="$2"
            shift 2
            ;;
        --check)
            MODE="check"
            shift
            ;;
        --fix)
            MODE="fix"
            shift
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            _usage
            ;;
    esac
done

[ -n "$ROOT" ] || _usage
[ -n "$MODE" ] || _usage

BACKLOG="${ROOT}/datarim/backlog.md"
ARCHIVE_ROOT="${ROOT}/documentation/archive"

# ---------- main logic -------------------------------------------------------

if [ ! -f "$BACKLOG" ]; then
    printf 'prunable: 0  surfaced: 0  kept: 0\n'
    exit 0
fi

prunable=0
surfaced=0
kept=0

# We build a new backlog content in-memory (array of lines to keep).
# Bash arrays used; safe because we control the content (no eval, no subshell).
declare -a keep_lines=()

while IFS= read -r line; do
    # Only examine canonical backlog one-liners (start with "- ").
    if printf '%s' "$line" | grep -qE '^- [A-Z]{2,10}-[0-9]+'; then
        id="$(_extract_id "$line")"
        status="$(_extract_status "$line")"

        # Validate extracted id and status.
        if [ -z "$id" ] || ! printf '%s' "$id" | grep -qE "$_ID_RE"; then
            # Non-standard line — preserve it unchanged.
            keep_lines+=("$line")
            kept=$((kept+1))
            continue
        fi

        if printf '%s' "$status" | grep -qE "$_TERMINAL_RE"; then
            # Terminal status: check for archive doc.
            if _archive_exists "$ARCHIVE_ROOT" "$id"; then
                prunable=$((prunable+1))
                # --fix mode: skip this line (pruned). --check mode: also skip (dry-run count only).
                if [ "$MODE" = "check" ]; then
                    keep_lines+=("$line")  # dry-run: keep in memory, don't rewrite
                fi
                # In --fix mode: do NOT add to keep_lines → line is removed.
            else
                # Terminal but NO archive doc — PRESERVE + surface (data-loss-safe).
                surfaced=$((surfaced+1))
                printf 'surfaced: %s (status=%s; no archive doc — preserved in backlog)\n' "$id" "$status"
                keep_lines+=("$line")
            fi
        else
            # Non-terminal (pending, blocked-pending) or transient cancelled: keep.
            kept=$((kept+1))
            keep_lines+=("$line")
        fi
    else
        # Structural lines (headers, blank lines, etc.) — keep unchanged.
        keep_lines+=("$line")
    fi
done < "$BACKLOG"

# Report counts.
printf 'prunable: %d  surfaced: %d  kept: %d\n' "$prunable" "$surfaced" "$kept"

# Apply in --fix mode: atomic temp-file + mv.
if [ "$MODE" = "fix" ] && [ "$prunable" -gt 0 ]; then
    TMP="$(mktemp "${BACKLOG}.XXXXXX")" || {
        printf 'prune-backlog-terminal: mktemp failed\n' >&2
        exit 2
    }
    # Write kept lines to tmp file.
    for l in "${keep_lines[@]}"; do
        printf '%s\n' "$l"
    done > "$TMP"
    mv -f -- "$TMP" "$BACKLOG"
fi

exit 0
