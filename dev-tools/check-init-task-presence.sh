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
