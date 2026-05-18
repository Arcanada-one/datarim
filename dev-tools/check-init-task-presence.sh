#!/usr/bin/env bash
# check-init-task-presence.sh — init-task artifact validator (F1).
#
# Validates the existence and structural shape of `datarim/tasks/{ID}-init-task.md`
# files produced by `/dr-init` Step 2.6. Two modes:
#
#   --task <ID>   — validate one specific init-task file:
#                     * required frontmatter fields
#                     * mandatory headings (`## Operator brief (verbatim)`,
#                       `## Append-log (operator amendments)`)
#                   Exit 0 = OK, 1 = malformed/missing, 2 = usage error.
#
#   --all         — scan `datarim/tasks/*-task-description.md` and emit a finding
#                   for every task whose init-task is missing. Per-task soft window:
#                     * task created < 30 days ago  → severity `info`
#                     * task created >= 30 days ago → severity `warn`
#                   `status: archived` and `legacy: true` markers suppress findings.
#                   Exit code is **always 0** in `--all` mode — findings are
#                   advisory (never block CI/pre-commit).
#
# Source-of-truth contract: skills/init-task-persistence.md.
#
# Exit codes:
#   0 — clean (or only advisory findings in --all mode)
#   1 — single-task validation failed (--task mode only)
#   2 — usage error / internal error
#
set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="check-init-task-presence.sh"

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME --task <TASK-ID> [--root <path>] [--report]
  $SCRIPT_NAME --all            [--root <path>] [--today YYYY-MM-DD]

Options:
  --task <ID>          Validate one init-task file (exit 0/1).
  --all                Scan all task-descriptions, advisory findings (exit 0).
  --root <path>        Repository root containing datarim/ (default: pwd).
  --report             Human-readable detail output (single-task mode).
  --today YYYY-MM-DD   Override today's date for soft-window tests.
  --help               Show this help and exit 0.
  --version            Print version and exit 0.

Exit codes:
  0   OK (or only advisory findings in --all mode)
  1   single-task validation failed
  2   usage / internal error
EOF
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
MODE=""
TASK_ID=""
ROOT=""
REPORT=0
TODAY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --task)
            MODE="task"
            shift
            TASK_ID="${1:-}"
            [ -z "$TASK_ID" ] && { echo "ERROR: --task requires a TASK-ID" >&2; exit 2; }
            ;;
        --all)
            MODE="all"
            ;;
        --root)
            shift
            ROOT="${1:-}"
            ;;
        --report)
            REPORT=1
            ;;
        --today)
            shift
            TODAY="${1:-}"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --version)
            echo "$SCRIPT_NAME $VERSION"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

[ -z "$MODE" ] && { echo "ERROR: one of --task or --all is required" >&2; exit 2; }
[ -z "$ROOT" ] && ROOT="$(pwd)"
[ -z "$TODAY" ] && TODAY="$(date +%Y-%m-%d)"

TASKS_DIR="$ROOT/datarim/tasks"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# extract_frontmatter_field <file> <field-name>
# Prints the field value (everything after "field: ") or empty string.
extract_frontmatter_field() {
    local file="$1" field="$2"
    awk -v key="$field" '
        /^---$/ { if (in_fm) exit; in_fm=1; next }
        in_fm {
            if (match($0, "^" key ":[ \t]*")) {
                print substr($0, RLENGTH + 1)
                exit
            }
        }
    ' "$file"
}

# days_between <YYYY-MM-DD-from> <YYYY-MM-DD-to>
# Prints absolute integer day count. Requires GNU or BSD date; falls back
# to a portable yyyy-mm-dd-to-julian via awk if neither supports the input.
days_between() {
    local from="$1" to="$2"
    # Try BSD date first (macOS default).
    local from_epoch to_epoch
    from_epoch=$(date -j -f "%Y-%m-%d" "$from" +%s 2>/dev/null || true)
    to_epoch=$(date -j -f "%Y-%m-%d" "$to" +%s 2>/dev/null || true)
    if [ -z "$from_epoch" ] || [ -z "$to_epoch" ]; then
        # Try GNU date (linux).
        from_epoch=$(date -d "$from" +%s 2>/dev/null || echo "")
        to_epoch=$(date -d "$to" +%s 2>/dev/null || echo "")
    fi
    if [ -z "$from_epoch" ] || [ -z "$to_epoch" ]; then
        # Portable awk julian fallback (Fliegel & Van Flandern).
        awk -v f="$from" -v t="$to" '
            function jd(s,    y,m,d,a) {
                split(s, a, "-")
                y=a[1]+0; m=a[2]+0; d=a[3]+0
                return d - 32075 + int(1461*(y+4800+int((m-14)/12))/4) \
                    + int(367*(m-2-int((m-14)/12)*12)/12) \
                    - int(3*int((y+4900+int((m-14)/12))/100)/4)
            }
            BEGIN { diff = jd(t) - jd(f); if (diff < 0) diff = -diff; print diff }
        '
        return
    fi
    local diff=$(( to_epoch - from_epoch ))
    [ "$diff" -lt 0 ] && diff=$(( -diff ))
    echo $(( diff / 86400 ))
}

