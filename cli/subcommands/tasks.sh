#!/usr/bin/env bash
# tasks.sh — `datarim tasks {list,show,move}` subcommand.
# list  — Phase 1 read-only enumeration.
# show  — Phase 1 multi-artefact concatenation (init-task + PRD + plan + reflection).
# move  — Phase 2b write op: TASK-ID pipeline-advance + tasks.md status update + audit JSONL.

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
TARGET_PHASE=""
MOVE_REASON=""

while (( $# > 0 )); do
    case "$1" in
        list|show|move)
            SUBCMD="$1"; shift
            ;;
        --json) OUTPUT_MODE=json; shift ;;
        --reason) MOVE_REASON="${2:-}"; shift 2 ;;
        --help|-h)
            cat <<'USAGE'
usage: datarim tasks list [--json]
       datarim tasks show <TASK-ID> [--json]
       datarim tasks move <TASK-ID> <init|prd|plan|do|qa|compliance|archive> [--reason "<text>"] [--json]
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
            elif [[ "$SUBCMD" == "move" && -z "$TARGET_ID" ]]; then
                TARGET_ID="$1"; shift
            elif [[ "$SUBCMD" == "move" && -z "$TARGET_PHASE" ]]; then
                TARGET_PHASE="$1"; shift
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
    output_emit_error 2 MISUSE "subcommand required: list | show <ID> | move <ID> <phase>"
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

if [[ "$SUBCMD" == "show" ]]; then
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
    exit 0
fi

# ---- move ----------------------------------------------------------------

export DATARIM_CLI_CMD="tasks move"

# Defense-in-depth kill-switch.
# shellcheck source=../lib/kill-switch.sh
source "$LIB_DIR/kill-switch.sh"
check_kill_switch || exit $?

# Required args.
[[ -n "$TARGET_ID" ]]    || output_emit_error 2 MISUSE "tasks move requires TASK-ID"
[[ -n "$TARGET_PHASE" ]] || output_emit_error 2 MISUSE "tasks move requires target-phase"

# Validate TASK-ID format ws_validate_task_id was already called via show path —
# но move re-entry: validate здесь.
ws_validate_task_id "$TARGET_ID" || output_emit_error 2 MISUSE "invalid TASK-ID '$TARGET_ID' (expected PREFIX-NNNN[A])"

# Phase enum gate.
case "$TARGET_PHASE" in
    init|prd|plan|design|do|qa|compliance|archive) ;;
    *)
        output_emit_error 32 INVALID_COMMAND "target-phase must be one of: init prd plan design do qa compliance archive (got '$TARGET_PHASE')"
        ;;
esac

[[ -f "$TASKS_MD" ]] || output_emit_error 31 NOT_FOUND "tasks.md not found at $TASKS_MD"

# Find current entry line.
entry_line="$(grep -nE "^- ${TARGET_ID} ·" "$TASKS_MD" | head -1)"
if [[ -z "$entry_line" ]]; then
    output_emit_error 31 NOT_FOUND "task $TARGET_ID not found in tasks.md"
fi

lineno="${entry_line%%:*}"
current="${entry_line#*:}"
# Parse `- <ID> · <status> · <P> · <L> · <title> → <link>`
current_status="$(printf '%s' "$current" | awk -F' · ' '{print $2}')"

# Decide new status: advancing from pending → in_progress; else keep.
new_status="$current_status"
case "$TARGET_PHASE" in
    plan|design|do|qa|compliance)
        [[ "$current_status" == "pending" ]] && new_status="in_progress"
        ;;
esac

# In-place update of the one-liner.
if [[ "$new_status" != "$current_status" ]]; then
    new_line="$(printf '%s' "$current" | sed "s/ · ${current_status} · / · ${new_status} · /")"
    # Replace exact line N with new_line (portable sed; macOS BSD + GNU).
    tmp="${TASKS_MD}.tmp.$$"
    awk -v n="$lineno" -v repl="$new_line" 'NR==n{print repl; next}{print}' "$TASKS_MD" > "$tmp" && mv "$tmp" "$TASKS_MD"
fi

