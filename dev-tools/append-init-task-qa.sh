#!/usr/bin/env bash
# append-init-task-qa.sh — atomic Q&A round-trip append to init-task file.
#
# Source-of-truth contract: skills/init-task-persistence.md § Q&A round-trip
# contract. Six pipeline commands invoke this utility at the "APPEND Q&A IF
# ANY" step (/dr-prd, /dr-plan, /dr-design, /dr-do, /dr-qa, /dr-compliance).
#
# Security mandate § S1: all free-form textual inputs come via `--*-file
# <path>` so operator answers containing quotes / backticks / $(…) cannot
# expand at shell layer. Summary stays literal (single one-line slug used
# verbatim with `printf '%s'`, no eval).
#
# Atomic write: mkdir-based per-task lock (macOS-portable, no flock
# assumption) + temp-file + `mv` into place. Parallel callers on the same
# task ID serialize on the lock; their blocks land in the order they
# acquired it, never half-written.
#
# Exit codes:
#   0 — Q&A block appended successfully
#   1 — validation / I/O error
#   2 — usage error

set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="append-init-task-qa.sh"

ROOT=""
TASK_ID=""
STAGE=""
ROUND=""
QUESTION_FILE=""
ANSWER_FILE=""
DECIDED_BY=""
RATIONALE_FILE=""
SUMMARY=""
CONFLICT_WITH=""
CONFLICT_DETAIL_FILE=""
TIMESTAMP=""
ASKED_BY="agent"

MAX_INPUT_BYTES="${DATARIM_QA_MAX_INPUT_BYTES:-102400}"
LOCK_TIMEOUT_SECONDS="${DATARIM_QA_LOCK_TIMEOUT:-5}"

LOCK_DIR=""
TMP_FILE=""

cleanup() {
    if [ -n "$TMP_FILE" ] && [ -e "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"
    fi
    if [ -n "$LOCK_DIR" ] && [ -d "$LOCK_DIR" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME --root <path> --task <ID> --stage <stage> --round <N> \\
               --question-file <path> --answer-file <path> \\
               --decided-by <operator|agent> [--rationale-file <path>] \\
               --summary "<one-line>" \\
               [--asked-by "<agent role>"] \\
               [--conflict-with <wish_id>] [--conflict-detail-file <path>] \\
               [--timestamp <ISO-8601>]

Allowed --stage values: prd | plan | design | do | qa | compliance.
Allowed --decided-by values: operator | agent.

Required when --decided-by is agent: --rationale-file (body >= 50 chars).

Environment:
  DATARIM_QA_MAX_INPUT_BYTES   per-file size cap (default 102400 bytes)
  DATARIM_QA_LOCK_TIMEOUT      lock-acquire timeout in seconds (default 5)

Exit codes:
  0   appended successfully
  1   validation / IO error
  2   usage error
EOF
}

fail_usage() { echo "ERROR: $1" >&2; usage >&2; exit 2; }
fail_io()    { echo "ERROR: $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --root)                 shift; ROOT="${1:-}";;
        --task)                 shift; TASK_ID="${1:-}";;
        --stage)                shift; STAGE="${1:-}";;
        --round)                shift; ROUND="${1:-}";;
        --question-file)        shift; QUESTION_FILE="${1:-}";;
        --answer-file)          shift; ANSWER_FILE="${1:-}";;
        --decided-by)           shift; DECIDED_BY="${1:-}";;
        --rationale-file)       shift; RATIONALE_FILE="${1:-}";;
        --summary)              shift; SUMMARY="${1:-}";;
        --asked-by)             shift; ASKED_BY="${1:-agent}";;
        --conflict-with)        shift; CONFLICT_WITH="${1:-}";;
        --conflict-detail-file) shift; CONFLICT_DETAIL_FILE="${1:-}";;
        --timestamp)            shift; TIMESTAMP="${1:-}";;
        --help|-h)              usage; exit 0;;
        --version)              echo "$SCRIPT_NAME $VERSION"; exit 0;;
        *)                      fail_usage "unknown argument: $1";;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Required-arg + shape validation (usage errors → exit 2)
# ---------------------------------------------------------------------------
[ -z "$ROOT" ]          && ROOT="$(pwd)"
[ -z "$TASK_ID" ]       && fail_usage "--task is required"
[ -z "$STAGE" ]         && fail_usage "--stage is required"
[ -z "$ROUND" ]         && fail_usage "--round is required"
[ -z "$QUESTION_FILE" ] && fail_usage "--question-file is required"
[ -z "$ANSWER_FILE" ]   && fail_usage "--answer-file is required"
[ -z "$DECIDED_BY" ]    && fail_usage "--decided-by is required"
[ -z "$SUMMARY" ]       && fail_usage "--summary is required"

if ! [[ "$TASK_ID" =~ ^[A-Z]{2,10}-[0-9]{4}$ ]]; then
    fail_usage "--task must match {PREFIX-NNNN}, got '$TASK_ID'"
fi

case "$STAGE" in
    prd|plan|design|do|qa|compliance) ;;
    *) fail_usage "--stage must be one of {prd, plan, design, do, qa, compliance}, got '$STAGE'";;
