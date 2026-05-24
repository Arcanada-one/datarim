#!/usr/bin/env bash
# backlog.sh — `datarim backlog list [--prefix PFX]`.

set -u

_BACKLOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$_BACKLOG_DIR/../lib"
# shellcheck source=../lib/exit-codes.sh
source "$LIB_DIR/exit-codes.sh"
# shellcheck source=../lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=../lib/markdown-parser.sh
source "$LIB_DIR/markdown-parser.sh"

OUTPUT_MODE="plain"
SUBCMD=""
PREFIX=""

while (( $# > 0 )); do
    case "$1" in
        list) SUBCMD=list; shift ;;
        --json) OUTPUT_MODE=json; shift ;;
        --prefix) PREFIX="${2:-}"; shift 2 ;;
        --help|-h)
            cat <<'USAGE'
usage: datarim backlog list [--prefix PFX] [--json]
USAGE
            exit 0
            ;;
        *)
            export DATARIM_CLI_CMD="backlog"; export OUTPUT_MODE
            output_emit_error 2 MISUSE "unknown arg '$1'"
            ;;
    esac
done

if [[ -z "$SUBCMD" ]]; then
    export DATARIM_CLI_CMD="backlog"; export OUTPUT_MODE
    output_emit_error 2 MISUSE "subcommand required: list"
fi
export OUTPUT_MODE
export DATARIM_CLI_CMD="backlog list"

_ws_resolve() {
    if [[ -n "${DATARIM_WORKSPACE_ROOT:-}" ]]; then
        printf '%s' "$DATARIM_WORKSPACE_ROOT"
        return
    fi
    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        if [[ -d "$d/datarim" ]]; then printf '%s' "$d"; return; fi
        d="$(dirname "$d")"
    done
    printf '%s' "$HOME/arcanada"
}

WS="$(_ws_resolve)"
BACKLOG_MD="$WS/datarim/backlog.md"
[[ -f "$BACKLOG_MD" ]] || output_emit_error 31 NOT_FOUND "backlog.md not found at $BACKLOG_MD"

items_json="$(parse_thin_file "$BACKLOG_MD")"

# Apply prefix filter if any.
if [[ -n "$PREFIX" ]]; then
    items_json="$(echo "$items_json" | jq --arg p "$PREFIX" '[.[] | select(.id | startswith($p))]')"
fi

if [[ "$OUTPUT_MODE" == "json" ]]; then
    data="$(jq -n --argjson items "$items_json" --arg prefix "$PREFIX" \
        '{items: $items, prefix: $prefix, count: ($items | length)}')"
    output_emit_json "$data"
else
    count="$(echo "$items_json" | jq 'length')"
    echo "$items_json" | jq -r '.[] | "  \(.id) · \(.status) · \(.priority) · \(.complexity) · \(.title)"'
    printf 'total: %s\n' "$count"
fi
