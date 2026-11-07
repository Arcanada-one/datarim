#!/usr/bin/env bash
# append-init-task-qa.sh — atomic Q&A round-trip append to init-task file.
#
# Source-of-truth contract: skills/init-task-persistence/SKILL.md § Q&A round-trip
# contract. Six pipeline commands invoke this utility at the "APPEND Q&A IF
# ANY" step (/dr-prd, /dr-plan, /dr-design, /dr-do, /dr-qa, /dr-compliance).
#
# Security mandate § S1: all free-form textual inputs come via `--*-file
# <path>` so operator answers containing quotes / backticks / $(…) cannot
# expand at shell layer. Summary stays literal (single one-line slug used
# verbatim with `printf '%s'`, no eval).
#
# Atomic write: per-task lock + temp-file + `mv` into place. Prefer
# flock on `datarim/tasks/.{TASK-ID}.qa-lock` (skill contract; Linux CI).
# Fall back to mkdir on the same `.{TASK-ID}.qa-lock` path when flock is
# absent (macOS). Parallel callers on the same task ID serialize on the
# lock; their blocks land in the order they acquired it, never
# half-written / lost-updated.
#
# Exit codes:
#   0 — Q&A block appended successfully
#   1 — validation / I/O error
#   2 — usage error

set -euo pipefail
IFS=$'\n\t'

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
LOCK_FILE=""
TMP_FILE=""