esac

if ! [[ "$ROUND" =~ ^[0-9]+$ ]]; then
    fail_usage "--round must be a non-negative integer, got '$ROUND'"
fi

case "$DECIDED_BY" in
    operator|agent) ;;
    *) fail_usage "--decided-by must be 'operator' or 'agent', got '$DECIDED_BY'";;
esac

if [ -n "$CONFLICT_WITH" ]; then
    if ! [[ "$CONFLICT_WITH" =~ ^[A-Za-zА-Яа-я0-9_\-]+$ ]]; then
        fail_usage "--conflict-with must be a slug ([A-Za-zА-Яа-я0-9_-]+), got '$CONFLICT_WITH'"
    fi
fi

# ---------------------------------------------------------------------------
# Path resolution + boundary check (IO errors → exit 1)
# ---------------------------------------------------------------------------
TASKS_DIR="$ROOT/datarim/tasks"
[ -d "$TASKS_DIR" ] || fail_io "tasks directory not found: $TASKS_DIR"

TASKS_DIR_ABS="$(cd "$TASKS_DIR" && pwd -P)"
INIT_FILE="$TASKS_DIR/${TASK_ID}-init-task.md"
[ -f "$INIT_FILE" ] || fail_io "init-task file does not exist: $INIT_FILE"

INIT_DIR_ABS="$(cd "$(dirname "$INIT_FILE")" && pwd -P)"
case "$INIT_DIR_ABS" in
    "$TASKS_DIR_ABS") ;;
    *) fail_io "init-task path resolves outside tasks directory: $INIT_DIR_ABS";;
esac

# ---------------------------------------------------------------------------
# Input file validation: existence + size cap
# ---------------------------------------------------------------------------
check_input_file() {
    local label="$1" path="$2"
    [ -n "$path" ] || return 0
    [ -f "$path" ] || fail_io "--$label points to non-existent file: $path"
    local size
    size=$(wc -c < "$path" | tr -d ' ')
    if [ "$size" -gt "$MAX_INPUT_BYTES" ]; then
        fail_io "--$label size ${size}B exceeds cap ${MAX_INPUT_BYTES}B (DATARIM_QA_MAX_INPUT_BYTES) — input too large"
    fi
}

check_input_file question-file "$QUESTION_FILE"
check_input_file answer-file "$ANSWER_FILE"
check_input_file rationale-file "$RATIONALE_FILE"
check_input_file conflict-detail-file "$CONFLICT_DETAIL_FILE"

if [ "$DECIDED_BY" = "agent" ] && [ -z "$RATIONALE_FILE" ]; then
    fail_io "--decided-by agent requires --rationale-file (body >= 50 chars)"
fi

# ---------------------------------------------------------------------------
# Lock acquisition (mkdir-based, macOS-portable)
# ---------------------------------------------------------------------------
LOCK_DIR="$TASKS_DIR_ABS/.${TASK_ID}.qa-lock"
deadline=$(( $(date +%s) + LOCK_TIMEOUT_SECONDS ))
acquired=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        acquired=1
        break
    fi
    sleep 0.1
done
if [ "$acquired" -ne 1 ]; then
    LOCK_DIR=""
    fail_io "failed to acquire lock for $TASK_ID within ${LOCK_TIMEOUT_SECONDS}s"
fi

# ---------------------------------------------------------------------------
# Timestamp default + composition
# ---------------------------------------------------------------------------
if [ -z "$TIMESTAMP" ]; then
    TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

TMP_FILE="$(mktemp "$TASKS_DIR_ABS/.${TASK_ID}.qa.append.XXXXXX")"

{
    cat "$INIT_FILE"
    printf '\n### %s — Q&A by /dr-%s (round %s)\n\n' "$TIMESTAMP" "$STAGE" "$ROUND"
    printf '**Question (verbatim, asked by %s):**\n\n' "$ASKED_BY"
    printf '%s\n\n' "$(cat "$QUESTION_FILE")"
    printf '**Answer (verbatim, by %s):**\n\n' "$DECIDED_BY"
    printf '%s\n\n' "$(cat "$ANSWER_FILE")"
    printf '**Decided by:** %s\n\n' "$DECIDED_BY"
    if [ -n "$RATIONALE_FILE" ]; then
        printf '**Decision rationale:**\n\n'
        printf '%s\n\n' "$(cat "$RATIONALE_FILE")"
    fi
    printf '**Summary (how it changes initial conditions):**\n\n'
    printf '%s\n\n' "$SUMMARY"
    if [ -n "$CONFLICT_WITH" ]; then
        if [ -n "$CONFLICT_DETAIL_FILE" ]; then
            printf '**Conflict with existing wish:** %s — %s\n\n' \
                "$CONFLICT_WITH" "$(cat "$CONFLICT_DETAIL_FILE")"
        else
            printf '**Conflict with existing wish:** %s — (see Summary)\n\n' "$CONFLICT_WITH"
        fi
    else
        printf '**Conflict with existing wish:** none\n\n'
    fi
} > "$TMP_FILE"

mv -f "$TMP_FILE" "$INIT_FILE"
TMP_FILE=""

exit 0
