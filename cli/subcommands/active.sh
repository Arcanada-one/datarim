#!/usr/bin/env bash
# active.sh — `datarim active` outputs § Active Tasks section verbatim from activeContext.md.

set -u

_ACTIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$_ACTIVE_DIR/../lib"
# shellcheck source=../lib/exit-codes.sh
source "$LIB_DIR/exit-codes.sh"
# shellcheck source=../lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=../lib/markdown-parser.sh
source "$LIB_DIR/markdown-parser.sh"
# shellcheck source=../lib/workspace.sh
source "$LIB_DIR/workspace.sh"

OUTPUT_MODE="plain"
while (( $# > 0 )); do
    case "$1" in
        --json) OUTPUT_MODE=json; shift ;;
        --help|-h) echo "usage: datarim active [--json]"; exit 0 ;;
        *)
            export DATARIM_CLI_CMD="active"; export OUTPUT_MODE
            output_emit_error 2 MISUSE "unknown arg '$1'" ;;
    esac
done
export OUTPUT_MODE
export DATARIM_CLI_CMD="active"

WS="$(ws_resolve)"
ACTIVE_CTX="$WS/datarim/activeContext.md"
[[ -f "$ACTIVE_CTX" ]] || output_emit_error 31 NOT_FOUND "activeContext.md not found"

section="$(awk '/^## Active Tasks$/{c=1;next} c && /^## /{exit} c' "$ACTIVE_CTX")"

if [[ "$OUTPUT_MODE" == "json" ]]; then
    items_md="$(mktemp -t active.XXXXXX)"
    echo "$section" > "$items_md"
    items_json="$(parse_thin_file "$items_md")"
    rm -f "$items_md"
    data="$(jq -n --argjson items "$items_json" '{active: $items, count: ($items | length)}')"
    output_emit_json "$data"
else
    printf '%s\n' "$section"
fi
