#!/usr/bin/env bash
# Deterministically validate one task's customer-delivery evidence bundle.
#
# Canonical task-bound artifacts under --root (no discovery or fallback):
#   datarim/tasks/<TASK-ID>-customer-requirements.yaml
#   datarim/receipts/<TASK-ID>-customer-delivery.yaml
#   datarim/receipts/<TASK-ID>-review-evolution.yaml
#
# Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

usage() {
    cat <<'EOF'
usage: check-customer-delivery.sh --root DIR --task TASK-ID --stage qa|compliance|archive [--format text|json]

Reads exactly these canonical task-bound artifacts below DIR:
  datarim/tasks/<TASK-ID>-customer-requirements.yaml
  datarim/receipts/<TASK-ID>-customer-delivery.yaml
  datarim/receipts/<TASK-ID>-review-evolution.yaml

Exit codes: 0 MET, 1 semantic NOT_MET, 2 usage/configuration error.
EOF
}

root=''
task=''
stage=''
format='text'
while (($#)); do
    case "$1" in
        --root|--task|--stage|--format)
            option="$1"
            (($# >= 2)) || { printf 'ERROR: %s requires a value\n' "$option" >&2; usage >&2; exit 2; }
            value="$2"
            case "$option" in
                --root) root="$value" ;;
                --task) task="$value" ;;
                --stage) stage="$value" ;;
                --format) format="$value" ;;
            esac
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -n "$root" && -n "$task" && -n "$stage" ]] || { usage >&2; exit 2; }
[[ "$task" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ ]] || { printf 'ERROR: invalid --task\n' >&2; exit 2; }
[[ "$stage" == qa || "$stage" == compliance || "$stage" == archive ]] || { printf 'ERROR: invalid --stage\n' >&2; exit 2; }
[[ "$format" == text || "$format" == json ]] || { printf 'ERROR: invalid --format\n' >&2; exit 2; }
[[ -d "$root" && ! -L "$root" ]] || { printf 'ERROR: invalid --root\n' >&2; exit 2; }
root="$(cd "$root" && pwd -P)"

framework_root="${CUSTOMER_DELIVERY_FRAMEWORK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
[[ -d "$framework_root" && ! -L "$framework_root" ]] || { printf 'ERROR: invalid framework root\n' >&2; exit 2; }
requirements="${root}/datarim/tasks/${task}-customer-requirements.yaml"
receipt="${root}/datarim/receipts/${task}-customer-delivery.yaml"
review="${root}/datarim/receipts/${task}-review-evolution.yaml"
requirements_schema="${framework_root}/config/customer-requirement.schema.json"
receipt_schema="${framework_root}/config/customer-delivery-receipt.schema.json"
review_schema="${framework_root}/config/review-evolution.schema.json"

missing=''
for artifact in "$requirements" "$receipt" "$review" "$requirements_schema" "$receipt_schema" "$review_schema"; do
    if [[ ! -f "$artifact" || -L "$artifact" ]]; then
        missing="${artifact#"$root"/}"
        break
    fi
done
if [[ -n "$missing" ]]; then
    if [[ "$format" == json ]]; then
        printf '{"decision":"ERROR","error":"missing_artifact","path":"%s","stage":"%s","task":"%s"}\n' "$missing" "$stage" "$task"
    else
        printf 'decision=ERROR stage=%s task=%s finding=missing_artifact:%s\n' "$stage" "$task" "$missing"
    fi
    exit 2
fi

python_bin="${CUSTOMER_DELIVERY_PYTHON:-python3}"
if ! "$python_bin" -c 'import jsonschema, yaml; assert "date-time" in jsonschema.FormatChecker().checkers' >/dev/null 2>&1; then
    printf 'ERROR: required Python modules unavailable: jsonschema, PyYAML, and RFC3339 format support\n' >&2
    exit 2
fi