cleanup() {
    # Command-substitution subshells must not release a parent-held lock.
    if [ "${BASH_SUBSHELL:-0}" -ne 0 ]; then
        return 0
    fi
    if [ -n "$TMP_FILE" ] && [ -e "$TMP_FILE" ]; then
        rm -f "$TMP_FILE" || true
    fi
    # mkdir-fallback only. flock unlocks when FD 9 closes; keep the lockfile
    # inode (do not rm) so a waiter that already opened the path cannot race.
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
               --decided-by <operator|agent|process-rule-artefact> [--rationale-file <path>] \\
               --summary "<one-line>" \\
               [--asked-by "<agent role>"] \\
               [--conflict-with <wish_id>] [--conflict-detail-file <path>] \\
               [--timestamp <ISO-8601>]

Allowed --stage values: prd | plan | design | do | qa | compliance.
Allowed --decided-by values: operator | agent | process-rule-artefact.

Required when --decided-by is agent: --rationale-file (body >= 50 chars).
Required when --decided-by is process-rule-artefact: --rationale-file
  enumerating at least one persisted-artefact path token (e.g. AGENTS.md,
  feedback_*.md, mandates/*.md, ~/.claude/...). No 50-char floor.

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

line_has_control() {
    local value="$1" grep_status
    case "$value" in
        *$'\n'*|*$'\r'*) return 0 ;;
    esac
    if ( set +o pipefail; printf '%s' "$value" | LC_ALL=C grep -q '[[:cntrl:]]' 2>/dev/null ); then
        return 0
    else
        grep_status=$?
    fi
    if [ "$grep_status" -ne 1 ]; then
        return "$grep_status"
    fi
    if ( set +o pipefail; printf '%s' "$value" | LC_ALL=C grep -q $'\xc2[\x80-\x9f]' 2>/dev/null ); then
        return 0
    else
        grep_status=$?
    fi
    if [ "$grep_status" -ne 1 ]; then
        return "$grep_status"
    fi
    return 1
}

check_one_line_field() {
    local option="$1" value="$2" guard_status
    if line_has_control "$value"; then
        fail_usage "$option must be one line without control characters"
    else
        guard_status=$?
    fi
    if [ "$guard_status" -ne 1 ]; then
        fail_io "failed to inspect $option for control characters"
    fi
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ "$#" -ge 2 ] || fail_usage "--root requires a value"
            shift; ROOT="${1:-}";;
        --task)
            [ "$#" -ge 2 ] || fail_usage "--task requires a value"
            shift; TASK_ID="${1:-}";;
        --stage)
            [ "$#" -ge 2 ] || fail_usage "--stage requires a value"
            shift; STAGE="${1:-}";;
        --round)
            [ "$#" -ge 2 ] || fail_usage "--round requires a value"
            shift; ROUND="${1:-}";;
        --question-file)
            [ "$#" -ge 2 ] || fail_usage "--question-file requires a value"
            shift; QUESTION_FILE="${1:-}";;
        --answer-file)
            [ "$#" -ge 2 ] || fail_usage "--answer-file requires a value"
            shift; ANSWER_FILE="${1:-}";;
        --decided-by)
            [ "$#" -ge 2 ] || fail_usage "--decided-by requires a value"
            shift; DECIDED_BY="${1:-}";;
        --rationale-file)
            [ "$#" -ge 2 ] || fail_usage "--rationale-file requires a value"
            shift; RATIONALE_FILE="${1:-}";;
        --summary)
            [ "$#" -ge 2 ] || fail_usage "--summary requires a value"
            shift; SUMMARY="${1:-}";;
        --asked-by)
            [ "$#" -ge 2 ] || fail_usage "--asked-by requires a value"
            shift; ASKED_BY="${1:-agent}";;
        --conflict-with)
            [ "$#" -ge 2 ] || fail_usage "--conflict-with requires a value"
            shift; CONFLICT_WITH="${1:-}";;
        --conflict-detail-file)
            [ "$#" -ge 2 ] || fail_usage "--conflict-detail-file requires a value"
            shift; CONFLICT_DETAIL_FILE="${1:-}";;
        --timestamp)
            [ "$#" -ge 2 ] || fail_usage "--timestamp requires a value"
            shift; TIMESTAMP="${1:-}";;
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

if ! [[ "$TASK_ID" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}(-[A-Za-z0-9]+)*$ ]]; then
    fail_usage "--task must match {PREFIX-NNNN} or compound {PREFIX-NNNN-suffix...}, got '$TASK_ID'"
fi

case "$STAGE" in
    prd|plan|design|do|qa|compliance) ;;
    *) fail_usage "--stage must be one of {prd, plan, design, do, qa, compliance}, got '$STAGE'";;
esac

if ! [[ "$ROUND" =~ ^[0-9]+$ ]]; then
    fail_usage "--round must be a non-negative integer, got '$ROUND'"
fi

case "$DECIDED_BY" in
    operator|agent|process-rule-artefact) ;;
    *) fail_usage "--decided-by must be 'operator', 'agent', or 'process-rule-artefact', got '$DECIDED_BY'";;
esac

if [ -n "$CONFLICT_WITH" ]; then
    if ! [[ "$CONFLICT_WITH" =~ ^[A-Za-zА-Яа-я0-9_\-]+$ ]]; then
        fail_usage "--conflict-with must be a slug ([A-Za-zА-Яа-я0-9_-]+), got '$CONFLICT_WITH'"
    fi
fi

# These values are written as single logical lines in the init-task Markdown.
check_one_line_field --summary "$SUMMARY"
check_one_line_field --asked-by "$ASKED_BY"
check_one_line_field --timestamp "$TIMESTAMP"

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

if [ "$DECIDED_BY" = "process-rule-artefact" ]; then
    [ -n "$RATIONALE_FILE" ] || fail_io "process-rule-artefact requires --rationale-file enumerating artefact paths"
    if ! grep -qE '(\.md\b|\.txt\b|/|~/|CLAUDE)' "$RATIONALE_FILE"; then
        fail_io "process-rule-artefact rationale must contain at least one artefact path (e.g. AGENTS.md, feedback_*.md, ~/.claude/...)"
    fi
fi

# ---------------------------------------------------------------------------
# Lock acquisition — flock first (skill contract), mkdir fallback otherwise
# ---------------------------------------------------------------------------
# IMPORTANT: never point LOCK_DIR at a path until THIS process owns it.
# A waiter that sets LOCK_DIR before mkdir can rmdir another holder's lock
# from EXIT cleanup (lost-update under parallel P2.5).
LOCK_FILE="$TASKS_DIR_ABS/.${TASK_ID}.qa-lock"
acquired=0

if command -v flock >/dev/null 2>&1; then
    # Stale mkdir-style directory from older builds must not block flock open.
    if [ -d "$LOCK_FILE" ]; then
        rmdir "$LOCK_FILE" 2>/dev/null \
            || fail_io "stale directory lock blocks $LOCK_FILE (remove empty .qa-lock dir)"
    fi
    exec 9>"$LOCK_FILE" || fail_io "cannot open lock file: $LOCK_FILE"
    if flock -w "$LOCK_TIMEOUT_SECONDS" 9; then
        acquired=1
    else
        exec 9>&- 2>/dev/null || true
        fail_io "failed to acquire lock for $TASK_ID within ${LOCK_TIMEOUT_SECONDS}s"
    fi
else
    # mkdir fallback: assign LOCK_DIR only AFTER this process owns the dir.
    if [ -f "$LOCK_FILE" ] && [ ! -d "$LOCK_FILE" ]; then
        fail_io "stale flock lockfile blocks mkdir fallback at $LOCK_FILE"
    fi
    lock_dir_path="$LOCK_FILE"
    deadline=$(( $(date +%s) + LOCK_TIMEOUT_SECONDS ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if mkdir "$lock_dir_path" 2>/dev/null; then
            LOCK_DIR="$lock_dir_path"
            acquired=1
            break
        fi
        sleep 0.1
    done
    if [ "$acquired" -ne 1 ]; then
        fail_io "failed to acquire lock for $TASK_ID within ${LOCK_TIMEOUT_SECONDS}s"
    fi
fi

# ---------------------------------------------------------------------------
# Timestamp default + composition
# ---------------------------------------------------------------------------
if [ -z "$TIMESTAMP" ]; then
    TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

TMP_FILE="$(mktemp "$TASKS_DIR_ABS/.${TASK_ID}.qa.append.XXXXXX")"

if ! QUESTION_CONTENT="$(cat "$QUESTION_FILE")"; then
    fail_io "failed to read --question-file: $QUESTION_FILE"
fi
if ! ANSWER_CONTENT="$(cat "$ANSWER_FILE")"; then
    fail_io "failed to read --answer-file: $ANSWER_FILE"
fi
RATIONALE_CONTENT=""
if [ -n "$RATIONALE_FILE" ] && ! RATIONALE_CONTENT="$(cat "$RATIONALE_FILE")"; then
    fail_io "failed to read --rationale-file: $RATIONALE_FILE"
fi
CONFLICT_DETAIL_CONTENT=""
if [ -n "$CONFLICT_DETAIL_FILE" ] && ! CONFLICT_DETAIL_CONTENT="$(cat "$CONFLICT_DETAIL_FILE")"; then
    fail_io "failed to read --conflict-detail-file: $CONFLICT_DETAIL_FILE"
fi

{
    if ! cat "$INIT_FILE"; then
        fail_io "failed to read init-task file: $INIT_FILE"
    fi
    printf '\n### %s — Q&A by /dr-%s (round %s)\n\n' "$TIMESTAMP" "$STAGE" "$ROUND"
    printf '**Question (verbatim, asked by %s):**\n\n' "$ASKED_BY"
    printf '%s\n\n' "$QUESTION_CONTENT"
    printf '**Answer (verbatim, by %s):**\n\n' "$DECIDED_BY"
    printf '%s\n\n' "$ANSWER_CONTENT"
    printf '**Decided by:** %s\n\n' "$DECIDED_BY"
    if [ -n "$RATIONALE_FILE" ]; then
        if [ "$DECIDED_BY" = "process-rule-artefact" ]; then
            printf '**Process-rule artefacts:**\n\n'
        else
            printf '**Decision rationale:**\n\n'
        fi
        printf '%s\n\n' "$RATIONALE_CONTENT"
    fi
    printf '**Summary (how it changes initial conditions):**\n\n'
    printf '%s\n\n' "$SUMMARY"
    if [ -n "$CONFLICT_WITH" ]; then
        if [ -n "$CONFLICT_DETAIL_FILE" ]; then
            printf '**Conflict with existing wish:** %s — %s\n\n' \
                "$CONFLICT_WITH" "$CONFLICT_DETAIL_CONTENT"
        else
            printf '**Conflict with existing wish:** %s — (see Summary)\n\n' "$CONFLICT_WITH"
        fi
    else
        printf '**Conflict with existing wish:** none\n\n'
    fi
} > "$TMP_FILE"

if ! mv -f "$TMP_FILE" "$INIT_FILE"; then
    fail_io "failed to replace init-task file: $INIT_FILE"
fi
TMP_FILE=""

exit 0
