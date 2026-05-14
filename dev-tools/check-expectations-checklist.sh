#!/usr/bin/env bash
# check-expectations-checklist.sh — expectations checklist validator (F2/F3).
#
# Validates the structural shape of `datarim/tasks/{ID}-expectations.md` files
# produced at `/dr-prd` (L3+) or `/dr-plan` (L2 without PRD) and consumed at
# `/dr-qa`, `/dr-compliance`, `/dr-archive`. Three modes:
#
#   --task <ID>     — structural validation of a single expectations file
#                     (frontmatter shape, '## Ожидания' heading, per-item
#                     wish_id/status/История format).
#                     Exit 0 = OK, 1 = malformed/missing, 2 = usage error.
#
#   --verify <ID>   — verify-routing mode for QA/COMPLIANCE/ARCHIVE: read the
#                     file's per-item Текущий статус and override values, then
#                     emit a verdict on stdout:
#                       PASS              — every item is met/n-a/pending/deleted
#                       CONDITIONAL_PASS  — partial/missed items all carry an
#                                            operator override (≥10 chars)
#                       BLOCKED           — ≥1 partial/missed item without
#                                            a valid override; CTA emits
#                                            `/dr-do {ID} --focus-items <wish_ids>`
#                     Exit 0 = PASS / CONDITIONAL_PASS, 1 = BLOCKED or malformed,
#                     2 = usage error.
#
#   --all           — scan task-descriptions and emit advisory findings for
#                     L3+ tasks that lack an expectations file. Severity
#                     ladder: info (<30d) → warn (≥30d). Exit code is always 0.
#
# Source-of-truth contract: skills/expectations-checklist.md.
#
set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="check-expectations-checklist.sh"

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME --task   <TASK-ID> [--root <path>] [--report]
  $SCRIPT_NAME --verify <TASK-ID> [--root <path>]
  $SCRIPT_NAME --all              [--root <path>] [--today YYYY-MM-DD]

Options:
  --task <ID>          Structural validation of one expectations file (exit 0/1).
  --verify <ID>        Verify-routing verdict (PASS/CONDITIONAL_PASS/BLOCKED).
  --all                Scan task-descriptions for missing expectations (advisory, exit 0).
  --root <path>        Repository root containing datarim/ (default: pwd).
  --report             Human-readable detail output (single-task mode).
  --today YYYY-MM-DD   Override today's date for soft-window tests.
  --help               Show this help and exit 0.
  --version            Print version and exit 0.

Exit codes:
  0   PASS / OK / advisory findings only
  1   structural error OR BLOCKED verdict
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
            MODE="task"; shift
            TASK_ID="${1:-}"
            [ -z "$TASK_ID" ] && { echo "ERROR: --task requires a TASK-ID" >&2; exit 2; }
            ;;
        --verify)
            MODE="verify"; shift
            TASK_ID="${1:-}"
            [ -z "$TASK_ID" ] && { echo "ERROR: --verify requires a TASK-ID" >&2; exit 2; }
            ;;
        --all)
            MODE="all"
            ;;
        --root)
            shift; ROOT="${1:-}"
            ;;
        --report)
            REPORT=1
            ;;
        --today)
            shift; TODAY="${1:-}"
            ;;
        --help|-h)
            usage; exit 0
            ;;
        --version)
            echo "$SCRIPT_NAME $VERSION"; exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2
            ;;
    esac
    shift
done

[ -z "$MODE" ] && { echo "ERROR: one of --task, --verify or --all is required" >&2; exit 2; }
[ -z "$ROOT" ] && ROOT="$(pwd)"
[ -z "$TODAY" ] && TODAY="$(date +%Y-%m-%d)"

TASKS_DIR="$ROOT/datarim/tasks"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