exec "$python_bin" - "$task" "$stage" "$format" \
    "$requirements" "$receipt" "$review" \
    "$requirements_schema" "$receipt_schema" "$review_schema" <<'PY'
import hashlib
import json
import re
import sys
from datetime import datetime

import jsonschema
import yaml


TASK, STAGE, OUTPUT_FORMAT = sys.argv[1:4]
DOCUMENT_PATHS = dict(zip(
    ("requirements", "receipt", "review"),
    sys.argv[4:7],
))
SCHEMA_PATHS = dict(zip(
    ("requirements", "receipt", "review"),
    sys.argv[7:10],
))

U4_EDGES = (
    "requirement",  # U4_EDGE
    "selected_knowledge",  # U4_EDGE
    "implementation_delta",  # U4_EDGE
    "red_green",  # U4_EDGE
    "merged_revision",  # U4_EDGE
    "deployed_revision",  # U4_EDGE
    "live_evidence",  # U4_EDGE
    "customer_disposition",  # U4_EDGE
)
EXPECTED_U4_EDGES = (
    "requirement",
    "selected_knowledge",
    "implementation_delta",
    "red_green",
    "merged_revision",
    "deployed_revision",
    "live_evidence",
    "customer_disposition",
)
KNOWLEDGE_KINDS = (
    "roles", "skills", "blueprints", "constraints", "policies", "success_criteria"
)
PAINTED_MATRIX = {
    (locale, viewport, theme)
    for locale in ("ru", "en")
    for viewport in ("mobile", "desktop")
    for theme in ("light", "dark")
}


class DuplicateKeyError(yaml.YAMLError):
    def __init__(self, key):
        super().__init__(str(key))
        self.key = str(key)


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise DuplicateKeyError(key)
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


findings = []


def add(code):
    findings.append(code)


def emit(decision, code, epic_status="NOT_MET"):
    unique = sorted(set(findings))
    if OUTPUT_FORMAT == "json":
        print(json.dumps(
            {
                "decision": decision,
                "epic_status": epic_status,
                "findings": unique,
                "stage": STAGE,
                "task": TASK,
            },
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ))
    else:
        joined = ",".join(unique)
        print(
            f"decision={decision} stage={STAGE} task={TASK} "
            f"epic_status={epic_status} findings={joined}"
        )
        for finding in unique:
            print(f"finding={finding}")
    raise SystemExit(code)


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


documents = {}
schemas = {}
for name in ("requirements", "receipt", "review"):
    try:
        with open(DOCUMENT_PATHS[name], encoding="utf-8") as handle:
            loader = UniqueKeyLoader(handle)
            try:
                documents[name] = loader.get_single_data()
            finally:
                loader.dispose()
    except DuplicateKeyError as error:
        add(f"duplicate_id:{error.key}")
        emit("NOT_MET", 1)
    except (OSError, UnicodeError, yaml.YAMLError):
        add(f"parse:{name}")
        emit("NOT_MET", 1)
    try:
        schemas[name] = load_json(SCHEMA_PATHS[name])
        jsonschema.Draft202012Validator.check_schema(schemas[name])
    except (OSError, UnicodeError, json.JSONDecodeError, jsonschema.SchemaError):
        print(f"ERROR: invalid framework schema: {name}", file=sys.stderr)
        raise SystemExit(2)

# Preserve high-value cross-document attribution even when an A1 conditional
# schema rule also rejects the same otherwise-readable delivery document.
receipt_requirements = documents.get("receipt", {}).get("requirements", {})
if isinstance(receipt_requirements, dict):
    for requirement_id, delivery in sorted(receipt_requirements.items()):
        chain = delivery.get("coverage_chain", {}) if isinstance(delivery, dict) else {}
        delta = chain.get("implementation_delta", {}) if isinstance(chain, dict) else {}
        live = chain.get("live_evidence", {}) if isinstance(chain, dict) else {}
        if (
            isinstance(delta, dict)
            and isinstance(live, dict)
            and live.get("visitor_visible") is True
            and (delta.get("visitor_visible_count", 0) < 1 or not delta.get("visitor_visible_changes"))
        ):
            add(f"zero_visitor_visible_delta:{requirement_id}")