# ---------------------------------------------------------------------------
# Single-task validator
# ---------------------------------------------------------------------------

validate_single_task() {
    local id="$1"
    local file="$TASKS_DIR/${id}-init-task.md"

    if [ ! -f "$file" ]; then
        echo "ERROR: init-task file missing for $id (expected $file)" >&2
        if [ "$REPORT" -eq 1 ]; then
            echo "  Run /dr-init {DESCRIPTION} to create the task properly, or backfill"
            echo "  $file manually with frontmatter (task_id, artifact: init-task,"
            echo "  schema_version: 1, captured_at, captured_by, operator, status)"
            echo "  and the two required headings."
        fi
        return 1
    fi

    local errors=0

    # --- Required frontmatter fields ---------------------------------------
    local field val
    for field in task_id artifact schema_version captured_at captured_by operator status; do
        val=$(extract_frontmatter_field "$file" "$field")
        if [ -z "$val" ]; then
            echo "ERROR: $file: frontmatter missing required field '$field'" >&2
            errors=$(( errors + 1 ))
        fi
    done

    # `artifact:` MUST be literal `init-task`.
    val=$(extract_frontmatter_field "$file" "artifact")
    if [ -n "$val" ] && [ "$val" != "init-task" ]; then
        echo "ERROR: $file: frontmatter artifact must be 'init-task', got '$val'" >&2
        errors=$(( errors + 1 ))
    fi

    # `schema_version:` MUST be literal `1`.
    val=$(extract_frontmatter_field "$file" "schema_version")
    if [ -n "$val" ] && [ "$val" != "1" ]; then
        echo "ERROR: $file: frontmatter schema_version must be '1', got '$val'" >&2
        errors=$(( errors + 1 ))
    fi

    # task_id MUST match {PREFIX-NNNN} pattern.
    val=$(extract_frontmatter_field "$file" "task_id")
    if [ -n "$val" ] && ! [[ "$val" =~ ^[A-Z]{2,10}-[0-9]{4}$ ]]; then
        echo "ERROR: $file: frontmatter task_id '$val' does not match {PREFIX-NNNN}" >&2
        errors=$(( errors + 1 ))
    fi

    # --- Required headings -------------------------------------------------
    if ! grep -q '^## Operator brief (verbatim)' "$file"; then
        echo "ERROR: $file: missing required heading '## Operator brief (verbatim)'" >&2
        errors=$(( errors + 1 ))
    fi
    if ! grep -q '^## Append-log' "$file"; then
        echo "ERROR: $file: missing required heading '## Append-log (operator amendments)'" >&2
        errors=$(( errors + 1 ))
    fi

    # --- Q&A round-trip blocks (TUNE-0216) ---------------------------------
    # Contract: skills/init-task-persistence.md § Q&A round-trip contract.
    local qa_errors
    qa_errors=$(validate_qa_blocks "$file") || true
    if [ -n "$qa_errors" ]; then
        printf '%s\n' "$qa_errors" >&2
        # Each line in qa_errors is one finding.
        errors=$(( errors + $(printf '%s\n' "$qa_errors" | grep -c .) ))
    fi

    if [ "$errors" -gt 0 ]; then
        if [ "$REPORT" -eq 1 ]; then
            echo "  $errors validation error(s) — see canonical contract in"
            echo "  skills/init-task-persistence.md § Artifact Schema."
        fi
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Q&A block validator (TUNE-0216)
# ---------------------------------------------------------------------------
#
# Walks the file looking for Q&A block headings of the form
#   ### <ISO> — Q&A by /dr-<stage> (round <N>)
# For each block (delimited by the next `### ` heading or EOF) it asserts:
#   1. All five mandatory subheadings present (Question, Answer, Decided by,
#      Summary, Conflict with existing wish).
#   2. `Decided by:` value ∈ {operator, agent}.
#   3. When `Decided by: agent` — `Decision rationale:` subheading present
#      and its body has >= 50 non-whitespace characters.
#
# Emits one line per finding on stdout; empty output = clean. The caller
# routes the lines to stderr and counts them.
validate_qa_blocks() {
    local file="$1"
    awk '
        function trim(s) {
            sub(/^[ \t\r\n]+/, "", s)
            sub(/[ \t\r\n]+$/, "", s)
            return s
        }
        function reset_block() {
            in_block = 1
            cur_heading = $0
            has_question = 0
            has_answer = 0
            has_decided_by = 0
            decided_by_val = ""
            has_summary = 0
            has_conflict = 0
            has_rationale = 0
            rationale_chars = 0
            in_rationale_body = 0
        }
        function emit_findings() {
            if (!in_block) return
            if (!has_question) {
                printf("ERROR: %s: Q&A block %q missing **Question (verbatim, asked by …):** subheading\n",
                    FILE, cur_heading)
            }
            if (!has_answer) {
                printf("ERROR: %s: Q&A block %q missing **Answer (verbatim, by …):** subheading\n",
                    FILE, cur_heading)
            }
            if (!has_decided_by) {
                printf("ERROR: %s: Q&A block %q missing **Decided by:** subheading\n",
                    FILE, cur_heading)
            } else if (decided_by_val != "operator" && decided_by_val != "agent") {
                printf("ERROR: %s: Q&A block %q has invalid Decided by value %q (must be operator or agent)\n",
                    FILE, cur_heading, decided_by_val)
            }
            if (!has_summary) {
                printf("ERROR: %s: Q&A block %q missing **Summary (how it changes initial conditions):** subheading\n",
                    FILE, cur_heading)
            }
            if (!has_conflict) {
                printf("ERROR: %s: Q&A block %q missing **Conflict with existing wish:** subheading\n",
                    FILE, cur_heading)
            }
            if (decided_by_val == "agent") {
                if (!has_rationale) {
                    printf("ERROR: %s: Q&A block %q with Decided by: agent missing **Decision rationale:** subheading\n",
                        FILE, cur_heading)
                } else if (rationale_chars < 50) {
                    printf("ERROR: %s: Q&A block %q Decision rationale has %d non-whitespace characters; minimum is 50\n",
                        FILE, cur_heading, rationale_chars)
                }
            }
        }
        BEGIN {
            in_block = 0
        }
        # Detect a Q&A block heading.
        /^### .+ — Q&A by \/dr-[a-z-]+ \(round [0-9]+\)$/ {
            emit_findings()
            reset_block()
            next
        }
        # Any other `### ` heading closes the current block.
        /^### / {
            emit_findings()
            in_block = 0
            in_rationale_body = 0
            next
        }
        in_block {
            line = $0
            stripped = line
            sub(/^[ \t]+/, "", stripped)
            if (stripped ~ /^\*\*Question \(verbatim/) {
                has_question = 1
                in_rationale_body = 0
                next
            }
            if (stripped ~ /^\*\*Answer \(verbatim/) {
                has_answer = 1
                in_rationale_body = 0
                next
            }
            if (stripped ~ /^\*\*Decided by:\*\*/) {
                has_decided_by = 1
                value = stripped
                sub(/^\*\*Decided by:\*\*[ \t]*/, "", value)
                decided_by_val = trim(value)
                in_rationale_body = 0
                next
            }
            if (stripped ~ /^\*\*Decision rationale:\*\*/) {
                has_rationale = 1
                in_rationale_body = 1
                inline = stripped
                sub(/^\*\*Decision rationale:\*\*[ \t]*/, "", inline)
                gsub(/[ \t]/, "", inline)
                rationale_chars += length(inline)
                next
            }
            if (stripped ~ /^\*\*Summary \(how it changes/) {
                has_summary = 1
                in_rationale_body = 0
                next
            }
            if (stripped ~ /^\*\*Conflict with existing wish:\*\*/) {
                has_conflict = 1
                in_rationale_body = 0
                next
            }
            # While inside the rationale body, accumulate non-whitespace chars
            # until a blank line or the next bold-prefixed subheading line.
            if (in_rationale_body) {
                if (stripped ~ /^\*\*/) {
                    in_rationale_body = 0
                } else if (stripped == "") {
                    # Empty line — body continues but no chars to count.
                } else {
                    chars = stripped
                    gsub(/[ \t]/, "", chars)
                    rationale_chars += length(chars)
                }
            }
        }
        END {
            emit_findings()
        }
    ' FILE="$file" "$file"
}

# ---------------------------------------------------------------------------
# Multi-task scan (advisory, exit-0)
# ---------------------------------------------------------------------------

scan_all_tasks() {
    if [ ! -d "$TASKS_DIR" ]; then
        # No tasks/ directory → nothing to scan.
        return 0
    fi

    local desc init_file id status legacy created age severity
    shopt -s nullglob
    for desc in "$TASKS_DIR"/*-task-description.md; do
        id="$(basename "$desc")"
        id="${id%-task-description.md}"
        init_file="$TASKS_DIR/${id}-init-task.md"
        [ -f "$init_file" ] && continue

        status=$(extract_frontmatter_field "$desc" "status")
        if [ "$status" = "archived" ] || [ "$status" = "completed" ] || [ "$status" = "cancelled" ]; then
            continue
        fi

        legacy=$(extract_frontmatter_field "$desc" "legacy")
        if [ "$legacy" = "true" ]; then
            continue
        fi

        created=$(extract_frontmatter_field "$desc" "created")
        if [ -z "$created" ]; then
            # Without a creation date we cannot decide severity; report as info.
            echo "info: $id init-task missing (no 'created' date in description)"
            continue
        fi

        age=$(days_between "$created" "$TODAY")
        if [ "$age" -lt 30 ]; then
            severity="info"
        else
            severity="warn"
        fi
        echo "$severity: $id init-task missing (task age ${age}d; rolling 30d soft window)"
    done
    shopt -u nullglob
    return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$MODE" in
    task)
        validate_single_task "$TASK_ID"
        exit $?
        ;;
    all)
        scan_all_tasks
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
