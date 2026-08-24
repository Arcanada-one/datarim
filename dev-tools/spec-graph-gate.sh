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
LIB="${SCRIPT_DIR}/../scripts/lib/spec-graph.sh"

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
[ -f "$LINT" ] && [ -f "$TRACE" ] && [ -f "$GRADE" ] && [ -f "$LIB" ] \
    || usage_die "spec-graph helper missing under $SCRIPT_DIR"
# shellcheck source=scripts/lib/spec-graph.sh
. "$LIB"

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
CUSTOMER_REQUIREMENTS="$DATARIM_ROOT/tasks/${TASK}-customer-requirements.yaml"
CUSTOMER_RECEIPT="$DATARIM_ROOT/receipts/${TASK}-customer-delivery.yaml"
QA_REPORT="$DATARIM_ROOT/qa/qa-report-${TASK}.md"
COMPLIANCE_REPORT="$DATARIM_ROOT/reports/compliance-report-${TASK}.md"

# _match_complexity <file> <level-label>
# Single helper shared by the PRD and task-description branches so the two
# cannot drift apart. Uses the tolerant pattern: optional leading whitespace,
# optional ** bold wrapper, case-insensitive, accepts both "Level N" and "LN".
_match_complexity() {
    grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+'"${2#L}"'|'"$2"')\b' "$1"
}

LEVEL="L3"
_resolved=0

# Precedence: PRD > task-description > backlog.md > tasks.md > default L3.
# The _resolved flag ensures the index-row fallback runs on failure to
# resolve, not on absence of file — a task-description that exists but
# carries no parseable complexity line does not block the fallback.

if [ -f "$PRD" ]; then
    if _match_complexity "$PRD" "L4"; then LEVEL="L4"; _resolved=1
    elif _match_complexity "$PRD" "L2"; then LEVEL="L2"; _resolved=1
    elif _match_complexity "$PRD" "L1"; then LEVEL="L1"; _resolved=1
    fi
fi

if [ "$_resolved" -eq 0 ] && [ -f "$TASK_DESC" ]; then
    if _match_complexity "$TASK_DESC" "L4"; then LEVEL="L4"; _resolved=1
    elif _match_complexity "$TASK_DESC" "L2"; then LEVEL="L2"; _resolved=1
    elif _match_complexity "$TASK_DESC" "L1"; then LEVEL="L1"; _resolved=1
    fi
fi

if [ "$_resolved" -eq 0 ]; then
    # Fallback: neither PRD nor task-description resolved the complexity
    # (e.g. an inline-executed L2 task whose PRD is legitimately waived,
    # or a task-description that exists but has no parseable complexity
    # line). Read the level from the one-liner index rows
    # (`- TASK · status · P · L<N> · ...`) in backlog.md, then the active
    # tasks.md, before defaulting to L3 and fail-closing the no-PRD branch
    # below. Backlog wins over tasks.md when both carry the row; PRD and
    # task-description (handled above) still take precedence over this
    # fallback. Source: TUNE-0444, TUNE-0528.
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

# Customer delivery extends the graph inventory, but does not become a second
# closure validator. A schema-v4 customer-derived wish makes the extension
# applicable. Plan/do fail hard only on the U3 pre-work prefix: stable
# Requirement -> V-AC binding plus requirement and selected-knowledge receipt
# edges with all six knowledge kinds. Downstream delivery edges may be absent
# while implementation is in progress and remain owned by
# check-customer-delivery.sh at QA/compliance/archive.
customer_applicable=0
customer_prework_ready=1
customer_prework_findings=""
customer_links_tmp=""
customer_receipt_tmp=""
customer_knowledge_tmp=""
customer_requirement_knowledge_tmp=""
lint_tmp=""
trace_tmp=""
grade_tmp=""
customer_links_tmp="$(mktemp)" || usage_die "cannot allocate customer link inventory"
trap 'rm -f -- "$lint_tmp" "$trace_tmp" "$grade_tmp" "$customer_links_tmp" "$customer_receipt_tmp" "$customer_knowledge_tmp" "$customer_requirement_knowledge_tmp"' EXIT
customer_receipt_tmp="$(mktemp)" || usage_die "cannot allocate customer receipt inventory"
customer_knowledge_tmp="$(mktemp)" || usage_die "cannot allocate customer knowledge inventory"
customer_requirement_knowledge_tmp="$(mktemp)" \
    || usage_die "cannot allocate customer requirement knowledge inventory"

