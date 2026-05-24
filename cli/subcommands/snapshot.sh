#!/usr/bin/env bash
# snapshot.sh — `datarim snapshot show <TASK-ID>`.

set -u

_SNAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$_SNAP_DIR/../lib"
# shellcheck source=../lib/exit-codes.sh
source "$LIB_DIR/exit-codes.sh"
# shellcheck source=../lib/output.sh
source "$LIB_DIR/output.sh"

OUTPUT_MODE="plain"
SUBCMD=""
TARGET_ID=""

while (( $# > 0 )); do
    case "$1" in
        show) SUBCMD=show; shift ;;
        --json) OUTPUT_MODE=json; shift ;;
        --help|-h)
            echo "usage: datarim snapshot show <TASK-ID> [--json]"
            exit 0 ;;
        --*)
            export DATARIM_CLI_CMD="snapshot"; export OUTPUT_MODE
            output_emit_error 2 MISUSE "unknown flag '$1'" ;;
        *)
            if [[ "$SUBCMD" == "show" && -z "$TARGET_ID" ]]; then
                TARGET_ID="$1"; shift
            else
                export DATARIM_CLI_CMD="snapshot"; export OUTPUT_MODE
                output_emit_error 2 MISUSE "unknown arg '$1'"
            fi ;;
    esac
done
export OUTPUT_MODE
export DATARIM_CLI_CMD="snapshot show"

[[ "$SUBCMD" == "show" && -n "$TARGET_ID" ]] || output_emit_error 2 MISUSE "snapshot show <TASK-ID> required"

_ws_resolve() {
    if [[ -n "${DATARIM_WORKSPACE_ROOT:-}" ]]; then printf '%s' "$DATARIM_WORKSPACE_ROOT"; return; fi
    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        [[ -d "$d/datarim" ]] && { printf '%s' "$d"; return; }
        d="$(dirname "$d")"
    done
    printf '%s' "$HOME/arcanada"
}

WS="$(_ws_resolve)"
SNAP="$WS/datarim/snapshots/${TARGET_ID}.snapshot.md"

[[ -f "$SNAP" ]] || output_emit_error 31 NOT_FOUND "snapshot not found at $SNAP"

if [[ "$OUTPUT_MODE" == "json" ]]; then
    body="$(cat "$SNAP")"
    data="$(jq -n --arg id "$TARGET_ID" --arg body "$body" --arg path "${SNAP#"$WS"/}" \
        '{task_id: $id, path: $path, body: $body}')"
    output_emit_json "$data"
else
    cat "$SNAP"
fi