format_checker = jsonschema.FormatChecker()
for name in ("requirements", "receipt", "review"):
    validator = jsonschema.Draft202012Validator(
        schemas[name],
        format_checker=format_checker,
    )
    for error in sorted(validator.iter_errors(documents[name]), key=lambda item: list(item.absolute_path)):
        path = "/".join(str(part) for part in error.absolute_path) or "$"
        add(f"schema:{name}:{path}")

if findings:
    emit("NOT_MET", 1)

for edge in EXPECTED_U4_EDGES:
    if edge not in U4_EDGES:
        add(f"validator_rule_removed:{edge}")
for edge in U4_EDGES:
    if edge not in EXPECTED_U4_EDGES:
        add(f"validator_rule_unknown:{edge}")
if findings:
    emit("NOT_MET", 1)

requirements_doc = documents["requirements"]
receipt_doc = documents["receipt"]
review_doc = documents["review"]
requirements = requirements_doc["requirements"]
deliveries = receipt_doc["requirements"]
sources = {item["source_id"]: item for item in requirements_doc["source_remarks"]}

if len(sources) != len(requirements_doc["source_remarks"]):
    add("duplicate_id:source")
if requirements_doc["requirement_set_id"] != receipt_doc["requirement_set_id"]:
    add("requirement_set_mismatch")

for source_id, source in sorted(sources.items()):
    for requirement_id in source["requirement_ids"]:
        if requirement_id not in requirements:
            add(f"dangling_requirement_ref:{source_id}:{requirement_id}")
        elif source_id not in requirements[requirement_id]["source_ids"]:
            add(f"source_mapping_not_bidirectional:{source_id}:{requirement_id}")

for requirement_id, requirement in sorted(requirements.items()):
    for source_id in requirement["source_ids"]:
        if source_id not in sources:
            add(f"dangling_source_ref:{requirement_id}:{source_id}")
        elif requirement_id not in sources[source_id]["requirement_ids"]:
            add(f"source_mapping_not_bidirectional:{source_id}:{requirement_id}")
    quotes = {
        sources[source_id]["verbatim_quote"]
        for source_id in requirement["source_ids"]
        if source_id in sources
    }
    exact_quote = requirement["acceptance"]["exact_source_quote"]
    if not quotes or quotes != {exact_quote}:
        add(f"exact_quote_mismatch:{requirement_id}")

for requirement_id in sorted(set(requirements) - set(deliveries)):
    add(f"dangling_delivery_ref:{requirement_id}")
for requirement_id in sorted(set(deliveries) - set(requirements)):
    add(f"dangling_requirement_ref:receipt:{requirement_id}")


def parse_time(value, code):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        add(code)
        return None


def check_supersession_cycles():
    graph = {}
    for requirement_id, requirement in requirements.items():
        target = requirement["acceptance"].get("superseded_by")
        if target:
            graph[requirement_id] = target
            if target not in requirements:
                add(f"dangling_requirement_ref:{requirement_id}:{target}")
    visited = set()
    active = []
    active_set = set()

    def visit(node):
        if node in active_set:
            cycle_nodes = active[active.index(node):]
            add(f"cycle:{min(cycle_nodes)}")
            return
        if node in visited:
            return
        visited.add(node)
        active.append(node)
        active_set.add(node)
        target = graph.get(node)
        if target in requirements:
            visit(target)
        active.pop()
        active_set.remove(node)

    for node in sorted(requirements):
        visit(node)


check_supersession_cycles()