collect_customer_requirement_vac_edges "$EXPECTATIONS" include-incomplete >"$customer_links_tmp" \
    || usage_die "customer requirement/V-AC collector failed"
if [ -s "$customer_links_tmp" ]; then
    customer_applicable=1
    collect_customer_receipt_edges "$CUSTOMER_RECEIPT" >"$customer_receipt_tmp" \
        || usage_die "customer receipt edge collector failed"
    collect_customer_selected_knowledge_kinds "$CUSTOMER_RECEIPT" >"$customer_knowledge_tmp" \
        || usage_die "customer selected-knowledge collector failed"
    collect_customer_selected_knowledge_kinds "$CUSTOMER_REQUIREMENTS" \
        >"$customer_requirement_knowledge_tmp" \
        || usage_die "customer requirement knowledge collector failed"

    if [ ! -f "$CUSTOMER_REQUIREMENTS" ]; then
        customer_prework_ready=0
        customer_prework_findings="${customer_prework_findings}missing_customer_requirements\n"
    fi
    if [ ! -f "$CUSTOMER_RECEIPT" ]; then
        customer_prework_ready=0
        customer_prework_findings="${customer_prework_findings}missing_customer_delivery_receipt\n"
    fi

    while IFS=$'\t' read -r requirement_id _vac _source; do
        [ -n "$requirement_id" ] || continue
        if [ "$requirement_id" = "__MISSING_REQUIREMENT__" ]; then
            customer_prework_ready=0
            customer_prework_findings="${customer_prework_findings}missing_customer_binding:requirement_id\n"
            continue
        fi
        if [ "$_vac" = "__MISSING_VAC__" ]; then
            customer_prework_ready=0
            customer_prework_findings="${customer_prework_findings}missing_customer_binding:v_ac:${requirement_id}\n"
            continue
        fi
        if ! collect_customer_requirement_ids "$CUSTOMER_REQUIREMENTS" | grep -qx "$requirement_id"; then
            customer_prework_ready=0
            customer_prework_findings="${customer_prework_findings}missing_requirement:${requirement_id}\n"
        fi
        for edge in requirement selected_knowledge; do
            if ! awk -F'\t' -v req="$requirement_id" -v edge="$edge" \
                '$1 == req && $2 == edge {found=1} END {exit(found ? 0 : 1)}' \
                "$customer_receipt_tmp"; then
                customer_prework_ready=0
                customer_prework_findings="${customer_prework_findings}missing_prework_edge:${requirement_id}:${edge}\n"
            fi
        done
        for kind in roles skills blueprints constraints policies success_criteria; do
            if ! awk -F'\t' -v req="$requirement_id" -v kind="$kind" \
                '$1 == req && $2 == kind {found=1} END {exit(found ? 0 : 1)}' \
                "$customer_knowledge_tmp"; then
                customer_prework_ready=0
                customer_prework_findings="${customer_prework_findings}missing_knowledge_kind:${requirement_id}:${kind}\n"
            fi
            if ! awk -F'\t' -v req="$requirement_id" -v kind="$kind" \
                '$1 == req && $2 == kind {found=1} END {exit(found ? 0 : 1)}' \
                "$customer_requirement_knowledge_tmp"; then
                customer_prework_ready=0
                customer_prework_findings="${customer_prework_findings}missing_requirement_knowledge_kind:${requirement_id}:${kind}\n"
            fi
        done
    done <"$customer_links_tmp"
fi

rules=""
case "$STAGE" in
    prd)
        rules="dreq-id-format,dreq-id-unique,covers-resolves,dreq-dangling,vac-covers-present,axis-separation,graph-complete-l3"
        ;;
    plan|verify)
        rules="dreq-id-format,dreq-id-unique,covers-resolves,dreq-orphan,dreq-dangling,vac-covers-present,vac-binding-present,binding-no-duplicate,axis-separation,vac-deliverable-coverage,graph-complete-l3"
        ;;
    do|qa|compliance)
        rules="dreq-id-format,dreq-id-unique,covers-resolves,dreq-orphan,dreq-dangling,vac-covers-present,vac-binding-present,binding-no-duplicate,axis-separation,vac-deliverable-coverage,graph-complete-l3"
        ;;
esac

lint_tmp="$(mktemp)" || usage_die "cannot allocate lint output"
trace_tmp="$(mktemp)" || usage_die "cannot allocate trace output"
grade_tmp="$(mktemp)" || usage_die "cannot allocate grade output"

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