# Optional Q&A round-trip append (operator-supplied --reason).
if [[ -n "$MOVE_REASON" ]]; then
    init_task="$WS/datarim/tasks/${TARGET_ID}-init-task.md"
    if [[ -f "$init_task" ]]; then
        # Map phase to append-init-task-qa.sh --stage enum (prd|plan|design|do|qa|compliance).
        qa_stage=""
        case "$TARGET_PHASE" in
            prd|plan|design|do|qa|compliance) qa_stage="$TARGET_PHASE" ;;
            init|archive) qa_stage="do" ;;  # closest available stage в enum
        esac
        # Q&A append via shared helper (best-effort; failure non-blocking — operator can re-run).
        helper="$WS/Projects/Datarim/code/datarim/dev-tools/append-init-task-qa.sh"
        [[ -x "$helper" ]] || helper="$(command -v append-init-task-qa.sh 2>/dev/null || true)"
        if [[ -x "$helper" ]]; then
            qf="$(mktemp)"; af="$(mktemp)"; rf="$(mktemp)"
            printf 'Advance %s to phase %s' "$TARGET_ID" "$TARGET_PHASE" > "$qf"
            printf '%s' "$MOVE_REASON" > "$af"
            printf 'CLI-driven pipeline-advance via `datarim tasks move`; operator-supplied reason: %s' "$MOVE_REASON" > "$rf"
            # Determine round number: count existing Q&A blocks.
            existing_rounds=$(grep -cE '^### .* — Q&A by /dr-' "$init_task" 2>/dev/null || true)
            existing_rounds=${existing_rounds:-0}
            round=$((existing_rounds + 1))
            "$helper" --root "$WS" --task "$TARGET_ID" --stage "$qa_stage" --round "$round" \
                --question-file "$qf" --answer-file "$af" \
                --decided-by operator --summary "operator advanced via CLI tasks move (target=$TARGET_PHASE)" \
                --asked-by "/dr-do" 2>/dev/null || \
            # Fallback: minimal inline append (if helper unavailable in fixture, write a stub Q&A block).
            {
                printf '\n### %s — Q&A by /dr-%s (round %d)\n**Decided by:** operator\n**Summary:** operator advanced via CLI tasks move (target=%s)\n**Answer:** %s\n' \
                    "$(date -u +%FT%TZ)" "$qa_stage" "$round" "$TARGET_PHASE" "$MOVE_REASON" >> "$init_task"
            }
            rm -f "$qf" "$af" "$rf"
        else
            # Helper не найден — fallback inline write для дальнейшего восстановления.
            existing_rounds=$(grep -cE '^### .* — Q&A by /dr-' "$init_task" 2>/dev/null || true)
            existing_rounds=${existing_rounds:-0}
            round=$((existing_rounds + 1))
            qa_stage_local="$qa_stage"
            printf '\n### %s — Q&A by /dr-%s (round %d)\n**Decided by:** operator\n**Summary:** operator advanced via CLI tasks move (target=%s)\n**Answer:** %s\n' \
                "$(date -u +%FT%TZ)" "$qa_stage_local" "$round" "$TARGET_PHASE" "$MOVE_REASON" >> "$init_task"
        fi
    fi
fi

# Selective hunk staging via workspace-discipline (no-op when tasks.md is gitignored — typical).
# shellcheck source=../lib/workspace-discipline.sh
source "$LIB_DIR/workspace-discipline.sh"
ws_stage_selective_hunk "$TASKS_MD" "$TARGET_ID" >/dev/null 2>&1 || true

# Audit JSONL append.
# shellcheck source=../lib/audit.sh
source "$LIB_DIR/audit.sh"
args_hash="$(audit_args_hash "$TARGET_ID" "$TARGET_PHASE" "${MOVE_REASON:-}")"
audit_append "tasks move" "$args_hash" reversible success 0 0 || true

if [[ "$OUTPUT_MODE" == "json" ]]; then
    data="$(jq -n --arg id "$TARGET_ID" --arg phase "$TARGET_PHASE" \
        --arg before "$current_status" --arg after "$new_status" \
        '{task_id: $id, target_phase: $phase, status_before: $before, status_after: $after}')"
    output_emit_json "$data"
else
    if [[ "$new_status" != "$current_status" ]]; then
        printf 'moved: %s · %s → %s (target-phase %s)\n' "$TARGET_ID" "$current_status" "$new_status" "$TARGET_PHASE"
    else
        printf 'no-op: %s already %s (target-phase %s)\n' "$TARGET_ID" "$current_status" "$TARGET_PHASE"
    fi
fi