for requirement_id in sorted(set(requirements) & set(deliveries)):
    requirement = requirements[requirement_id]
    acceptance = requirement["acceptance"]
    delivery = deliveries[requirement_id]
    chain = delivery["coverage_chain"]
    actual_missing = [edge for edge in U4_EDGES if edge not in chain]
    declared_missing = sorted(delivery.get("missing_edges", []))
    if sorted(actual_missing) != declared_missing:
        add(f"missing_edge_declaration_mismatch:{requirement_id}")
    if delivery["coverage_status"] != "MET":
        for edge in sorted(set(actual_missing) | set(declared_missing)):
            add(f"missing_edge:{requirement_id}:{edge}")
        if not actual_missing:
            add(f"coverage_not_met:{requirement_id}")
        continue
    for edge in actual_missing:
        add(f"missing_edge:{requirement_id}:{edge}")
    if actual_missing:
        continue

    requirement_ref = chain["requirement"]
    if requirement_ref["requirement_id"] != requirement_id:
        add(f"requirement_identity_mismatch:{requirement_id}")
    if requirement_ref["requirement_set_id"] != requirements_doc["requirement_set_id"]:
        add(f"requirement_set_mismatch:{requirement_id}")
    quote_digest = "sha256:" + hashlib.sha256(
        acceptance["exact_source_quote"].encode("utf-8")
    ).hexdigest()
    if requirement_ref["source_quote_digest"] != quote_digest:
        add(f"source_quote_digest_mismatch:{requirement_id}")

    selected = acceptance["knowledge_selection"]
    if selected != chain["selected_knowledge"]:
        add(f"knowledge_selection_mismatch:{requirement_id}")
    started_at = parse_time(
        acceptance["implementation"]["started_at"],
        f"timestamp:{requirement_id}:implementation_started_at",
    )
    for kind in KNOWLEDGE_KINDS:
        for pin in selected[kind]:
            marker = f"{pin['id']} {pin['revision']}".casefold()
            if re.search(r"(^|[^a-z])(gap|unbound)([^a-z]|$)", marker):
                add(f"unbound_product_delivery:{requirement_id}:{kind}")
            if pin["revision"].strip().casefold() in {
                "main", "master", "head", "latest", "current", "pending"
            }:
                add(f"knowledge_revision_unpinned:{requirement_id}:{kind}")
            selected_at = parse_time(
                pin["selected_at"],
                f"timestamp:{requirement_id}:{kind}:selected_at",
            )
            if selected_at is not None and started_at is not None and selected_at >= started_at:
                add(f"knowledge_selected_post_hoc:{requirement_id}:{kind}")

    evidence_text = " ".join((
        acceptance["evidence"]["method"],
        acceptance.get("production_acceptance_criterion", ""),
    )).casefold()
    has_tool_only = any(token in evidence_text for token in ("tool", "cli", "ci", "docs", "ledger", "unit test"))
    has_visitor_production = any(token in evidence_text for token in ("visitor", "production", "public", "live", "browser"))
    delta = chain["implementation_delta"]
    live = chain["live_evidence"]
    if acceptance["visitor_visible"]:
        if has_tool_only and not has_visitor_production:
            add(f"tool_only_visible_acceptance:{requirement_id}")
        if delta["visitor_visible_count"] < 1 or not delta["visitor_visible_changes"]:
            add(f"zero_visitor_visible_delta:{requirement_id}")
        if not live["visitor_visible"]:
            add(f"visitor_production_evidence_missing:{requirement_id}")
    if delta["visitor_visible_count"] != len(delta["visitor_visible_changes"]):
        add(f"visitor_visible_count_mismatch:{requirement_id}")
    if delta["enabling_count"] != len(delta["enabling_changes"]):
        add(f"enabling_count_mismatch:{requirement_id}")

    if acceptance["applicability"]["painted_matrix_applicable"]:
        matrix = {
            (cell["locale"], cell["viewport"], cell["theme"])
            for cell in live["painted_matrix"]
        }
        if not live["painted_matrix_applicable"] or matrix != PAINTED_MATRIX or len(live["painted_matrix"]) != 8:
            add(f"painted_matrix_incomplete:{requirement_id}")

    merged = chain["merged_revision"]
    deployed = chain["deployed_revision"]
    accepted_revisions = {
        acceptance["implementation"]["code_revision"],
        acceptance["implementation"]["content_revision"],
    }
    if merged["revision"] not in accepted_revisions:
        add(f"accepted_revision_mismatch:{requirement_id}")
    if deployed["revision"] != merged["revision"] or deployed["digest"] != merged["digest"]:
        add(f"production_revision_mismatch:{requirement_id}")
    disposition = chain["customer_disposition"]
    if disposition["status"] not in ("accepted", "superseded"):
        add(f"customer_disposition_not_closed:{requirement_id}")
    if acceptance["disposition"] != disposition["status"]:
        add(f"customer_disposition_mismatch:{requirement_id}")

    times = [
        started_at,
        parse_time(chain["red_green"]["red"]["observed_at"], f"timestamp:{requirement_id}:red"),
        parse_time(chain["red_green"]["green"]["observed_at"], f"timestamp:{requirement_id}:green"),
        parse_time(merged["merged_at"], f"timestamp:{requirement_id}:merged"),
        parse_time(deployed["deployed_at"], f"timestamp:{requirement_id}:deployed"),
        parse_time(live["observed_at"], f"timestamp:{requirement_id}:live"),
        parse_time(disposition["recorded_at"], f"timestamp:{requirement_id}:disposition"),
    ]
    if all(value is not None for value in times):
        if any(left > right for left, right in zip(times, times[1:])):
            add(f"timestamp_chain_mismatch:{requirement_id}")