days_between() {
    local from="$1" to="$2"
    local from_epoch to_epoch
    from_epoch=$(date -j -f "%Y-%m-%d" "$from" +%s 2>/dev/null || true)
    to_epoch=$(date -j -f "%Y-%m-%d" "$to" +%s 2>/dev/null || true)
    if [ -z "$from_epoch" ] || [ -z "$to_epoch" ]; then
        from_epoch=$(date -d "$from" +%s 2>/dev/null || echo "")
        to_epoch=$(date -d "$to" +%s 2>/dev/null || echo "")
    fi
    if [ -z "$from_epoch" ] || [ -z "$to_epoch" ]; then
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
# Core: per-item parser. Emits a pipe-separated table to stdout for verify
# mode and structural errors to stderr. Exit 0 if zero errors, 1 otherwise.
#
# Output stream (stdout):
#   <item_num>|<wish_id>|<status>|<override_len>
#
# Errors (stderr):
#   ERROR: <file>: <item N | section> <reason>
# ---------------------------------------------------------------------------

parse_items() {
    local file="$1"
    awk -v f="$file" '
        BEGIN {
            in_section = 0; current_item = 0; total_items = 0; errors = 0
            wish_id = ""; status = ""; override_text = ""
            history_count = 0; has_history_heading = 0; has_status_heading = 0
            in_history = 0; in_status = 0
        }

        /^## Ожидания[ \t]*$/ {
            in_section = 1; next
        }
        /^## / && in_section {
            if (current_item) emit_item()
            current_item = 0
            in_section = 0
            in_history = 0; in_status = 0
            next
        }

        in_section {
            # New item header: `- **N. Title**`
            if (match($0, /^- \*\*[0-9]+\. /)) {
                if (current_item) emit_item()
                total_items++
                current_item = total_items
                wish_id = ""; status = ""; override_text = ""
                history_count = 0; has_history_heading = 0; has_status_heading = 0
                in_history = 0; in_status = 0
                next
            }
            if (current_item) {
                if (match($0, /^  - wish_id:[ \t]*/)) {
                    wish_id = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", wish_id)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - override:[ \t]*/)) {
                    override_text = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", override_text)
                    in_history = 0; in_status = 0; next
                }
                if ($0 ~ /^  - #### История статусов/) {
                    has_history_heading = 1; in_history = 1; in_status = 0; next
                }
                if ($0 ~ /^  - #### Текущий статус/) {
                    has_status_heading = 1; in_history = 0; in_status = 1; next
                }
                if (in_history && match($0, /^    - /)) {
                    history_count++
                    line = substr($0, 7)
                    if (!(line ~ /·.*·.*·.*reason:/)) {
                        printf "ERROR: %s: item %d malformed История статусов line: %s\n", \
                            f, current_item, line > "/dev/stderr"
                        errors++
                    }
                    next
                }
                if (in_status && match($0, /^    - /)) {
                    status = substr($0, 7)
                    sub(/[ \t]+$/, "", status)
                    in_status = 0; next
                }
            }
        }

        END {
            if (current_item) emit_item()
            if (total_items == 0) {
                printf "ERROR: %s: no items found under ## Ожидания (file appears empty)\n", f > "/dev/stderr"
                errors++
            }
            exit (errors > 0 ? 1 : 0)
        }

        function emit_item(    ovr_len) {
            if (wish_id == "") {
                printf "ERROR: %s: item %d missing wish_id\n", f, current_item > "/dev/stderr"
                errors++
            }
            if (!has_history_heading) {
                printf "ERROR: %s: item %d missing #### История статусов heading\n", f, current_item > "/dev/stderr"
                errors++
            } else if (history_count == 0) {
                printf "ERROR: %s: item %d has empty История статусов (need >=1 entry)\n", f, current_item > "/dev/stderr"
                errors++
            }
            if (!has_status_heading) {
                printf "ERROR: %s: item %d missing #### Текущий статус heading\n", f, current_item > "/dev/stderr"
                errors++
            }
            if (status == "") {
                printf "ERROR: %s: item %d missing Текущий статус value\n", f, current_item > "/dev/stderr"
                errors++
            } else if (status != "pending" && status != "met" && status != "partial" \
                   && status != "missed" && status != "n-a" && status != "deleted") {
                printf "ERROR: %s: item %d status not in enum: %s\n", f, current_item, status > "/dev/stderr"
                errors++
            }
            ovr_len = length(override_text)
            printf "%d|%s|%s|%d\n", current_item, wish_id, status, ovr_len
        }
    ' "$file"
}

# ---------------------------------------------------------------------------
# Single-task structural validation
# ---------------------------------------------------------------------------

