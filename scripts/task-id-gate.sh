#!/usr/bin/env bash
# task-id-gate.sh — pre-apply linter rejecting task-ID provenance references
# in Datarim runtime files (skills/agents/commands/templates).
#
# Source contract: skills/evolution/history-agnostic-gate.md.
# Sibling precedent: scripts/stack-agnostic-gate.sh (denylist gate, same shape).
#
# Datarim runtime rules MUST be history-agnostic. Provenance ("Source: TUNE-0033",
# "Per DEV-1183") couples rules to ephemeral identifiers (archived/renamed/cancelled
# tasks), distracts the reading agent, and risks leaking into AI outputs. History
# lives in docs/evolution-log.md, documentation/archive/, datarim/reflection/, and
# git log — not in runtime instructions.
#
# Usage:
#   scripts/task-id-gate.sh <file-or-dir> [--whitelist <path>] ...
#                           [--diff-only [<base>]]
#
# Inputs:
#   <file-or-dir>   Path to scan. File → single-file mode. Directory →
#                   recursive *.md scan (excluding tests/fixtures/).
#   --whitelist     Optional, repeatable. Suffix-based path match.
#                   Default whitelist: skills/evolution/history-agnostic-gate.md
#                   (the gate's own contract document — must enumerate the
#                   regex and would otherwise self-fail).
#   --diff-only     Scan only lines added in `git diff <base> -- <file>` —
#                   ignore pre-existing baseline matches. Default base = HEAD.
#                   Optional positional next arg is treated as base if it does
#                   not exist as a filesystem path. Single-file target outside
#                   a git repo or untracked → exit 2; directory scan silently
#                   skips untracked files.
#
# Output (stderr):
#   Per match: "<path>:<line>:<id>"
#   Summary:   "FAIL: N matches in M files" or "PASS: clean"
#
# Exit codes:
#   0  clean (no matches)
#   1  matches found
#   2  invocation error (path missing, etc.)
#
# Implementation notes:
#   - Pure bash + grep + awk, bash 3.2 compatible (macOS default).
#   - Single regex constant — no per-keyword denylist (task IDs share one shape).
#   - Escape hatch for legitimate placeholders / illustrative IDs: wrap a fenced
#     block in `<!-- gate:history-allowed -->` markers (handled by skipping any
#     line between an opening and closing marker — markers MUST be on separate
#     lines, see skills/evolution/history-agnostic-gate.md § markers pitfall).
#   - Read-only: no writes, no network, no exec of scanned content.

set -uo pipefail

# ---------------------------------------------------------------------------
# Match pattern. Whole-word boundary on both sides. Two-to-ten upper-case
# letters, hyphen, exactly four digits (matches TUNE-0042, DEV-1183, INFRA-0029,
# AGENT-0001 etc. but not "AB-1" or "FOO-12345").
# ---------------------------------------------------------------------------
TASK_ID_REGEX='\b[A-Z]{2,10}-[0-9]{4}\b'

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WHITELIST=(
    "skills/evolution/history-agnostic-gate.md"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
TARGET=""
DIFF_ONLY=0
DIFF_BASE="HEAD"
while [ $# -gt 0 ]; do
    case "$1" in
        --whitelist)
            shift
            [ $# -gt 0 ] || { echo "task-id-gate: --whitelist requires a value" >&2; exit 2; }
            WHITELIST+=("$1")
            shift
            ;;
        --reset-whitelist)
            WHITELIST=()
            shift
            ;;
        --diff-only)
            DIFF_ONLY=1
            shift
            if [ $# -gt 0 ] && [ "${1#-}" = "$1" ] && [ ! -e "$1" ]; then
                DIFF_BASE="$1"
                shift
            fi
            ;;
        --help|-h)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --*)
            echo "task-id-gate: unknown flag $1" >&2
            exit 2
            ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$1"
            else
                echo "task-id-gate: only one target path supported (got '$TARGET' and '$1')" >&2
                exit 2
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "Usage: task-id-gate.sh <file-or-dir> [--whitelist <path>] [--diff-only [<base>]]" >&2
    exit 2
fi

