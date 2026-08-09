#!/usr/bin/env bash
# task-id-gate.sh — reject task-ID provenance on governed public surfaces.
#
# Source contract: skills/evolution/history-agnostic-gate.md.
#
# Usage:
#   scripts/task-id-gate.sh <file-or-dir> [--whitelist <path>] ...
#                           [--diff-only [<base>]]
#                           [--base-commit <sha>]
#
# Directory inputs scan regular text files ending in .md, .template, .sh,
# .yaml, or .yml. The CLI accepts one target so callers make policy scope
# explicit. Default exact exemptions are this gate's contract and the public
# evolution log.
#
# Output (stderr):
#   Per finding: "<path>:<line>:<finding>"
#   Summary:     "FAIL: N matches in M files" or "PASS: clean"
#
# Exit codes:
#   0 clean; 1 policy finding; 2 invocation or scanner error.

set -euo pipefail
IFS=$'\n\t'

WHITELIST=(
    "skills/evolution/history-agnostic-gate.md"
    "documentation/how-to/evolution-log.md"
)

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
        --base-commit)
            shift
            [ $# -gt 0 ] || { echo "task-id-gate: --base-commit requires a SHA/ref argument" >&2; exit 2; }
            DIFF_ONLY=1
            DIFF_BASE="$1"
            shift
            ;;
        --help|-h)
            awk 'NR>1 && /^[^#]/{exit} NR>1{sub(/^# ?/,""); print}' "$0"
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

if [ -L "$TARGET" ]; then
    echo "task-id-gate: symlink target is not accepted: $TARGET" >&2
    exit 2
fi
if [ ! -e "$TARGET" ]; then
    echo "task-id-gate: path not found: $TARGET" >&2
    exit 2
fi
if [ ! -f "$TARGET" ] && [ ! -d "$TARGET" ]; then
    echo "task-id-gate: target must be a regular file or directory: $TARGET" >&2
    exit 2
fi

canonical_path() {
    local path="$1"
    local parent
    parent="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$parent" "$(basename "$path")"
}