receipt_epics = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "epic"
}
receipt_tasks = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "task"
}
receipt_sets = {
    link["id"] for link in receipt_doc["parent_links"] if link["relation"] == "requirement_set"
}
expected_task_links = {
    requirement["acceptance"]["implementation"]["task_id"]
    for requirement in requirements.values()
}
if not receipt_epics:
    add("dangling_parent_ref:epic")
if not expected_task_links.issubset(receipt_tasks):
    add("dangling_parent_ref:task")
if requirements_doc["requirement_set_id"] not in receipt_sets:
    add("dangling_parent_ref:requirement_set")

review_links = {(link["relation"], link["id"]) for link in review_doc["parent_links"]}
review_requirement = review_doc["requirement_id"]
if review_requirement not in requirements:
    add(f"dangling_requirement_ref:review:{review_requirement}")
if review_doc["delivery_receipt_id"] != receipt_doc["receipt_id"]:
    add("review_receipt_mismatch")
if review_doc["product_fix"]["requirement_id"] != review_requirement:
    add(f"review_product_requirement_mismatch:{review_requirement}")
if review_doc["product_fix"]["delivery_receipt_id"] != receipt_doc["receipt_id"]:
    add("review_product_receipt_mismatch")
if review_doc["product_fix"]["status"] != "DELIVERED":
    add(f"parent_review_not_closed:{review_requirement}")
required_review_links = {
    ("requirement", review_requirement),
    ("delivery_receipt", receipt_doc["receipt_id"]),
}
required_review_links.update(("epic", epic) for epic in receipt_epics)
required_review_links.update(("task", task_id) for task_id in expected_task_links)
for relation, identifier in sorted(required_review_links - review_links):
    add(f"dangling_parent_ref:review:{relation}:{identifier}")

all_children_met = bool(deliveries) and all(
    item["coverage_status"] == "MET"
    and item["coverage_chain"].get("customer_disposition", {}).get("status") in ("accepted", "superseded")
    for item in deliveries.values()
)
epic_status = "MET" if receipt_epics and all_children_met else "NOT_MET"
if findings:
    emit("NOT_MET", 1, epic_status)
emit("MET", 0, epic_status)
PY