validate_single_task() {
    local id="$1"
    local file="$TASKS_DIR/${id}-expectations.md"

    if [ ! -f "$file" ]; then
        echo "ERROR: expectations file missing for $id (expected $file)" >&2
        if [ "$REPORT" -eq 1 ]; then
            echo "  Run /dr-prd or /dr-plan to seed expectations from PRD"
            echo "  acceptance criteria + init-task. Contract in"
            echo "  skills/expectations-checklist.md."
        fi
        return 1
    fi

    local errors=0 val

    for field in task_id artifact schema_version captured_at captured_by status; do
        val=$(extract_frontmatter_field "$file" "$field")
        if [ -z "$val" ]; then
            echo "ERROR: $file: frontmatter missing required field '$field'" >&2
            errors=$(( errors + 1 ))
        fi
    done

    val=$(extract_frontmatter_field "$file" "artifact")
    if [ -n "$val" ] && [ "$val" != "expectations" ]; then
        echo "ERROR: $file: frontmatter artifact must be 'expectations', got '$val'" >&2
        errors=$(( errors + 1 ))
    fi

    val=$(extract_frontmatter_field "$file" "schema_version")
    if [ -n "$val" ] && [ "$val" != "1" ]; then
        echo "ERROR: $file: schema_version must be '1', got '$val'" >&2
        errors=$(( errors + 1 ))
    fi

    val=$(extract_frontmatter_field "$file" "task_id")
    if [ -n "$val" ] && ! [[ "$val" =~ ^[A-Z]{2,10}-[0-9]{4}$ ]]; then
        echo "ERROR: $file: task_id '$val' does not match {PREFIX-NNNN}" >&2
        errors=$(( errors + 1 ))
    fi

    if ! grep -q '^## Ожидания[[:space:]]*$' "$file"; then
        echo "ERROR: $file: missing required heading '## Ожидания'" >&2
        errors=$(( errors + 1 ))
    fi

    # Item-level parse — emits to stdout (discarded here) + stderr.
    if ! parse_items "$file" >/dev/null; then
        errors=$(( errors + 1 ))
    fi

    if [ "$errors" -gt 0 ]; then
        if [ "$REPORT" -eq 1 ]; then
            echo "  $errors validation error(s) — see contract in"
            echo "  skills/expectations-checklist.md § Item Schema."
        fi
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Verify-routing mode
# ---------------------------------------------------------------------------

verify_routing() {
    local id="$1"
    local file="$TASKS_DIR/${id}-expectations.md"

    if [ ! -f "$file" ]; then
        echo "ERROR: expectations file missing for $id (expected $file)" >&2
        echo "BLOCKED: expectations checklist absent — run /dr-prd or /dr-plan first"
        return 1
    fi

    # Validate structure first; structural error → BLOCKED.
    if ! validate_single_task "$id" >/dev/null 2>&1; then
        echo "BLOCKED: expectations file fails structural validation; run --task --report for detail" >&2
        return 1
    fi

    local items
    items=$(parse_items "$file" 2>/dev/null) || true

    local blocking=()
    local has_partial_or_missed=0

    while IFS='|' read -r _idx wish_id status ovr_len; do
        [ -z "$status" ] && continue
        case "$status" in
            met|n-a|pending|deleted)
                ;;
            partial|missed)
                has_partial_or_missed=1
                if [ "${ovr_len:-0}" -lt 10 ]; then
                    blocking+=("$wish_id")
                fi
                ;;
            *)
                # Already caught by structural validation; defensive guard.
                blocking+=("$wish_id")
                ;;
        esac
    done <<< "$items"

    if [ "${#blocking[@]}" -gt 0 ]; then
        local focus
        focus=$(IFS=,; echo "${blocking[*]}")
        echo "BLOCKED: ${#blocking[@]} expectation(s) require resolution"
        echo "Focus items: $focus"
        echo "Next step:   /dr-do $id --focus-items $focus"
        return 1
    fi

    if [ "$has_partial_or_missed" -eq 1 ]; then
        echo "CONDITIONAL_PASS: all partial/missed items carry valid operator override"
        return 0
    fi

    echo "PASS: all expectation items met / n-a / pending / deleted"
    return 0
}

# ---------------------------------------------------------------------------
# Multi-task advisory scan
# ---------------------------------------------------------------------------

scan_all_tasks() {
    [ ! -d "$TASKS_DIR" ] && return 0

    local desc id complexity status legacy created exp_file age severity
    shopt -s nullglob
    for desc in "$TASKS_DIR"/*-task-description.md; do
        id="$(basename "$desc")"
        id="${id%-task-description.md}"
        exp_file="$TASKS_DIR/${id}-expectations.md"
        [ -f "$exp_file" ] && continue

        complexity=$(extract_frontmatter_field "$desc" "complexity")
        case "$complexity" in
            L3|L4) ;;
            *) continue ;;
        esac

        status=$(extract_frontmatter_field "$desc" "status")
        case "$status" in
            archived|completed|cancelled) continue ;;
        esac

        legacy=$(extract_frontmatter_field "$desc" "legacy")
        [ "$legacy" = "true" ] && continue

        created=$(extract_frontmatter_field "$desc" "created")
        if [ -z "$created" ]; then
            echo "info: $id expectations missing (no 'created' date in description)"
            continue
        fi

        age=$(days_between "$created" "$TODAY")
        if [ "$age" -lt 30 ]; then
            severity="info"
        else
            severity="warn"
        fi
        echo "$severity: $id expectations missing (task age ${age}d; rolling 30d soft window, complexity $complexity)"
    done
    shopt -u nullglob
    return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$MODE" in
    task)
        validate_single_task "$TASK_ID"; exit $?
        ;;
    verify)
        verify_routing "$TASK_ID"; exit $?
        ;;
    all)
        scan_all_tasks; exit 0
        ;;
    *)
        usage >&2; exit 2
        ;;
esac
