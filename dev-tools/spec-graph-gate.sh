#!/usr/bin/env bash
# spec-graph-gate.sh — internal automatic spec-graph stage adapter.
#
# This is not an operator command. Existing pipeline stages invoke it with the
# task and stage they already own. It centralizes complexity, rollout mode,
# artifact scope, helper orchestration, and normalized 0/1/2 exits.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LINT="${SCRIPT_DIR}/dr-lint.sh"
TRACE="${SCRIPT_DIR}/dr-trace.sh"
GRADE="${SCRIPT_DIR}/dr-spec-grade.sh"

TASK=""
STAGE=""
ROOT="$PWD"
FORMAT="text"

usage_die() {
    printf 'spec-graph-gate: %s\n' "$*" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --task) shift; [ $# -gt 0 ] || usage_die "--task requires an id"; TASK="$1"; shift ;;
        --stage) shift; [ $# -gt 0 ] || usage_die "--stage requires a value"; STAGE="$1"; shift ;;
        --root) shift; [ $# -gt 0 ] || usage_die "--root requires a path"; ROOT="$1"; shift ;;
        --format) shift; [ $# -gt 0 ] || usage_die "--format requires a value"; FORMAT="$1"; shift ;;
        --help|-h) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) usage_die "unknown flag: $1" ;;
    esac
done

[ -n "$TASK" ] || usage_die "--task <ID> is required"
printf '%s' "$TASK" | grep -qE '^[A-Z]+-[0-9]+(-[A-Za-z0-9]+)*$' \
    || usage_die "invalid task id: $TASK"
case "$STAGE" in
    prd|plan|do|qa|compliance|verify) ;;
    *) usage_die "--stage must be prd|plan|do|qa|compliance|verify" ;;
esac
case "$FORMAT" in json|text) ;; *) usage_die "--format must be json|text" ;; esac
[ -d "$ROOT" ] || usage_die "root not found: $ROOT"
[ -f "$LINT" ] && [ -f "$TRACE" ] && [ -f "$GRADE" ] \
    || usage_die "spec-graph helper missing under $SCRIPT_DIR"

DATARIM_ROOT=""
search="$ROOT"
while [ "$search" != "/" ] && [ -n "$search" ]; do
    if [ -d "$search/datarim" ]; then DATARIM_ROOT="$search/datarim"; break; fi
    search="$(dirname "$search")"
done
[ -n "$DATARIM_ROOT" ] || usage_die "datarim/ not found from $ROOT"

PRD="$DATARIM_ROOT/prd/PRD-${TASK}.md"
PLAN="$DATARIM_ROOT/plans/${TASK}-plan.md"
EXPECTATIONS="$DATARIM_ROOT/tasks/${TASK}-expectations.md"
TASK_DESC="$DATARIM_ROOT/tasks/${TASK}-task-description.md"

LEVEL="L3"
if [ -f "$PRD" ] && grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+4|L4)\b' "$PRD"; then LEVEL="L4"
elif [ -f "$PRD" ] && grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+2|L2)\b' "$PRD"; then LEVEL="L2"
elif [ -f "$PRD" ] && grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+1|L1)\b' "$PRD"; then LEVEL="L1"
elif [ -f "$TASK_DESC" ]; then
    if grep -qiE '^complexity:[[:space:]]*L1' "$TASK_DESC"; then LEVEL="L1"
    elif grep -qiE '^complexity:[[:space:]]*L2' "$TASK_DESC"; then LEVEL="L2"
    elif grep -qiE '^complexity:[[:space:]]*L4' "$TASK_DESC"; then LEVEL="L4"
    fi
else
    # Fallback: neither PRD nor task-description carries the complexity (e.g.
    # an inline-executed L2 task whose PRD is legitimately waived). Read the
    # level from the one-liner index rows (`- TASK · status · P · L<N> · ...`)
    # in backlog.md, then the active tasks.md, before defaulting to L3 and
    # fail-closing the no-PRD branch below. Backlog wins over tasks.md when both
    # carry the row; PRD and task-description (handled above) still take
    # precedence over this fallback. Source: TUNE-0444.
    for _idx in "$DATARIM_ROOT/backlog.md" "$DATARIM_ROOT/tasks.md"; do
        [ -f "$_idx" ] || continue
        _row="$(grep -m1 -E "^- ${TASK} ·" "$_idx" || true)"
        [ -n "$_row" ] || continue
        if printf '%s' "$_row" | grep -qE '· L1 ·'; then LEVEL="L1"; break
        elif printf '%s' "$_row" | grep -qE '· L2 ·'; then LEVEL="L2"; break
        elif printf '%s' "$_row" | grep -qE '· L4 ·'; then LEVEL="L4"; break
        elif printf '%s' "$_row" | grep -qE '· L3 ·'; then LEVEL="L3"; break
        fi
    done