if [ "$customer_applicable" -eq 1 ] \
    && { [ "$STAGE" = "plan" ] || [ "$STAGE" = "do" ]; } \
    && [ "$customer_prework_ready" -ne 1 ]; then
    decision="blocked"
    exit_code=1
fi

if [ "$FORMAT" = "json" ]; then
    python3 - "$TASK" "$STAGE" "$LEVEL" "$MODE" "$decision" \
        "$lint_tmp" "$trace_tmp" "$grade_tmp" "$ROOT" \
        "$PRD" "$PLAN" "$EXPECTATIONS" "$TASK_DESC" \
        "$CUSTOMER_REQUIREMENTS" "$CUSTOMER_RECEIPT" \
        "$customer_applicable" "$customer_prework_ready" \
        "$customer_prework_findings" "$customer_links_tmp" \
        "$customer_receipt_tmp" "$QA_REPORT" "$COMPLIANCE_REPORT" <<'PYEOF'
import json
import os
import sys

(
    task, stage, level, mode, decision, lint_path, trace_path, grade_path, root,
    prd, plan, expectations, task_desc, customer_requirements, customer_receipt,
    customer_applicable, customer_prework_ready, customer_prework_findings,
    customer_links_path, customer_receipt_path, qa_report, compliance_report,
) = sys.argv[1:]
with open(lint_path, encoding="utf-8") as fh:
    findings = [json.loads(line) for line in fh if line.strip()]
with open(trace_path, encoding="utf-8") as fh:
    trace = json.load(fh)
with open(grade_path, encoding="utf-8") as fh:
    grade = json.load(fh)
canonical = (prd, plan, expectations, task_desc, customer_requirements, customer_receipt)
included = [
    {"path": os.path.relpath(path, root), "reason": "canonical current-task artifact"}
    for path in canonical if os.path.isfile(path)
]
excluded = [
    {"path": os.path.relpath(path, root), "reason": "artifact absent and optional for this stage"}
    for path in canonical if not os.path.isfile(path)
]

links = []
with open(customer_links_path, encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            links.append((parts[0], parts[1]))
receipt_edges = {}
with open(customer_receipt_path, encoding="utf-8") as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            receipt_edges.setdefault(parts[0], set()).add(parts[1])

evidence_vacs = set()
evidence_pattern = __import__("re").compile(r"Evidence:\s*(V-AC-[A-Z]?\d+(?:\.\d+)?)\s+—")
for path in (task_desc, qa_report, compliance_report):
    if not os.path.isfile(path):
        continue
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            match = evidence_pattern.search(line)
            if match:
                evidence_vacs.add(match.group(1))

edges = []
missing = []
for requirement, vac in links:
    if requirement.startswith("__MISSING_") or vac.startswith("__MISSING_"):
        missing.append("customer_binding")
        continue
    edges.append({"from": f"requirement:{requirement}", "to": f"vac:{vac}"})
    present = receipt_edges.get(requirement, set())
    if "selected_knowledge" in present:
        edges.append({
            "from": f"requirement:{requirement}",
            "to": f"knowledge:{requirement}:selected_knowledge",
        })
    else:
        missing.append(f"{requirement}:selected_knowledge")
    if "red_green" in present and vac in evidence_vacs:
        edges.append({"from": f"vac:{vac}", "to": f"evidence:{requirement}:red_green"})
    else:
        missing.append(f"{requirement}:evidence")
    if "implementation_delta" in present:
        edges.append({
            "from": f"evidence:{requirement}:red_green",
            "to": f"implementation:{requirement}:implementation_delta",
        })
    else:
        missing.append(f"{requirement}:implementation")
    if "live_evidence" in present:
        edges.append({
            "from": f"implementation:{requirement}:implementation_delta",
            "to": f"live:{requirement}:live_evidence",
        })
    else:
        missing.append(f"{requirement}:live")
    if "customer_disposition" in present:
        edges.append({
            "from": f"live:{requirement}:live_evidence",
            "to": f"customer:{requirement}:customer_disposition",
        })
    else:
        missing.append(f"{requirement}:customer_disposition")

customer_graph = {
    "applicable": customer_applicable == "1",
    "prework_ready": customer_prework_ready == "1",
    "prework_findings": [
        item for item in customer_prework_findings.split("\\n") if item
    ],
    "edges": edges,
    "missing_edges": sorted(set(missing)),
    "closure_authority": "check-customer-delivery.sh",
}
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
    "customer_delivery_prework": customer_graph,
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