if [ ! -e "$TARGET" ]; then
    echo "task-id-gate: path not found: $TARGET" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
is_whitelisted() {
    local path="$1"
    local entry
    for entry in "${WHITELIST[@]:-}"; do
        [ -n "$entry" ] || continue
        case "$path" in
            *"$entry") return 0 ;;
        esac
    done
    return 1
}

# Strip lines inside <!-- gate:history-allowed --> ... <!-- /gate:history-allowed -->
# blocks. Reads from stdin, writes to stdout; line numbers preserved by replacing
# skipped lines with blanks. Markers MUST be on separate lines (same-line form
# triggers the skip persistence bug — see contract doc § pitfall).
strip_history_blocks() {
    awk '
        /<!-- gate:history-allowed -->/ { skip=1; print ""; next }
        /<!-- \/gate:history-allowed -->/ { skip=0; print ""; next }
        { if (skip) print ""; else print }
    '
}

produce_scan_stream() {
    local file="$1"
    if [ "$DIFF_ONLY" -ne 1 ]; then
        cat "$file"
        return 0
    fi
    local repo_root
    repo_root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)" || return 2
    if ! git -C "$repo_root" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
        return 2
    fi
    git -C "$repo_root" diff "$DIFF_BASE" -- "$file" 2>/dev/null \
        | awk '/^\+\+\+ /{next} /^\+/{print substr($0,2)}'
}

SCAN_FILE_HITS=0
SCAN_FILE_DIFF_SKIP=0

scan_file() {
    SCAN_FILE_HITS=0
    SCAN_FILE_DIFF_SKIP=0
    local file="$1"
    if is_whitelisted "$file"; then
        return 0
    fi

    local stream
    if ! stream="$(produce_scan_stream "$file")"; then
        SCAN_FILE_DIFF_SKIP=1
        return 0
    fi

    # Strip <!-- gate:history-allowed --> blocks then run a single ERE grep.
    # Case-sensitive (task IDs are all-caps by convention). -n line numbers,
    # -o emits matching token only — we want the ID literal labelled per hit.
    local matches
    matches="$(printf '%s\n' "$stream" | strip_history_blocks | grep -nE -o -- "$TASK_ID_REGEX" 2>/dev/null || true)"

    [ -z "$matches" ] && return 0

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        local line_no="${match%%:*}"
        local id="${match#*:}"
        printf '%s:%s:%s\n' "$file" "$line_no" "$id" >&2
        SCAN_FILE_HITS=$((SCAN_FILE_HITS + 1))
    done <<< "$matches"

    return 0
}

# ---------------------------------------------------------------------------
# Main scan
# ---------------------------------------------------------------------------
TOTAL_HITS=0
FILES_WITH_HITS=0

scan_path() {
    local path="$1"
    if [ -f "$path" ]; then
        scan_file "$path"
        if [ "$DIFF_ONLY" -eq 1 ] && [ "$SCAN_FILE_DIFF_SKIP" -eq 1 ]; then
            echo "task-id-gate: --diff-only requires a tracked file inside a git repo: $path" >&2
            exit 2
        fi
        if [ "$SCAN_FILE_HITS" -gt 0 ]; then
            TOTAL_HITS=$((TOTAL_HITS + SCAN_FILE_HITS))
            FILES_WITH_HITS=$((FILES_WITH_HITS + 1))
        fi
    elif [ -d "$path" ]; then
        while IFS= read -r f; do
            scan_file "$f"
            if [ "$SCAN_FILE_HITS" -gt 0 ]; then
                TOTAL_HITS=$((TOTAL_HITS + SCAN_FILE_HITS))
                FILES_WITH_HITS=$((FILES_WITH_HITS + 1))
            fi
        done < <(find "$path" -type f -name '*.md' \
                    -not -path '*/tests/fixtures/*' \
                    -not -path '*/node_modules/*' \
                    -not -path '*/.git/*' \
                    | sort)
    fi
}

scan_path "$TARGET"

if [ "$TOTAL_HITS" -eq 0 ]; then
    echo "PASS: clean" >&2
    exit 0
fi

echo "FAIL: $TOTAL_HITS matches in $FILES_WITH_HITS files" >&2
exit 1