fi

MODE="${DATARIM_SPEC_GRAPH_MODE:-advisory}"
case "$MODE" in advisory|hard) ;; *) usage_die "DATARIM_SPEC_GRAPH_MODE must be advisory|hard" ;; esac

if [ ! -f "$PRD" ]; then
    if [ "$LEVEL" = "L1" ] || [ "$LEVEL" = "L2" ]; then
        if [ "$FORMAT" = "json" ]; then
            printf '{"task":"%s","stage":"%s","complexity":"%s","mode":"%s","decision":"skip","evaluated_artifacts":[],"excluded_artifacts":[{"path":"%s","reason":"no PRD graph expected at this complexity"}],"findings":[]}\n' \
                "$TASK" "$STAGE" "$LEVEL" "$MODE" "$PRD"
        else
            printf 'spec-graph: SKIP %s %s (%s, no PRD graph)\n' "$TASK" "$STAGE" "$LEVEL"
        fi
        exit 0
    fi
    # ---- Class B: documented PRD-waiver skip (TUNE-0473) ---------------------
    # A follow-up L3/L4 task may legitimately run WITHOUT its own PRD when the
    # operator records the canonical waiver line `**PRD waived:**` (mandated by
    # the datarim-system task-identity contract: one scoped track from a parent
    # PRD/archive, parent approved <30 days ago, no new requirements). Before
    # emitting the hard usage-error, look for that marker on the task's
    # authoritative surfaces (tasks.md is the mandated home; plan/task-description
    # carry it in practice). When present, SKIP with an explicit reason instead
    # of a usage-error -- this is the documented waiver path, NOT a silent bypass.
    # Guard: the <30d age is only *asserted* in the reason when a parent PRD id
    # in the marker resolves to a file whose mtime is within 30 days; otherwise
    # the reason states the waiver is documented but the parent age is
    # unverifiable (honest, non-fabricated). No invented marker: keyed strictly
    # off the canonical `**PRD waived:**` token.
    waiver_line=""
    for _src in "$DATARIM_ROOT/tasks.md" "$PLAN" "$TASK_DESC" "$EXPECTATIONS"; do
        [ -f "$_src" ] || continue
        waiver_line="$(grep -m1 -F '**PRD waived:**' "$_src" 2>/dev/null || true)"
        [ -n "$waiver_line" ] && break
    done
    if [ -n "$waiver_line" ]; then
        # Best-effort parent-PRD age check: pull the first PRD id token from the
        # marker line and, if the corresponding PRD file exists and is <=30 days
        # old, assert the <30d claim; else fall back to an unverified reason.
        waiver_reason="documented PRD-waiver (parent age unverified)"
        _parent_id="$(printf '%s' "$waiver_line" | grep -oE 'PRD-[A-Z]+-[0-9]+' | head -1 | sed -E 's/^PRD-//')"
        if [ -n "$_parent_id" ]; then
            for _pprd in "$DATARIM_ROOT/prd/PRD-${_parent_id}.md" "$DATARIM_ROOT/prd/${_parent_id}-prd.md"; do
                [ -f "$_pprd" ] || continue
                if find "$_pprd" -mtime -30 2>/dev/null | grep -q .; then
                    waiver_reason="documented PRD-waiver (parent <30d)"
                fi
                break
            done
        fi
        if [ "$FORMAT" = "json" ]; then
            printf '{"task":"%s","stage":"%s","complexity":"%s","mode":"%s","decision":"skip","reason":"%s","evaluated_artifacts":[],"excluded_artifacts":[{"path":"%s","reason":"%s"}],"findings":[]}\n' \
                "$TASK" "$STAGE" "$LEVEL" "$MODE" "$waiver_reason" "$PRD" "$waiver_reason"
        else
            printf 'spec-graph: SKIP %s %s (%s, %s)\n' "$TASK" "$STAGE" "$LEVEL" "$waiver_reason"
        fi
        exit 0
    fi
    usage_die "required PRD missing for $TASK"
fi

required=("$PRD")
case "$STAGE" in
    plan|do|qa|compliance) required+=("$PLAN") ;;
esac
case "$STAGE" in
    do|qa|compliance) required+=("$TASK_DESC") ;;
esac
if { [ "$LEVEL" = "L3" ] || [ "$LEVEL" = "L4" ]; } && [ "$STAGE" != "verify" ]; then
    required+=("$EXPECTATIONS")
fi

if [ "$LEVEL" = "L1" ]; then
    if [ "$FORMAT" = "json" ]; then
        printf '{"task":"%s","stage":"%s","complexity":"L1","mode":"%s","decision":"skip","evaluated_artifacts":[],"excluded_artifacts":[],"findings":[]}\n' \
            "$TASK" "$STAGE" "$MODE"
    else
        printf 'spec-graph: SKIP %s %s (L1)\n' "$TASK" "$STAGE"
    fi
    exit 0