repo_relative_path() {
    local file="$1"
    local file_abs repo_root repo_abs
    file_abs="$(canonical_path "$file")" || return 1
    repo_root="$(git -C "$(dirname "$file_abs")" rev-parse --show-toplevel 2>/dev/null)" || return 1
    repo_abs="$(canonical_path "$repo_root")" || return 1
    case "$file_abs" in
        "$repo_abs"/*) printf '%s\n' "${file_abs#"$repo_abs"/}" ;;
        *) return 1 ;;
    esac
}

is_whitelisted() {
    local file="$1"
    local file_abs file_rel entry entry_abs normalized
    file_abs="$(canonical_path "$file")" || return 1
    file_rel="$(repo_relative_path "$file" 2>/dev/null || true)"

    for entry in "${WHITELIST[@]:-}"; do
        [ -n "$entry" ] || continue
        case "$entry" in
            /*)
                entry_abs="$(canonical_path "$entry" 2>/dev/null || true)"
                [ -n "$entry_abs" ] && [ "$file_abs" = "$entry_abs" ] && return 0
                ;;
            *)
                normalized="${entry#./}"
                [ -n "$file_rel" ] && [ "$file_rel" = "$normalized" ] && return 0
                ;;
        esac
    done
    return 1
}

validate_text_file() {
    local file="$1"
    if [ -L "$file" ] || [ ! -f "$file" ]; then
        echo "task-id-gate: governed input is not a regular file: $file" >&2
        return 2
    fi
    if [ ! -r "$file" ]; then
        echo "task-id-gate: governed input is unreadable: $file" >&2
        return 2
    fi
    if [ -s "$file" ] && ! LC_ALL=C grep -Iq '' "$file"; then
        echo "task-id-gate: governed input is not text: $file" >&2
        return 2
    fi
    return 0
}

produce_scan_stream() {
    local file="$1"
    local allow_untracked="$2"
    local file_abs repo_root repo_abs rel

    if [ "$DIFF_ONLY" -ne 1 ]; then
        cat -- "$file" || return 2
        return 0
    fi

    file_abs="$(canonical_path "$file")" || return 2
    repo_root="$(git -C "$(dirname "$file_abs")" rev-parse --show-toplevel 2>/dev/null)" || return 2
    repo_abs="$(canonical_path "$repo_root")" || return 2
    case "$file_abs" in
        "$repo_abs"/*) rel="${file_abs#"$repo_abs"/}" ;;
        *) return 2 ;;
    esac

    git -C "$repo_root" rev-parse --verify "${DIFF_BASE}^{commit}" >/dev/null 2>&1 || return 2
    if ! git -C "$repo_root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        if [ "$allow_untracked" -eq 1 ]; then
            cat -- "$file" || return 2
            return 0
        fi
        return 3
    fi

    git -C "$repo_root" diff "$DIFF_BASE" -- "$rel" 2>/dev/null \
        | awk '/^\+\+\+ /{next} /^\+/{print substr($0,2)}'
    local pipeline_status=("${PIPESTATUS[@]}")
    [ "${pipeline_status[0]}" -eq 0 ] || return 2
    [ "${pipeline_status[1]}" -eq 0 ] || return 2
    return 0
}

scan_stream() {
    awk '
        function emit(kind, line_no, detail) {
            print line_no ":" kind ":" detail
        }

        function emit_ids(text, line_no, kind,    rest, offset, candidate, dash, letters, pos, before, after_pos, after, advance) {
            rest = text
            offset = 0
            while (match(rest, /[A-Z][A-Z][A-Z]*-[0-9][0-9][0-9][0-9]/)) {
                candidate = substr(rest, RSTART, RLENGTH)
                dash = index(candidate, "-")
                letters = dash - 1
                pos = offset + RSTART
                before = (pos > 1) ? substr(text, pos - 1, 1) : ""
                after_pos = pos + length(candidate)
                after = (after_pos <= length(text)) ? substr(text, after_pos, 1) : ""
                if (letters >= 2 && letters <= 10 && before !~ /[[:alnum:]_]/ && after !~ /[[:alnum:]_]/) {
                    emit(kind, line_no, candidate)
                }
                advance = RSTART + RLENGTH - 1
                offset += advance
                rest = substr(rest, advance + 1)
            }
        }

        function is_label(text,    normalized) {
            normalized = tolower(text)
            gsub(/[`*_>#|+]/, "", normalized)
            gsub(/\[/, "", normalized)
            gsub(/\]/, "", normalized)
            gsub(/-/, "", normalized)
            sub(/^[[:space:]]*[0-9]+[.)][[:space:]]*/, "", normalized)
            sub(/^[[:space:]]*/, "", normalized)
            return normalized ~ /^(source task|source|reference|created|parent epic)[[:space:]]*:/
        }

        BEGIN {
            inside = 0
            pending_label = 0
            open_line = 0
        }

        {
            exact_open = ($0 ~ /^[[:space:]]*<!--[ ]gate:history-allowed[ ]-->[[:space:]]*$/)
            exact_close = ($0 ~ /^[[:space:]]*<!--[ ]\/gate:history-allowed[ ]-->[[:space:]]*$/)
            has_open = (index($0, "<!-- gate:history-allowed -->") > 0)
            has_close = (index($0, "<!-- /gate:history-allowed -->") > 0)

            if (exact_open) {
                if (inside) emit("malformed-history-marker", NR, "nested-open")
                else {
                    inside = 1
                    open_line = NR
                }
                pending_label = 0
                next
            }
            if (exact_close) {
                if (!inside) emit("malformed-history-marker", NR, "stray-close")
                else inside = 0
                pending_label = 0
                next
            }
            if (has_open || has_close) {
                emit("malformed-history-marker", NR, "marker-must-be-alone")
                pending_label = 0
                next
            }

            if (!inside) {
                emit_ids($0, NR, "task-id")
                next
            }

            if (is_label($0)) {
                emit_ids($0, NR, "history-provenance-label")
                pending_label = 1
                next
            }

            if (pending_label && $0 !~ /^[[:space:]]*$/) {
                emit_ids($0, NR, "history-provenance-continuation")
                pending_label = 0
            }
        }

        END {
            if (inside) emit("malformed-history-marker", open_line, "unclosed-open")
        }
    '
}

