#!/usr/bin/env bash
# tasks.sh — `datarim tasks {list,show}` subcommand.

set -u

_TASKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$_TASKS_DIR/../lib"
# shellcheck source=../lib/exit-codes.sh
source "$LIB_DIR/exit-codes.sh"
# shellcheck source=../lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=../lib/markdown-parser.sh
source "$LIB_DIR/markdown-parser.sh"
# shellcheck source=../lib/workspace.sh
source "$LIB_DIR/workspace.sh"

OUTPUT_MODE="plain"
SUBCMD=""
TARGET_ID=""

while (( $# > 0 )); do
    case "$1" in
        list|show)
            SUBCMD="$1"; shift
            ;;
        --json) OUTPUT_MODE=json; shift ;;
        --help|-h)
            cat <<'USAGE'
usage: datarim tasks list [--json]
       datarim tasks show <TASK-ID> [--json]
USAGE
            exit 0
            ;;
        --*)
            export DATARIM_CLI_CMD="tasks"; export OUTPUT_MODE
            output_emit_error 2 MISUSE "unknown flag '$1'"
            ;;
        *)
            if [[ "$SUBCMD" == "show" && -z "$TARGET_ID" ]]; then
                TARGET_ID="$1"; shift
            else
                export DATARIM_CLI_CMD="tasks"; export OUTPUT_MODE
                output_emit_error 2 MISUSE "unknown arg '$1'"
            fi
            ;;
    esac
done
export OUTPUT_MODE

if [[ -z "$SUBCMD" ]]; then
    export DATARIM_CLI_CMD="tasks"
    output_emit_error 2 MISUSE "subcommand required: list | show <ID>"
fi

# Resolve workspace.
WS="$(ws_resolve)"
TASKS_MD="$WS/datarim/tasks.md"

if [[ "$SUBCMD" == "list" ]]; then
    export DATARIM_CLI_CMD="tasks list"
    [[ -f "$TASKS_MD" ]] || output_emit_error 31 NOT_FOUND "tasks.md not found at $TASKS_MD"
    tasks_json="$(parse_thin_file "$TASKS_MD")"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        data="$(jq -n --argjson tasks "$tasks_json" '{tasks: $tasks}')"
        output_emit_json "$data"
    else
        echo "$tasks_json" | jq -r '.[] | "  \(.id) · \(.status) · \(.priority) · \(.complexity) · \(.title)"'
    fi
    exit 0
fi

# show <ID>
export DATARIM_CLI_CMD="tasks show"
[[ -n "$TARGET_ID" ]] || output_emit_error 2 MISUSE "tasks show requires TASK-ID"
ws_validate_task_id "$TARGET_ID" || output_emit_error 2 MISUSE "invalid TASK-ID '$TARGET_ID' (expected PREFIX-NNNN[A])"

# Candidate files (in canonical order).
candidates=(
    "$WS/datarim/tasks/${TARGET_ID}-init-task.md"
    "$WS/datarim/tasks/${TARGET_ID}-task-description.md"
    "$WS/datarim/prd/PRD-${TARGET_ID}.md"
    "$WS/datarim/plans/${TARGET_ID}-plan.md"
)

# Reflection (most-recent reflection-<TARGET_ID>*.md OR qa-report-<TARGET_ID>.md).
reflection_file="$WS/datarim/reflection/reflection-${TARGET_ID}.md"
qa_file="$WS/datarim/qa/qa-report-${TARGET_ID}.md"
[[ -f "$reflection_file" ]] && candidates+=("$reflection_file")
[[ -f "$qa_file" ]] && candidates+=("$qa_file")

# Filter to existing files.
existing=()
for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && existing+=("$c")
done

if [[ ${#existing[@]} -eq 0 ]]; then
    output_emit_error 31 NOT_FOUND "no artefacts found for $TARGET_ID"
fi

if [[ "$OUTPUT_MODE" == "json" ]]; then
    sections_arr='[]'
    for f in "${existing[@]}"; do
        body="$(cat "$f")"
        sections_arr="$(echo "$sections_arr" | jq \
            --arg path "${f#"$WS"/}" \
            --arg body "$body" \
            '. + [{path: $path, body: $body}]')"
    done
    data="$(jq -n \
        --arg id "$TARGET_ID" \
        --argjson sections "$sections_arr" \
        '{task_id: $id, sections: $sections}')"
    output_emit_json "$data"
else
    for f in "${existing[@]}"; do
        printf '==== %s ====\n' "${f#"$WS"/}"
        cat "$f"
        printf '\n'
    done
fi