fi

for artifact in "${required[@]}"; do
    [ -f "$artifact" ] || usage_die "required artifact missing for stage $STAGE: $artifact"
done

rules=""
case "$STAGE" in
    prd)
        rules="dreq-id-format,dreq-id-unique,covers-resolves,dreq-dangling,vac-covers-present,axis-separation,graph-complete-l3"
        ;;
    plan|verify)
        rules="dreq-id-format,dreq-id-unique,covers-resolves,dreq-orphan,dreq-dangling,vac-covers-present,vac-binding-present,binding-no-duplicate,axis-separation,graph-complete-l3"
        ;;
    do|qa|compliance)
        rules="dreq-id-format,dreq-id-unique,covers-resolves,dreq-orphan,dreq-dangling,vac-covers-present,vac-binding-present,binding-no-duplicate,axis-separation,graph-complete-l3"
        ;;
esac

lint_tmp="$(mktemp)"
trace_tmp="$(mktemp)"
grade_tmp="$(mktemp)"
trap 'rm -f "$lint_tmp" "$trace_tmp" "$grade_tmp"' EXIT

bash "$LINT" --task "$TASK" --root "$ROOT" --stage "$STAGE" \
    --rules "$rules" --format json --advisory >"$lint_tmp"
lint_rc=$?
[ "$lint_rc" -ne 2 ] || exit 2

bash "$TRACE" --task "$TASK" --root "$ROOT" --format json >"$trace_tmp"
trace_rc=$?
[ "$trace_rc" -ne 2 ] || exit 2

bash "$GRADE" --findings "$lint_tmp" --format json >"$grade_tmp"
grade_rc=$?
[ "$grade_rc" -ne 2 ] || exit 2

hard_enabled=0
if [ "$MODE" = "hard" ] && { [ "$LEVEL" = "L3" ] || [ "$LEVEL" = "L4" ]; }; then
    case "$STAGE" in prd|plan|qa|compliance|verify) hard_enabled=1 ;; esac
fi

if ! error_count="$(python3 - "$lint_tmp" <<'PYEOF'
import json, sys
n = 0
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        if line.strip() and json.loads(line).get("severity") == "error":
            n += 1
print(n)
PYEOF
)"; then
    printf 'spec-graph-gate: malformed lint output\n' >&2
    exit 2
fi

decision="clean"
exit_code=0
if [ "${error_count:-0}" -gt 0 ]; then
    if [ "$hard_enabled" -eq 1 ]; then
        decision="blocked"
        exit_code=1
    else
        decision="advisory"
    fi
elif [ -s "$lint_tmp" ]; then
    decision="advisory"
fi

if [ "$STAGE" = "do" ] && [ -s "$lint_tmp" ]; then
    decision="advisory"
    exit_code=0
fi

if [ "$FORMAT" = "json" ]; then
    python3 - "$TASK" "$STAGE" "$LEVEL" "$MODE" "$decision" \
        "$lint_tmp" "$trace_tmp" "$grade_tmp" "$ROOT" \
        "$PRD" "$PLAN" "$EXPECTATIONS" "$TASK_DESC" <<'PYEOF'
import json
import os
import sys

task, stage, level, mode, decision, lint_path, trace_path, grade_path, root, *canonical = sys.argv[1:]
with open(lint_path, encoding="utf-8") as fh:
    findings = [json.loads(line) for line in fh if line.strip()]
with open(trace_path, encoding="utf-8") as fh:
    trace = json.load(fh)
with open(grade_path, encoding="utf-8") as fh:
    grade = json.load(fh)
included = [
    {"path": os.path.relpath(path, root), "reason": "canonical current-task artifact"}
    for path in canonical if os.path.isfile(path)
]
excluded = [
    {"path": os.path.relpath(path, root), "reason": "artifact absent and optional for this stage"}
    for path in canonical if not os.path.isfile(path)
]
print(json.dumps({
    "task": task,
    "stage": stage,
    "complexity": level,
    "mode": mode,
    "decision": decision,
    "evaluated_artifacts": included,
    "excluded_artifacts": excluded,
    "findings": findings,
    "trace": trace,
    "grade": grade,
}, separators=(",", ":")))
PYEOF
else
    printf 'spec-graph: task=%s stage=%s complexity=%s mode=%s decision=%s findings=%s\n' \
        "$TASK" "$STAGE" "$LEVEL" "$MODE" "$decision" "$(grep -c . "$lint_tmp" || true)"
    cat "$lint_tmp"
    cat "$trace_tmp"
    cat "$grade_tmp"
fi

exit "$exit_code"