SCAN_FILE_HITS=0
SCAN_FILE_ERROR=0

scan_file() {
    local file="$1"
    local allow_untracked="$2"
    local stream rc matches match

    SCAN_FILE_HITS=0
    SCAN_FILE_ERROR=0

    validate_text_file "$file" || { SCAN_FILE_ERROR=1; return 0; }
    if is_whitelisted "$file"; then
        return 0
    fi

    rc=0
    stream="$(produce_scan_stream "$file" "$allow_untracked")" || rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ "$rc" -eq 3 ]; then
            echo "task-id-gate: --diff-only requires a tracked file inside a git repo: $file" >&2
        else
            echo "task-id-gate: failed to produce scan stream for $file (base: $DIFF_BASE)" >&2
        fi
        SCAN_FILE_ERROR=1
        return 0
    fi

    rc=0
    matches="$(printf '%s\n' "$stream" | scan_stream)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "task-id-gate: scanner error for $file" >&2
        SCAN_FILE_ERROR=1
        return 0
    fi
    [ -z "$matches" ] && return 0

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        printf '%s:%s\n' "$file" "$match" >&2
        SCAN_FILE_HITS=$((SCAN_FILE_HITS + 1))
    done <<< "$matches"
}

TOTAL_HITS=0
FILES_WITH_HITS=0
SCAN_ERRORS=0

accumulate_file_result() {
    if [ "$SCAN_FILE_ERROR" -eq 1 ]; then
        SCAN_ERRORS=$((SCAN_ERRORS + 1))
    fi
    if [ "$SCAN_FILE_HITS" -gt 0 ]; then
        TOTAL_HITS=$((TOTAL_HITS + SCAN_FILE_HITS))
        FILES_WITH_HITS=$((FILES_WITH_HITS + 1))
    fi
}

if [ -f "$TARGET" ]; then
    scan_file "$TARGET" 0
    accumulate_file_result
else
    TARGET_ABS="$(canonical_path "$TARGET")" || {
        echo "task-id-gate: cannot canonicalize target: $TARGET" >&2
        exit 2
    }
    SCAN_LIST="$(mktemp "${TMPDIR:-/tmp}/task-id-gate.XXXXXX")" || {
        echo "task-id-gate: cannot create scan list" >&2
        exit 2
    }
    trap 'rm -f "$SCAN_LIST"' EXIT

    if ! find "$TARGET_ABS" \
        \( -type f -o -type l -o -type p -o -type s -o -type b -o -type c \) \
        \( -name '*.md' -o -name '*.template' -o -name '*.sh' -o -name '*.yaml' -o -name '*.yml' \) \
        -print0 > "$SCAN_LIST"; then
        echo "task-id-gate: directory traversal failed: $TARGET" >&2
        exit 2
    fi

    while IFS= read -r -d '' file; do
        relative="${file#"$TARGET_ABS"/}"
        case "$relative" in
            tests/fixtures/*|node_modules/*|.git/*) continue ;;
        esac
        scan_file "$file" 1
        accumulate_file_result
    done < "$SCAN_LIST"
fi

if [ "$SCAN_ERRORS" -gt 0 ]; then
    echo "task-id-gate: $SCAN_ERRORS scanner error(s)" >&2
    exit 2
fi

if [ "$TOTAL_HITS" -gt 0 ]; then
    echo "FAIL: $TOTAL_HITS matches in $FILES_WITH_HITS files" >&2
    exit 1
fi

echo "PASS: clean" >&2
exit 0
