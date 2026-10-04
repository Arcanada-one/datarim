#!/usr/bin/env bash
# markdown-parser.sh — thin one-liner parser for datarim/{tasks,backlog}.md.
# Canonical schema (datarim-system.md § Operational File Schema):
#   - {TASK-ID} · {status} · P{n} · L{n} · {title...} → tasks/{TASK-ID}-{descriptor}.md
#
# Public API:
#   parse_thin_line <line>       — parses one line, emits JSON or exit 30
#   parse_thin_file <path>       — streams all thin lines, emits JSON array
#
# Bash 3.2-compatible. Dependencies: jq.

[[ -n "${_MARKDOWN_PARSER_LOADED:-}" ]] && return 0
_MARKDOWN_PARSER_LOADED=1

_MP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=exit-codes.sh
source "$_MP_DIR/exit-codes.sh"

# Thin-line regex (POSIX ERE; capture groups in order):
#   1: TASK-ID (e.g. TUNE-0268, ARCA-0135-A)
#   2: status (e.g. in_progress, not_started, pending, blocked, completed)
#   3: priority (e.g. P0..P4)
#   4: complexity (e.g. L1..L4)
#   5: title (greedy, includes brackets/unicode/dashes до ` → `)
#   6: pointer (e.g. tasks/TUNE-0268-init-task.md)
_MP_REGEX='^- ([A-Z][A-Z0-9]+-[0-9]+[A-Z]?) · ([a-z_]+) · (P[0-9]+) · (L[0-9]+) · (.+) → (tasks/[^[:space:]]+\.md)[[:space:]]*$'

parse_thin_line() {
    local line="${1-}"
    if [[ "$line" =~ $_MP_REGEX ]]; then
        local id="${BASH_REMATCH[1]}"
        local status="${BASH_REMATCH[2]}"
        local priority="${BASH_REMATCH[3]}"
        local complexity="${BASH_REMATCH[4]}"
        local title="${BASH_REMATCH[5]}"
        local pointer="${BASH_REMATCH[6]}"
        jq -n \
            --arg id "$id" \
            --arg status "$status" \
            --arg priority "$priority" \
            --arg complexity "$complexity" \
            --arg title "$title" \
            --arg pointer "$pointer" \
            '{id: $id, status: $status, priority: $priority, complexity: $complexity, title: $title, pointer: $pointer}'
        return 0
    fi
    return "$(exit_code_of STATE_MISMATCH)"
}

parse_thin_file() {
    local path="${1:?parse_thin_file: path required}"
    if [[ ! -f "$path" ]]; then
        return "$(exit_code_of NOT_FOUND)"
    fi
    local tmp_arr
    tmp_arr="$(mktemp -t mp.XXXXXX)"
    # Filter lines that look like thin one-liners, parse each, accumulate into JSON array.
    {
        echo '['
        local first=1
        local line
        while IFS= read -r line; do
            # Quick filter: lines starting with `- ` and containing ` · ` AND ` → `.
            case "$line" in
                "- "*" · "*" · "*" → "*) ;;
                *) continue ;;
            esac
            local obj
            obj="$(parse_thin_line "$line" 2>/dev/null)" || continue
            if [[ $first -eq 1 ]]; then
                first=0
            else
                echo ','
            fi
            printf '%s' "$obj"
        done < "$path"
        echo
        echo ']'
    } > "$tmp_arr"
    jq -c . < "$tmp_arr"
    local rc=$?
    rm -f "$tmp_arr"
    return $rc
}
