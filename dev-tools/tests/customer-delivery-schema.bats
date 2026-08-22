#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    PYTHON="${CUSTOMER_SCHEMA_PYTHON:-python3}"
    REQUIREMENTS_SCHEMA="${ROOT}/config/customer-requirement.schema.json"
    RECEIPT_SCHEMA="${ROOT}/config/customer-delivery-receipt.schema.json"
    EVOLUTION_SCHEMA="${ROOT}/config/review-evolution.schema.json"
    REQUIREMENTS_TEMPLATE="${ROOT}/templates/customer-requirements-template.yaml"
    RECEIPT_TEMPLATE="${ROOT}/templates/customer-delivery-receipt-template.yaml"
    EVOLUTION_TEMPLATE="${ROOT}/templates/review-evolution-template.yaml"

    for schema in "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$EVOLUTION_SCHEMA"; do
        if [ ! -f "$schema" ]; then
            echo "missing schema: $schema" >&2
            return 1
        fi
    done

    if ! "$PYTHON" -c 'import jsonschema, yaml; assert "date-time" in jsonschema.FormatChecker().checkers' >/dev/null 2>&1; then
        echo "ERROR: required Python schema dependencies unavailable: jsonschema, PyYAML, and jsonschema date-time format support" >&2
        return 1
    fi
}

validate_yaml() {
    "$PYTHON" - "$1" "$2" <<'PY'
import json
import sys

import jsonschema
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    schema = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    instance = yaml.safe_load(handle)

format_checker = jsonschema.FormatChecker()

jsonschema.Draft202012Validator.check_schema(schema)
jsonschema.Draft202012Validator(
    schema,
    format_checker=format_checker,
).validate(instance)
PY
}

reject_mutation() {
    local schema="$1"
    local template="$2"
    local expression="$3"
    local mutated="$BATS_TEST_TMPDIR/mutated.yaml"

    cp "$template" "$mutated" || return 2
    yq -i "$expression" "$mutated" || return 2
    validate_yaml "$schema" "$mutated"
}

structured_requirement_fixture() {
    local target="$1"

    cp "$REQUIREMENTS_TEMPLATE" "$target" || return 2
    construct_placeholder_approvals "$target"
}

construct_placeholder_approvals() {
    "$PYTHON" - "$1" <<'PY'
import hashlib
import json
import sys

import yaml

APPROVAL_FIELDS = (
    "approved_digest",
    "authority_id",
    "authority_role",
    "approved_at",
    "evidence_ref",
    "algorithm",
    "key_id",
)


def jcs_bytes(payload):
    # RFC 8785-compatible for these fixed ASCII object keys and schema values.
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def seal_placeholder_approval(approval, approved_digest):
    approval["approved_digest"] = approved_digest
    payload = {field: approval[field] for field in APPROVAL_FIELDS}
    approval["approval_payload_digest"] = (
        "sha256:" + hashlib.sha256(jcs_bytes(payload)).hexdigest()
    )


path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
for source in document["source_remarks"]:
    seal_placeholder_approval(source["authority_approval"], source["source_digest"])
    for assertion in source["tier1_assertions"]:
        seal_placeholder_approval(
            assertion["authority_approval"], assertion["assertion_digest"]
        )
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
PY
}

refresh_assertion_digests() {
    "$PYTHON" - "$1" <<'PY'
import hashlib
import json
import sys

import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = yaml.safe_load(handle)
for source in document["source_remarks"]:
    source_payload = {
        "source_id": source["source_id"],
        "revision": source["revision"],
        "source_tier": source["source_tier"],
        "verbatim_quote": source["verbatim_quote"],
        "captured_at": source["captured_at"],
        "requirement_ids": sorted(source["requirement_ids"]),
    }
    for optional_field in ("locale", "source_ref", "supersedes_source_digest"):
        if optional_field in source:
            source_payload[optional_field] = source[optional_field]
    canonical_source = json.dumps(
        source_payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    source_digest = "sha256:" + hashlib.sha256(canonical_source).hexdigest()
    source["source_digest"] = source_digest
    # Updating approved_digest deliberately invalidates the existing approval
    # payload commitment; only construct_placeholder_approvals creates fixtures.
    source["authority_approval"]["approved_digest"] = source_digest
    for assertion in source["tier1_assertions"]:
        assertion["source_digest"] = source_digest
        payload = {
            key: value
            for key, value in assertion.items()
            if key not in {"assertion_digest", "authority_approval"}
        }
        canonical = json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        digest = "sha256:" + hashlib.sha256(canonical).hexdigest()
        assertion["assertion_digest"] = digest
        assertion["authority_approval"]["approved_digest"] = digest
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(document, handle, allow_unicode=True, sort_keys=False)
PY
}

validate_source_history() {
    "$PYTHON" - "$1" "$2" <<'PY'
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    before = yaml.safe_load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    after = yaml.safe_load(handle)

before_sources = {
    source["source_digest"]: source for source in before["source_remarks"]
}
after_sources = {
    source["source_digest"]: source for source in after["source_remarks"]
}
if len(after_sources) != len(after["source_remarks"]):
    raise SystemExit("SOURCE_HISTORY_AFTER_DIGEST_DUPLICATE")

for source_digest, prior_source in before_sources.items():
    if source_digest not in after_sources:
        raise SystemExit(f"SOURCE_HISTORY_PRIOR_DIGEST_DELETED:{source_digest}")
    if after_sources[source_digest] != prior_source:
        raise SystemExit(f"SOURCE_HISTORY_PRIOR_RECORD_MUTATED:{source_digest}")

new_sources = [
    source
    for source_digest, source in after_sources.items()
    if source_digest not in before_sources
]
if not new_sources:
    raise SystemExit("SOURCE_HISTORY_CORRECTION_NOT_APPENDED")
if not any(
    source.get("supersedes_source_digest") in before_sources
    for source in new_sources
):
    raise SystemExit("SOURCE_HISTORY_CORRECTION_SUPERSEDES_PRIOR_MISSING")
PY
}

validate_requirement_contract() {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$1" <<'PY'
import hashlib
import json
import sys
from datetime import datetime

import jsonschema
import yaml

APPROVAL_FIELDS = (
    "approved_digest",
    "authority_id",
    "authority_role",
    "approved_at",
    "evidence_ref",
    "algorithm",
    "key_id",
)


def jcs_bytes(payload):
    # RFC 8785-compatible for these fixed ASCII object keys and schema values.
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def approval_payload_digest(approval):
    payload = {field: approval[field] for field in APPROVAL_FIELDS}
    return "sha256:" + hashlib.sha256(jcs_bytes(payload)).hexdigest()

with open(sys.argv[1], encoding="utf-8") as handle:
    schema = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    instance = yaml.safe_load(handle)

try:
    jsonschema.Draft202012Validator(
        schema,
        format_checker=jsonschema.FormatChecker(),
    ).validate(instance)
except jsonschema.ValidationError as exc:
    location = ".".join(str(part) for part in exc.absolute_path) or "$"
    raise SystemExit(f"SCHEMA_REJECTED:{location}:{exc.message}") from None

sources = {}
assertions = {}
assertions_by_requirement = {}
for source in instance["source_remarks"]:
    source_id = source["source_id"]
    if source_id in sources:
        raise SystemExit(f"TIER1_AUTHORITY_DUPLICATE:{source_id}")
    sources[source_id] = source
    source_payload = {
        "source_id": source["source_id"],
        "revision": source["revision"],
        "source_tier": source["source_tier"],
        "verbatim_quote": source["verbatim_quote"],
        "captured_at": source["captured_at"],
        "requirement_ids": sorted(source["requirement_ids"]),
    }
    for optional_field in ("locale", "source_ref", "supersedes_source_digest"):
        if optional_field in source:
            source_payload[optional_field] = source[optional_field]
    canonical_source = jcs_bytes(source_payload)
    expected_source_digest = "sha256:" + hashlib.sha256(canonical_source).hexdigest()
    if source["source_digest"] != expected_source_digest:
        raise SystemExit(f"SOURCE_DIGEST_MISMATCH:{source_id}")
    source_approval = source["authority_approval"]
    if source_approval["approved_digest"] != source["source_digest"]:
        raise SystemExit(f"SOURCE_APPROVAL_DIGEST_MISMATCH:{source_id}")
    if source_approval["approval_payload_digest"] != approval_payload_digest(
        source_approval
    ):
        raise SystemExit(f"SOURCE_APPROVAL_PAYLOAD_DIGEST_MISMATCH:{source_id}")
    for assertion in source["tier1_assertions"]:
        assertion_id = assertion["assertion_id"]
        if assertion_id in assertions:
            raise SystemExit(f"TIER1_ASSERTION_DUPLICATE:{assertion_id}")
        requirement_id = assertion["requirement_id"]
        assertions[assertion_id] = (source_id, assertion)
        assertions_by_requirement.setdefault(requirement_id, set()).add(assertion_id)

source_digests = {source["source_digest"] for source in sources.values()}
for source_id, source in sources.items():
    superseded_digest = source.get("supersedes_source_digest")
    if superseded_digest is not None and superseded_digest not in source_digests:
        raise SystemExit(
            f"SOURCE_SUPERSEDED_DIGEST_DANGLING:{source_id}:{superseded_digest}"
        )

requirements = instance["requirements"]
for source_id, source in sources.items():
    asserted_requirements = {
        assertion["requirement_id"] for assertion in source["tier1_assertions"]
    }
    for requirement_id in source["requirement_ids"]:
        if requirement_id not in requirements:
            raise SystemExit(
                f"TIER1_REQUIREMENT_DANGLING:{source_id}:{requirement_id}"
            )
    if asserted_requirements != set(source["requirement_ids"]):
        raise SystemExit(f"TIER1_SOURCE_ASSERTION_MAPPING:{source_id}")

for requirement_id, requirement in requirements.items():
    acceptance = requirement["acceptance"]
    for knowledge_kind, selections in acceptance["knowledge_selection"].items():
        for selection in selections:
            for identity_field in ("id", "revision"):
                identity_value = selection[identity_field]
                if identity_value.casefold() in {"gap", "unbound"}:
                    raise SystemExit(
                        "KNOWLEDGE_SELECTION_GAP_UNBOUND:"
                        f"{requirement_id}:{knowledge_kind}:{identity_field}:"
                        f"{identity_value}"
                    )
    for source_id in requirement["source_ids"]:
        if source_id not in sources:
            raise SystemExit(f"TIER1_SOURCE_DANGLING:{requirement_id}:{source_id}")
        if requirement_id not in sources[source_id]["requirement_ids"]:
            raise SystemExit(f"TIER1_SOURCE_NOT_RECIPROCAL:{requirement_id}:{source_id}")

    referenced_assertion_ids = set(requirement["tier1_assertion_ids"])
    authoritative_assertion_ids = assertions_by_requirement.get(requirement_id, set())
    if referenced_assertion_ids != authoritative_assertion_ids:
        raise SystemExit(f"TIER1_ASSERTION_MAPPING_MISMATCH:{requirement_id}")
    authoritative_source_ids = {
        assertions[assertion_id][0] for assertion_id in referenced_assertion_ids
    }
    if authoritative_source_ids != set(requirement["source_ids"]):
        raise SystemExit(f"TIER1_SOURCE_ASSERTION_MAPPING:{requirement_id}")

    assertion_id = acceptance["tier1_assertion_id"]
    if assertion_id not in assertions:
        raise SystemExit(f"TIER1_ASSERTION_DANGLING:{assertion_id}")
    if assertion_id not in referenced_assertion_ids:
        raise SystemExit(
            f"TIER1_ASSERTION_REPLACED:{requirement_id}:{assertion_id}"
        )
    implementation_started_at = datetime.fromisoformat(
        acceptance["implementation"]["started_at"].replace("Z", "+00:00")
    )
    for linked_assertion_id in referenced_assertion_ids:
        linked_source_id, linked_assertion = assertions[linked_assertion_id]
        if linked_assertion["source_digest"] != sources[linked_source_id]["source_digest"]:
            raise SystemExit(
                f"ASSERTION_SOURCE_DIGEST_MISMATCH:{linked_assertion_id}"
            )
        canonical_payload = {
            key: value
            for key, value in linked_assertion.items()
            if key not in {"assertion_digest", "authority_approval"}
        }
        canonical_bytes = jcs_bytes(canonical_payload)
        expected_digest = "sha256:" + hashlib.sha256(canonical_bytes).hexdigest()
        if linked_assertion["assertion_digest"] != expected_digest:
            raise SystemExit(
                f"TIER1_ASSERTION_DIGEST_MISMATCH:{linked_assertion_id}"
            )
        approval = linked_assertion["authority_approval"]
        if approval["approved_digest"] != linked_assertion["assertion_digest"]:
            raise SystemExit(
                f"TIER1_APPROVAL_DIGEST_MISMATCH:{linked_assertion_id}"
            )
        if approval["approval_payload_digest"] != approval_payload_digest(approval):
            raise SystemExit(
                f"TIER1_APPROVAL_PAYLOAD_DIGEST_MISMATCH:{linked_assertion_id}"
            )
        approved_at = datetime.fromisoformat(
            approval["approved_at"].replace("Z", "+00:00")
        )
        if approved_at >= implementation_started_at:
            raise SystemExit(
                f"TIER1_APPROVAL_NOT_BEFORE_IMPLEMENTATION:{linked_assertion_id}"
            )
    provided_quotes = {}
    for quote_row in acceptance["exact_source_quotes"]:
        source_id = quote_row["source_id"]
        if source_id in provided_quotes:
            raise SystemExit(
                f"TIER1_QUOTE_SOURCE_DUPLICATE:{requirement_id}:{source_id}"
            )
        provided_quotes[source_id] = quote_row["verbatim_quote"]
    expected_quotes = {
        source_id: sources[source_id]["verbatim_quote"]
        for source_id in authoritative_source_ids
    }
    if provided_quotes != expected_quotes:
        raise SystemExit(f"TIER1_QUOTE_SET_MISMATCH:{requirement_id}")

    accepted_scope = acceptance["applicability"]
    for linked_assertion_id in referenced_assertion_ids:
        _, assertion = assertions[linked_assertion_id]
        if acceptance["predicate_id"] != assertion["predicate_id"]:
            raise SystemExit(f"TIER1_PREDICATE_CHANGED:{requirement_id}")
        if acceptance["product"] != assertion["product"]:
            raise SystemExit(f"TIER1_PRODUCT_CHANGED:{requirement_id}")
        if acceptance["surface"] != assertion["surface"]:
            raise SystemExit(f"TIER1_SURFACE_CHANGED:{requirement_id}")
        asserted_scope = assertion["applicability"]
        for dimension in ("locales", "viewports", "themes"):
            omitted = set(asserted_scope[dimension]) - set(accepted_scope[dimension])
            if omitted:
                raise SystemExit(
                    f"TIER1_SCOPE_WEAKENED:{requirement_id}:{dimension}:"
                    + ",".join(sorted(omitted))
                )
        if assertion["visitor_visible"] and not acceptance["visitor_visible"]:
            raise SystemExit(f"TIER1_VISITOR_VISIBLE_WEAKENED:{requirement_id}")
        if acceptance["surface_class"] != assertion["surface_class"]:
            raise SystemExit(f"TIER1_SURFACE_CLASS_CHANGED:{requirement_id}")
        if (
            asserted_scope["painted_matrix_applicable"]
            and not accepted_scope["painted_matrix_applicable"]
        ):
            raise SystemExit(
                f"TIER1_PAINTED_APPLICABILITY_WEAKENED:{requirement_id}"
            )

    production = acceptance.get("production_assertion")
    if production is not None:
        for identity in ("product", "surface", "surface_class", "predicate_id"):
            if production[identity] != acceptance[identity]:
                raise SystemExit(
                    f"PRODUCTION_ASSERTION_IDENTITY_CHANGED:{requirement_id}:{identity}"
                )
        production_scope = production["applicability"]
        for dimension in ("locales", "viewports", "themes"):
            if set(production_scope[dimension]) != set(accepted_scope[dimension]):
                raise SystemExit(
                    f"PRODUCTION_ASSERTION_SCOPE_CHANGED:{requirement_id}:{dimension}"
                )
        if (
            production_scope["painted_matrix_applicable"]
            != accepted_scope["painted_matrix_applicable"]
        ):
            raise SystemExit(
                f"PRODUCTION_ASSERTION_SCOPE_CHANGED:{requirement_id}:painted"
            )

    method = acceptance["evidence"]["method"]
    if isinstance(method, dict):
        for identity in ("product", "surface", "surface_class", "predicate_id"):
            if method[identity] != acceptance[identity]:
                raise SystemExit(
                    f"VISITOR_METHOD_IDENTITY_CHANGED:{requirement_id}:{identity}"
                )
        method_scope = method["applicability"]
        for dimension in ("locales", "viewports", "themes"):
            if set(method_scope[dimension]) != set(accepted_scope[dimension]):
                raise SystemExit(
                    f"VISITOR_METHOD_SCOPE_CHANGED:{requirement_id}:{dimension}"
                )
        if (
            method_scope["painted_matrix_applicable"]
            != accepted_scope["painted_matrix_applicable"]
        ):
            raise SystemExit(
                f"VISITOR_METHOD_SCOPE_CHANGED:{requirement_id}:painted"
            )

    rendered_test = acceptance.get("rendered_test_evidence")
    if rendered_test is not None:
        for identity in ("product", "surface", "predicate_id"):
            if rendered_test[identity] != acceptance[identity]:
                raise SystemExit(
                    f"RENDERED_TEST_IDENTITY_CHANGED:{requirement_id}:{identity}"
                )
        rendered_scope = rendered_test["applicability"]
        for dimension in ("locales", "viewports", "themes"):
            if set(rendered_scope[dimension]) != set(accepted_scope[dimension]):
                raise SystemExit(
                    f"RENDERED_TEST_SCOPE_CHANGED:{requirement_id}:{dimension}"
                )
        if (
            rendered_scope["painted_matrix_applicable"]
            != accepted_scope["painted_matrix_applicable"]
        ):
            raise SystemExit(
                f"RENDERED_TEST_SCOPE_CHANGED:{requirement_id}:painted"
            )
        rendered_at = datetime.fromisoformat(
            rendered_test["observed_at"].replace("Z", "+00:00")
        )
        if rendered_at < implementation_started_at:
            raise SystemExit(f"RENDERED_TEST_BEFORE_IMPLEMENTATION:{requirement_id}")

    if acceptance["disposition"] == "superseded":
        superseded_by = acceptance["superseded_by"]
        if superseded_by not in requirements:
            raise SystemExit(
                f"SUPERSESSION_TARGET_DANGLING:{requirement_id}:{superseded_by}"
            )
PY
}

reject_contract_mutation() {
    local expression="$1"
    local mutated="$BATS_TEST_TMPDIR/structured-requirement.yaml"

    structured_requirement_fixture "$mutated" || return 2
    yq -i "$expression" "$mutated" || return 2
    validate_requirement_contract "$mutated"
}

two_source_requirement_fixture() {
    local target="$1"

    structured_requirement_fixture "$target" || return 2
    yq -i '
        .source_remarks += [.source_remarks[0]] |
        .source_remarks[1].source_id = "source-0002" |
        .source_remarks[1].verbatim_quote = "The comparison must also remain legible for desktop visitors." |
        .source_remarks[1].captured_at = "2026-01-02T09:01:00Z" |
        .source_remarks[1].source_ref = "customer-interview-0002" |
        .source_remarks[1].tier1_assertions[0].assertion_id = "assertion-0002" |
        .source_remarks[1].tier1_assertions[0].asserted_at = "2026-01-02T09:01:00Z" |
        .requirements.req-0001.source_ids += ["source-0002"] |
        .requirements.req-0001.tier1_assertion_ids += ["assertion-0002"] |
        .requirements.req-0001.acceptance.exact_source_quotes = [
          {
            "source_id": "source-0001",
            "verbatim_quote": "The comparison must remain readable on my phone in both languages and themes."
          },
          {
            "source_id": "source-0002",
            "verbatim_quote": "The comparison must also remain legible for desktop visitors."
          }
        ] |
        del(.requirements.req-0001.acceptance.exact_source_quote)
    ' "$target" || return 2
    refresh_assertion_digests "$target" || return 2
    construct_placeholder_approvals "$target" || return 2
}

plural_receipt_fixture() {
    local target="$1"

    cp "$RECEIPT_TEMPLATE" "$target" || return 2
    yq -i '
        .requirements.req-0001.coverage_chain.requirement.source_quote_digests = [
          {
            "source_id": "source-0001",
            "digest": "sha256:02ea885890c5deec86bbc01bc6d5f123229ed11a38c8438c68dbc4235a415eb5"
          },
          {
            "source_id": "source-0002",
            "digest": "sha256:e9e1afff11ff27a1422054ca44320e5cf45e7a73601a95f5fcaf1b8a43eb092f"
          }
        ] |
        del(.requirements.req-0001.coverage_chain.requirement.source_quote_digest)
    ' "$target" || return 2
}

validate_receipt_digest_contract() {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$1" "$2" <<'PY'
import hashlib
import json
import sys

import jsonschema
import yaml

requirements_schema_path, receipt_schema_path, requirements_path, receipt_path = sys.argv[1:]
with open(requirements_schema_path, encoding="utf-8") as handle:
    requirements_schema = json.load(handle)
with open(receipt_schema_path, encoding="utf-8") as handle:
    receipt_schema = json.load(handle)
with open(requirements_path, encoding="utf-8") as handle:
    requirements_document = yaml.safe_load(handle)
with open(receipt_path, encoding="utf-8") as handle:
    receipt_document = yaml.safe_load(handle)

checker = jsonschema.FormatChecker()
jsonschema.Draft202012Validator(requirements_schema, format_checker=checker).validate(
    requirements_document
)
jsonschema.Draft202012Validator(receipt_schema, format_checker=checker).validate(
    receipt_document
)

sources = {
    source["source_id"]: source["verbatim_quote"]
    for source in requirements_document["source_remarks"]
}
for requirement_id, requirement in requirements_document["requirements"].items():
    expected_source_ids = set(requirement["source_ids"])
    receipt_requirement = receipt_document["requirements"][requirement_id]
    digest_rows = receipt_requirement["coverage_chain"]["requirement"][
        "source_quote_digests"
    ]
    provided = {}
    for row in digest_rows:
        source_id = row["source_id"]
        if source_id in provided:
            raise SystemExit(
                f"SOURCE_QUOTE_DIGEST_SOURCE_DUPLICATE:{requirement_id}:{source_id}"
            )
        provided[source_id] = row["digest"]
    if set(provided) != expected_source_ids:
        raise SystemExit(f"SOURCE_QUOTE_DIGEST_SET_MISMATCH:{requirement_id}")
    for source_id in sorted(expected_source_ids):
        expected_digest = "sha256:" + hashlib.sha256(
            sources[source_id].encode("utf-8")
        ).hexdigest()
        if provided[source_id] != expected_digest:
            raise SystemExit(
                f"SOURCE_QUOTE_DIGEST_CONTENT_MISMATCH:{requirement_id}:{source_id}"
            )
PY
}

validate_review_closure_contract() {
    local review_state="$1"
    local requested_task_state="$2"

    case "$review_state:$requested_task_state" in
        OPEN:CLOSED|CHANGES_REQUESTED:CLOSED)
            echo "ORIGINATING_REVIEW_BLOCKS_CLOSURE:${review_state}"
            return 1
            ;;
    esac
}

validate_requirement_receipt_key_contract() {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$1" "$2" <<'PY'
import json
import sys

import jsonschema
import yaml

requirements_schema_path, receipt_schema_path, requirements_path, receipt_path = sys.argv[1:]
with open(requirements_schema_path, encoding="utf-8") as handle:
    requirements_schema = json.load(handle)
with open(receipt_schema_path, encoding="utf-8") as handle:
    receipt_schema = json.load(handle)
with open(requirements_path, encoding="utf-8") as handle:
    requirements_document = yaml.safe_load(handle)
with open(receipt_path, encoding="utf-8") as handle:
    receipt_document = yaml.safe_load(handle)

checker = jsonschema.FormatChecker()
jsonschema.Draft202012Validator(requirements_schema, format_checker=checker).validate(
    requirements_document
)
jsonschema.Draft202012Validator(receipt_schema, format_checker=checker).validate(
    receipt_document
)
requirement_keys = set(requirements_document["requirements"])
receipt_keys = set(receipt_document["requirements"])
if requirement_keys != receipt_keys:
    difference = sorted(requirement_keys ^ receipt_keys)
    raise SystemExit(f"REQUIREMENT_RECEIPT_KEY_SET_MISMATCH:{','.join(difference)}")
PY
}

validate_acceptance_receipt_authority_contract() {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$1" "$2" <<'PY'
import json
import sys
from datetime import datetime

import jsonschema
import yaml

requirements_schema_path, receipt_schema_path, requirements_path, receipt_path = sys.argv[1:]
with open(requirements_schema_path, encoding="utf-8") as handle:
    requirements_schema = json.load(handle)
with open(receipt_schema_path, encoding="utf-8") as handle:
    receipt_schema = json.load(handle)
with open(requirements_path, encoding="utf-8") as handle:
    requirements_document = yaml.safe_load(handle)
with open(receipt_path, encoding="utf-8") as handle:
    receipt_document = yaml.safe_load(handle)

checker = jsonschema.FormatChecker()
jsonschema.Draft202012Validator(requirements_schema, format_checker=checker).validate(
    requirements_document
)
jsonschema.Draft202012Validator(receipt_schema, format_checker=checker).validate(
    receipt_document
)
for requirement_id, requirement in requirements_document["requirements"].items():
    acceptance = requirement["acceptance"]
    receipt_chain = receipt_document["requirements"][requirement_id]["coverage_chain"]
    disposition = receipt_chain["customer_disposition"]
    if (
        acceptance["visitor_visible"]
        and disposition["authority"]["authority_role"] != "OPERATOR"
    ):
        raise SystemExit(
            f"VISITOR_DISPOSITION_OPERATOR_REQUIRED:{requirement_id}"
        )
    rendered_at = datetime.fromisoformat(
        acceptance["rendered_test_evidence"]["observed_at"].replace("Z", "+00:00")
    )
    live_at = datetime.fromisoformat(
        receipt_chain["live_evidence"]["observed_at"].replace("Z", "+00:00")
    )
    if rendered_at > live_at:
        raise SystemExit(f"RENDERED_TEST_AFTER_LIVE_EVIDENCE:{requirement_id}")
PY
}

assert_semantic_invariant_registries() {
    "$PYTHON" - "$1" "$2" "$3" <<'PY'
import json
import sys

expected = {
    sys.argv[1]: {
        "description": "Draft 2020-12 validates shape only; the deterministic customer-delivery validator must enforce every registered cross-record invariant.",
        "enforcer": "customer-delivery-validator",
        "invariant_ids": [
            "source-id-unique",
            "assertion-id-unique",
            "source-requirement-bidirectional",
            "source-assertion-bidirectional",
            "source-quote-set-exact",
            "source-canonical-digest-valid",
            "source-approval-digest-equals-source-digest",
            "source-approval-payload-canonical-digest-valid",
            "source-signature-valid",
            "source-signature-over-approval-payload-digest-valid",
            "source-approval-key-known",
            "source-approval-key-authority-id-equal",
            "source-approval-key-role-authorized",
            "source-approval-key-active",
            "source-approval-key-valid-at-approval",
            "assertion-source-digest-equals-containing-source-digest",
            "source-correction-superseded-digest-exists",
            "source-correction-prior-record-retained",
            "source-correction-in-place-replacement-prohibited",
            "source-history-prior-digest-set-retained",
            "source-history-prior-record-content-immutable",
            "source-correction-appended-record-supersedes-prior-digest",
            "tier1-assertion-canonical-digest-valid",
            "tier1-assertion-approval-digest-equals-assertion-digest",
            "tier1-assertion-approval-payload-canonical-digest-valid",
            "tier1-assertion-signature-valid",
            "tier1-assertion-signature-over-approval-payload-digest-valid",
            "tier1-assertion-approval-key-known",
            "tier1-assertion-approval-key-authority-id-equal",
            "tier1-assertion-approval-key-role-authorized",
            "tier1-assertion-approval-key-active",
            "tier1-assertion-approval-key-valid-at-approval",
            "tier1-authority-approval-before-implementation",
            "tier1-assertion-correction-append-only",
            "source-verbatim-to-assertion-authority-approval-required",
            "assertion-acceptance-predicate-equal",
            "assertion-acceptance-product-equal",
            "assertion-acceptance-surface-equal",
            "assertion-acceptance-surface-class-equal",
            "acceptance-applicability-superset",
            "acceptance-visitor-visible-nonweakening",
            "acceptance-painted-applicability-nonweakening",
            "production-acceptance-product-equal",
            "production-acceptance-surface-equal",
            "production-acceptance-surface-class-equal",
            "production-acceptance-predicate-equal",
            "production-acceptance-applicability-equal",
            "evidence-acceptance-product-equal",
            "evidence-acceptance-surface-equal",
            "evidence-acceptance-surface-class-equal",
            "evidence-acceptance-predicate-equal",
            "evidence-acceptance-applicability-equal",
            "rendered-test-acceptance-product-equal",
            "rendered-test-acceptance-surface-equal",
            "rendered-test-acceptance-predicate-equal",
            "rendered-test-acceptance-applicability-equal",
            "rendered-test-observed-after-implementation-start",
            "knowledge-selection-id-unique-across-kinds",
            "knowledge-selection-revision-immutable",
            "knowledge-selection-revision-not-branch-ref",
            "knowledge-selection-gap-unbound-prohibited",
            "knowledge-selection-before-implementation",
            "supersession-target-exists",
            "supersession-graph-acyclic",
        ],
    },
    sys.argv[2]: {
        "description": "Draft 2020-12 validates shape only; the deterministic customer-delivery validator must enforce every registered cross-record invariant.",
        "enforcer": "customer-delivery-validator",
        "invariant_ids": [
            "receipt-requirement-key-equals-embedded-id",
            "receipt-requirement-key-set-equals-requirement-document-key-set",
            "receipt-top-requirement-set-equals-embedded-id",
            "receipt-source-quote-digest-set-exact",
            "receipt-selected-knowledge-set-exact",
            "receipt-implementation-task-equals-parent-task",
            "receipt-u4-edge-declaration-exact",
            "receipt-enabling-count-equals-list-cardinality",
            "receipt-visible-count-equals-list-cardinality",
            "receipt-live-product-equals-acceptance-product",
            "receipt-live-surface-equals-acceptance-surface",
            "receipt-live-surface-class-equals-acceptance-surface-class",
            "receipt-live-predicate-equals-acceptance-predicate",
            "receipt-live-applicability-equals-acceptance-applicability",
            "receipt-live-visitor-visible-equals-acceptance-visitor-visible",
            "receipt-zero-visible-rejected-for-user-facing",
            "receipt-painted-matrix-set-exact",
            "receipt-red-before-green",
            "receipt-green-before-merge",
            "receipt-merge-before-deploy",
            "receipt-deploy-before-matrix-observation",
            "receipt-matrix-observation-not-after-live-summary",
            "receipt-deploy-before-live",
            "receipt-live-before-disposition",
            "receipt-rendered-test-before-live-evidence",
            "receipt-merged-revision-accepted",
            "receipt-deployed-revision-equals-merged-revision",
            "receipt-deployed-digest-equals-merged-digest",
            "receipt-disposition-equals-requirement-disposition",
            "receipt-disposition-closure-exact",
            "receipt-visitor-acceptance-authority-role-operator",
            "receipt-parent-links-complete",
            "review-open-or-changes-requested-blocks-closure",
            "receipt-epic-status-derived",
            "receipt-user-facing-parent-has-visible-child",
        ],
    },
    sys.argv[3]: {
        "description": "Draft 2020-12 validates shape only; the deterministic review-evolution validator must enforce every registered cross-record invariant.",
        "enforcer": "review-evolution-validator",
        "invariant_ids": [
            "review-requirement-id-equals-product-fix-requirement-id",
            "review-receipt-id-equals-product-fix-receipt-id",
            "review-parent-links-complete",
            "review-open-or-changes-requested-blocks-closure",
            "review-product-fix-status-equals-receipt-delivery",
            "review-classification-canonical-change-exclusive",
            "review-no-canon-change-evidence-approved",
            "review-canonical-change-enforcement-red-capable",
            "review-product-fix-substitution-prohibited",
        ],
    },
}

for path, required_registry in expected.items():
    with open(path, encoding="utf-8") as handle:
        schema = json.load(handle)
    actual = schema.get("x-datarim-semantic-invariants")
    if actual != required_registry:
        raise SystemExit(
            f"SEMANTIC_INVARIANT_REGISTRY_MISMATCH:{path}:"
            f"expected={required_registry!r}:actual={actual!r}"
        )
PY
}

assert_signature_contract() {
    "$PYTHON" - "$1" <<'PY'
import json
import sys

expected = {
    "algorithm": "ED25519",
    "signed_field": "authority_approval.approval_payload_digest",
    "digest_framing": {
        "strip_prefix": "sha256:",
        "hex_pattern": "^[0-9a-f]{64}$",
        "decode": "LOWERCASE_HEX",
        "signed_message": "RAW_SHA256_DIGEST_BYTES",
        "signed_message_length_bytes": 32,
    },
    "signature_framing": {
        "field": "authority_approval.signature",
        "strip_prefix": "ed25519:",
        "decode": "RFC4648_STANDARD_BASE64",
        "canonical_padding": "REQUIRED",
        "decoded_length_bytes": 64,
    },
    "key_resolution": {
        "registry": "TRUSTED_AUTHORITY_KEY_REGISTRY",
        "lookup_by": "authority_approval.key_id",
        "unknown_key_policy": "FAIL_CLOSED",
        "binding_schema": {
            "type": "object",
            "additionalProperties": False,
            "required": [
                "key_id",
                "authority_id",
                "allowed_roles",
                "public_key",
                "status",
                "valid_from",
            ],
            "properties": {
                "key_id": {
                    "type": "string",
                    "pattern": "^key-[a-z0-9][a-z0-9-]*$",
                },
                "authority_id": {
                    "type": "string",
                    "pattern": "^authority-[a-z0-9][a-z0-9-]*$",
                },
                "allowed_roles": {
                    "type": "array",
                    "minItems": 1,
                    "uniqueItems": True,
                    "items": {"enum": ["CUSTOMER", "OPERATOR"]},
                },
                "public_key": {
                    "type": "string",
                    "pattern": "^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$",
                    "x-key-type": "ED25519_PUBLIC_KEY",
                    "x-encoding": "RFC4648_STANDARD_BASE64",
                    "x-canonical-padding": "REQUIRED",
                    "x-decoded-length-bytes": 32,
                },
                "status": {"enum": ["ACTIVE", "REVOKED"]},
                "valid_from": {"type": "string", "format": "date-time"},
                "valid_until": {"type": "string", "format": "date-time"},
            },
        },
        "validity_interval": {
            "valid_from": "INCLUSIVE",
            "valid_until": "EXCLUSIVE_WHEN_PRESENT",
        },
        "verification_sequence": [
            "KEY_ID_KNOWN",
            "APPROVAL_AUTHORITY_ID_EQUALS_KEY_AUTHORITY_ID",
            "APPROVAL_AUTHORITY_ROLE_IN_KEY_ALLOWED_ROLES",
            "KEY_STATUS_ACTIVE",
            "APPROVED_AT_INSIDE_KEY_VALIDITY",
            "CRYPTOGRAPHIC_SIGNATURE_VALID",
        ],
    },
    "verification_enforcer": "customer-delivery-validator",
}
with open(sys.argv[1], encoding="utf-8") as handle:
    actual = json.load(handle).get("x-datarim-signature-contract")
if actual != expected:
    raise SystemExit(
        f"SIGNATURE_CONTRACT_MISMATCH:expected={expected!r}:actual={actual!r}"
    )
PY
}

validate_trusted_authority_keys() {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$1" <<'PY'
import base64
import json
import sys
from datetime import datetime

import jsonschema
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    schema = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    document = yaml.safe_load(handle)

key_contract = schema["x-datarim-signature-contract"]["key_resolution"]
binding_schema = key_contract["binding_schema"]
public_key_contract = binding_schema["properties"]["public_key"]
public_key = "A" * 43 + "="
trusted_registry = {
    "key-customer-0001": {
        "key_id": "key-customer-0001",
        "authority_id": "authority-customer-0001",
        "allowed_roles": ["CUSTOMER"],
        "public_key": public_key,
        "status": "ACTIVE",
        "valid_from": "2026-01-01T00:00:00Z",
        "valid_until": "2027-01-01T00:00:00Z",
    },
    "key-revoked-0001": {
        "key_id": "key-revoked-0001",
        "authority_id": "authority-customer-0001",
        "allowed_roles": ["CUSTOMER"],
        "public_key": public_key,
        "status": "REVOKED",
        "valid_from": "2026-01-01T00:00:00Z",
        "valid_until": "2027-01-01T00:00:00Z",
    },
    "key-future-0001": {
        "key_id": "key-future-0001",
        "authority_id": "authority-customer-0001",
        "allowed_roles": ["CUSTOMER"],
        "public_key": public_key,
        "status": "ACTIVE",
        "valid_from": "2026-02-01T00:00:00Z",
    },
    "key-expired-0001": {
        "key_id": "key-expired-0001",
        "authority_id": "authority-customer-0001",
        "allowed_roles": ["CUSTOMER"],
        "public_key": public_key,
        "status": "ACTIVE",
        "valid_from": "2025-01-01T00:00:00Z",
        "valid_until": "2026-01-02T09:04:00Z",
    },
}

checker = jsonschema.FormatChecker()
for registry_key, binding in trusted_registry.items():
    jsonschema.Draft202012Validator(
        binding_schema,
        format_checker=checker,
    ).validate(binding)
    if binding["key_id"] != registry_key:
        raise SystemExit(f"TRUSTED_KEY_REGISTRY_INDEX_MISMATCH:{registry_key}")
    decoded_key = base64.b64decode(binding["public_key"], validate=True)
    if len(decoded_key) != public_key_contract["x-decoded-length-bytes"]:
        raise SystemExit(f"TRUSTED_KEY_LENGTH_MISMATCH:{registry_key}")
    if base64.b64encode(decoded_key).decode("ascii") != binding["public_key"]:
        raise SystemExit(f"TRUSTED_KEY_BASE64_NONCANONICAL:{registry_key}")


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_approval(kind, record_id, approval):
    key_id = approval["key_id"]
    binding = trusted_registry.get(key_id)
    if binding is None:
        raise SystemExit(f"{kind}_APPROVAL_KEY_UNKNOWN:{record_id}:{key_id}")
    if approval["authority_id"] != binding["authority_id"]:
        raise SystemExit(
            f"{kind}_APPROVAL_KEY_AUTHORITY_ID_MISMATCH:{record_id}:{key_id}"
        )
    if approval["authority_role"] not in binding["allowed_roles"]:
        raise SystemExit(
            f"{kind}_APPROVAL_KEY_ROLE_UNAUTHORIZED:{record_id}:"
            f"{approval['authority_role']}"
        )
    if binding["status"] != "ACTIVE":
        raise SystemExit(f"{kind}_APPROVAL_KEY_NOT_ACTIVE:{record_id}:{key_id}")
    approved_at = parse_timestamp(approval["approved_at"])
    valid_from = parse_timestamp(binding["valid_from"])
    if approved_at < valid_from:
        raise SystemExit(f"{kind}_APPROVAL_KEY_NOT_YET_VALID:{record_id}:{key_id}")
    if "valid_until" in binding and approved_at >= parse_timestamp(
        binding["valid_until"]
    ):
        raise SystemExit(f"{kind}_APPROVAL_KEY_EXPIRED:{record_id}:{key_id}")


for source in document["source_remarks"]:
    validate_approval("SOURCE", source["source_id"], source["authority_approval"])
    for assertion in source["tier1_assertions"]:
        validate_approval(
            "TIER1",
            assertion["assertion_id"],
            assertion["authority_approval"],
        )
PY
}

trusted_key_mutation_fixture() {
    local target="$1"
    local expression="$2"

    structured_requirement_fixture "$target" || return 2
    yq -i "$expression" "$target" || return 2
    construct_placeholder_approvals "$target"
}

@test "complete customer delivery examples validate against Draft 2020-12 schemas" {
    validate_requirement_contract "$REQUIREMENTS_TEMPLATE" \
        && validate_yaml "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        && validate_yaml "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        && validate_yaml "$EVOLUTION_SCHEMA" "$EVOLUTION_TEMPLATE"
}

@test "missing Python schema dependencies fail loud instead of skipping core validation" {
    local fake_python="$BATS_TEST_TMPDIR/python-without-schema-deps"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_python"
    chmod +x "$fake_python"

    run env CUSTOMER_SCHEMA_PYTHON="$fake_python" bats \
        --filter '^complete customer delivery examples' \
        "${BATS_TEST_DIRNAME}/customer-delivery-schema.bats"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"ERROR: required Python schema dependencies unavailable"* ]]
}

@test "every object-shaped schema node is closed" {
    run "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$EVOLUTION_SCHEMA" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        schema = json.load(handle)
    stack = [("$", schema)]
    while stack:
        location, node = stack.pop()
        if not isinstance(node, dict):
            continue
        if node.get("type") == "object" and node.get("additionalProperties") is not False:
            raise SystemExit(f"{path}:{location} is not closed")
        for key, value in node.items():
            if isinstance(value, dict):
                stack.append((f"{location}.{key}", value))
            elif isinstance(value, list):
                for index, item in enumerate(value):
                    if isinstance(item, dict):
                        stack.append((f"{location}.{key}[{index}]", item))
PY
    [ "$status" -eq 0 ]
}

@test "schemas publish the exact closed A2 and A3 semantic invariant registries" {
    assert_semantic_invariant_registries \
        "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$EVOLUTION_SCHEMA"
}

@test "requirement schema publishes the exact portable RFC 8785 canonicalization contract" {
    run "$PYTHON" - "$REQUIREMENTS_SCHEMA" <<'PY'
import json
import sys

expected = {
    "algorithm": "RFC8785",
    "scheme": "JCS",
    "encoding": "UTF-8",
    "unicode_normalization": "NONE",
    "object_member_order": "RFC8785_UTF16_CODE_UNIT_LEXICOGRAPHIC",
    "array_order": {
        "default": "PRESERVE_INPUT_ORDER",
        "sorted_set_like_fields": [
            {
                "payload": "sourceRemark",
                "field": "requirement_ids",
                "order": "ASCENDING_UNICODE_CODE_POINT",
            }
        ],
    },
    "digest_input": "RFC8785_CANONICAL_JSON_UTF8_BYTES_WITHOUT_DIGEST_PREFIX",
}

with open(sys.argv[1], encoding="utf-8") as handle:
    actual = json.load(handle).get("x-datarim-canonicalization")
if actual != expected:
    raise SystemExit(
        f"CANONICALIZATION_REGISTRY_MISMATCH:expected={expected!r}:actual={actual!r}"
    )
PY
    [ "$status" -eq 0 ]
}

@test "requirement schema publishes the exact closed Ed25519 wire framing contract" {
    assert_signature_contract "$REQUIREMENTS_SCHEMA"
}

@test "Ed25519 framing signs raw 32-byte digest rather than hex or prefixed UTF-8" {
    run "$PYTHON" - "$REQUIREMENTS_SCHEMA" <<'PY'
import base64
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    contract = json.load(handle)["x-datarim-signature-contract"]
field_value = "sha256:" + ("ab" * 32)
prefix = contract["digest_framing"]["strip_prefix"]
if not field_value.startswith(prefix):
    raise SystemExit("SIGNATURE_DIGEST_PREFIX_MISSING")
hex_text = field_value[len(prefix):]
raw_digest = bytes.fromhex(hex_text)
hex_utf8 = hex_text.encode("utf-8")
field_utf8 = field_value.encode("utf-8")
if len(raw_digest) != contract["digest_framing"]["signed_message_length_bytes"]:
    raise SystemExit(f"SIGNATURE_RAW_DIGEST_LENGTH:{len(raw_digest)}")
if len(hex_utf8) != 64:
    raise SystemExit(f"SIGNATURE_HEX_UTF8_LENGTH:{len(hex_utf8)}")
if len(field_utf8) != 71:
    raise SystemExit(f"SIGNATURE_FIELD_UTF8_LENGTH:{len(field_utf8)}")
if raw_digest in {hex_utf8, field_utf8}:
    raise SystemExit("SIGNATURE_MESSAGE_FRAMING_AMBIGUOUS")
signature_text = "A" * 86 + "=="
signature_bytes = base64.b64decode(signature_text, validate=True)
if len(signature_bytes) != contract["signature_framing"]["decoded_length_bytes"]:
    raise SystemExit(f"SIGNATURE_DECODED_LENGTH:{len(signature_bytes)}")
if base64.b64encode(signature_bytes).decode("ascii") != signature_text:
    raise SystemExit("SIGNATURE_BASE64_NOT_CANONICAL")
public_key_text = "A" * 43 + "="
public_key_bytes = base64.b64decode(public_key_text, validate=True)
public_key_contract = contract["key_resolution"]["binding_schema"]["properties"]["public_key"]
if len(public_key_bytes) != public_key_contract["x-decoded-length-bytes"]:
    raise SystemExit(f"PUBLIC_KEY_DECODED_LENGTH:{len(public_key_bytes)}")
if base64.b64encode(public_key_bytes).decode("ascii") != public_key_text:
    raise SystemExit("PUBLIC_KEY_BASE64_NOT_CANONICAL")
PY
    [ "$status" -eq 0 ]
}

@test "signature schema rejects noncanonical RFC 4648 pad bits" {
    run "$PYTHON" - "$REQUIREMENTS_SCHEMA" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    pattern = json.load(handle)["$defs"]["authorityApproval"]["properties"]["signature"]["pattern"]
canonical = "ed25519:" + ("A" * 86) + "=="
noncanonical = "ed25519:" + ("A" * 85) + "/=="
if re.fullmatch(pattern, canonical) is None:
    raise SystemExit("CANONICAL_SIGNATURE_REJECTED")
if re.fullmatch(pattern, noncanonical) is not None:
    raise SystemExit("NONCANONICAL_SIGNATURE_PAD_BITS_ACCEPTED")
PY
    [ "$status" -eq 0 ]
}

@test "deleting or mutating Ed25519 wire framing is detected independently" {
    local deleted="$BATS_TEST_TMPDIR/signature-contract-deleted.json"
    local message_mutant="$BATS_TEST_TMPDIR/signature-message-mutant.json"
    local key_mutant="$BATS_TEST_TMPDIR/signature-key-mutant.json"
    cp "$REQUIREMENTS_SCHEMA" "$deleted" || return 1
    cp "$REQUIREMENTS_SCHEMA" "$message_mutant" || return 1
    cp "$REQUIREMENTS_SCHEMA" "$key_mutant" || return 1
    yq -i 'del(."x-datarim-signature-contract")' "$deleted" || return 1
    yq -i '."x-datarim-signature-contract".digest_framing.signed_message = "LOWERCASE_HEX_UTF8"' "$message_mutant" || return 1
    yq -i '."x-datarim-signature-contract".key_resolution.binding_schema.properties.public_key."x-encoding" = "PEM"' "$key_mutant" || return 1

    run assert_signature_contract "$deleted"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SIGNATURE_CONTRACT_MISMATCH"* ]] \
        && run assert_signature_contract "$message_mutant" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SIGNATURE_CONTRACT_MISMATCH"* ]] \
        && run assert_signature_contract "$key_mutant" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SIGNATURE_CONTRACT_MISMATCH"* ]]
}

@test "trusted authority-key registry accepts the bound customer approval" {
    assert_signature_contract "$REQUIREMENTS_SCHEMA" \
        && validate_requirement_contract "$REQUIREMENTS_TEMPLATE" \
        && validate_trusted_authority_keys "$REQUIREMENTS_TEMPLATE"
}

@test "customer key cannot claim an operator authority identity" {
    local mutant="$BATS_TEST_TMPDIR/key-authority-id-mismatch.yaml"
    trusted_key_mutation_fixture "$mutant" \
        '.source_remarks[0].authority_approval.authority_id = "authority-operator-0001"' || return 1
    assert_signature_contract "$REQUIREMENTS_SCHEMA" || return 1
    validate_requirement_contract "$mutant" || return 1

    run validate_trusted_authority_keys "$mutant"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_APPROVAL_KEY_AUTHORITY_ID_MISMATCH:source-0001:key-customer-0001"* ]]
}

@test "customer key cannot claim the operator authority role" {
    local mutant="$BATS_TEST_TMPDIR/key-role-unauthorized.yaml"
    trusted_key_mutation_fixture "$mutant" \
        '.source_remarks[0].tier1_assertions[0].authority_approval.authority_role = "OPERATOR"' || return 1
    assert_signature_contract "$REQUIREMENTS_SCHEMA" || return 1
    validate_requirement_contract "$mutant" || return 1

    run validate_trusted_authority_keys "$mutant"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_APPROVAL_KEY_ROLE_UNAUTHORIZED:assertion-0001:OPERATOR"* ]]
}

@test "unknown approval key fails closed" {
    local mutant="$BATS_TEST_TMPDIR/key-unknown.yaml"
    trusted_key_mutation_fixture "$mutant" \
        '.source_remarks[0].authority_approval.key_id = "key-unknown-0001"' || return 1
    assert_signature_contract "$REQUIREMENTS_SCHEMA" || return 1
    validate_requirement_contract "$mutant" || return 1

    run validate_trusted_authority_keys "$mutant"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_APPROVAL_KEY_UNKNOWN:source-0001:key-unknown-0001"* ]]
}

@test "revoked approval key is rejected" {
    local mutant="$BATS_TEST_TMPDIR/key-revoked.yaml"
    trusted_key_mutation_fixture "$mutant" \
        '.source_remarks[0].tier1_assertions[0].authority_approval.key_id = "key-revoked-0001"' || return 1
    assert_signature_contract "$REQUIREMENTS_SCHEMA" || return 1
    validate_requirement_contract "$mutant" || return 1

    run validate_trusted_authority_keys "$mutant"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_APPROVAL_KEY_NOT_ACTIVE:assertion-0001:key-revoked-0001"* ]]
}

@test "not-yet-valid approval key is rejected" {
    local mutant="$BATS_TEST_TMPDIR/key-not-yet-valid.yaml"
    trusted_key_mutation_fixture "$mutant" \
        '.source_remarks[0].authority_approval.key_id = "key-future-0001"' || return 1
    assert_signature_contract "$REQUIREMENTS_SCHEMA" || return 1
    validate_requirement_contract "$mutant" || return 1

    run validate_trusted_authority_keys "$mutant"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_APPROVAL_KEY_NOT_YET_VALID:source-0001:key-future-0001"* ]]
}

@test "expired approval key is rejected" {
    local mutant="$BATS_TEST_TMPDIR/key-expired.yaml"
    trusted_key_mutation_fixture "$mutant" \
        '.source_remarks[0].tier1_assertions[0].authority_approval.key_id = "key-expired-0001"' || return 1
    assert_signature_contract "$REQUIREMENTS_SCHEMA" || return 1
    validate_requirement_contract "$mutant" || return 1

    run validate_trusted_authority_keys "$mutant"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_APPROVAL_KEY_EXPIRED:assertion-0001:key-expired-0001"* ]]
}

@test "RFC 8785 source digest preserves Cyrillic UTF-8 bytes without legacy escaping" {
    run "$PYTHON" - <<'PY'
import hashlib
import json

payload = {
    "source_id": "source-0001",
    "revision": "1",
    "source_tier": "CUSTOMER_VERBATIM",
    "verbatim_quote": "Сравнение должно оставаться читаемым.",
    "locale": "ru",
    "captured_at": "2026-01-02T09:00:00Z",
    "source_ref": "интервью-0001",
    "requirement_ids": ["req-0001", "req-0002"],
}
jcs_bytes = json.dumps(
    payload,
    ensure_ascii=False,
    sort_keys=True,
    separators=(",", ":"),
).encode("utf-8")
legacy_escaped_bytes = json.dumps(
    payload,
    ensure_ascii=True,
    sort_keys=True,
    separators=(",", ":"),
).encode("utf-8")
expected = "d854eabeb1d695d4716d6d6db25670a57bf941245fed437c05fa378b2e9cefdf"
actual = hashlib.sha256(jcs_bytes).hexdigest()
legacy = hashlib.sha256(legacy_escaped_bytes).hexdigest()
if actual != expected:
    raise SystemExit(f"JCS_INTEROP_DIGEST_MISMATCH:{actual}")
if legacy == expected:
    raise SystemExit("LEGACY_ASCII_ESCAPED_DIGEST_ACCEPTED")
PY
    [ "$status" -eq 0 ]
}

@test "deleting any registered semantic invariant is detected independently" {
    local schema index count mutant
    local requirement_path receipt_path evolution_path

    for schema in "$REQUIREMENTS_SCHEMA" "$RECEIPT_SCHEMA" "$EVOLUTION_SCHEMA"; do
        count=$(jq '."x-datarim-semantic-invariants".invariant_ids | length' "$schema") || return 1
        for ((index = 0; index < count; index++)); do
            mutant="$BATS_TEST_TMPDIR/$(basename "$schema")-$index"
            cp "$schema" "$mutant" || return 1
            yq -i "del(.\"x-datarim-semantic-invariants\".invariant_ids[$index])" "$mutant" || return 1
            requirement_path="$REQUIREMENTS_SCHEMA"
            receipt_path="$RECEIPT_SCHEMA"
            evolution_path="$EVOLUTION_SCHEMA"
            case "$schema" in
                "$REQUIREMENTS_SCHEMA") requirement_path="$mutant" ;;
                "$RECEIPT_SCHEMA") receipt_path="$mutant" ;;
                "$EVOLUTION_SCHEMA") evolution_path="$mutant" ;;
            esac
            run assert_semantic_invariant_registries \
                "$requirement_path" "$receipt_path" "$evolution_path"
            [ "$status" -eq 1 ] \
                && [[ "$output" == *"SEMANTIC_INVARIANT_REGISTRY_MISMATCH"* ]] \
                || return 1
        done
    done
}

@test "customer requirements reject unstable requirement IDs" {
    run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        '.requirements.BAD_ID = .requirements.req-0001 | del(.requirements.req-0001)'
    [ "$status" -eq 1 ]
}

@test "customer requirements require supported verbatim source tiers and exact quotes" {
    run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        '.source_remarks[0].source_tier = "agent_inference"'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            'del(.source_remarks[0].verbatim_quote)' \
        && [ "$status" -eq 1 ]
}

@test "source records require immutable digest and signed authority commitment" {
    run reject_contract_mutation \
        'del(.source_remarks[0].revision)'
    [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            'del(.source_remarks[0].source_digest)' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            'del(.source_remarks[0].authority_approval)' \
        && [ "$status" -eq 1 ]
}

@test "source and assertion approvals require a canonical approval payload digest" {
    local coherent="$BATS_TEST_TMPDIR/coherent-authority.yaml"
    structured_requirement_fixture "$coherent" || return 1

    validate_requirement_contract "$coherent" \
        && run reject_contract_mutation \
            'del(.source_remarks[0].authority_approval.approval_payload_digest)' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            'del(.source_remarks[0].tier1_assertions[0].authority_approval.approval_payload_digest)' \
        && [ "$status" -eq 1 ]
}

@test "approval metadata changes cannot retain the prior approval payload commitment" {
    local source_changed="$BATS_TEST_TMPDIR/source-approval-metadata.yaml"
    local assertion_changed="$BATS_TEST_TMPDIR/assertion-approval-metadata.yaml"
    structured_requirement_fixture "$source_changed" || return 1
    cp "$source_changed" "$assertion_changed" || return 1
    yq -i '.source_remarks[0].authority_approval.approved_at = "2026-01-02T09:03:00Z"' "$source_changed" || return 1
    yq -i '.source_remarks[0].tier1_assertions[0].authority_approval.evidence_ref = "changed-authority-evidence"' "$assertion_changed" || return 1

    run validate_requirement_contract "$source_changed"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_APPROVAL_PAYLOAD_DIGEST_MISMATCH:source-0001"* ]] \
        && run validate_requirement_contract "$assertion_changed" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_APPROVAL_PAYLOAD_DIGEST_MISMATCH:assertion-0001"* ]]
}

@test "digest refresh cannot silently reseal coordinated authority narrowing" {
    local narrowed="$BATS_TEST_TMPDIR/coordinated-authority-narrowing.yaml"
    structured_requirement_fixture "$narrowed" || return 1
    yq -i '
        .source_remarks[0].verbatim_quote = "The comparison may remain readable on desktop in English." |
        .source_remarks[0].tier1_assertions[0].applicability.locales = ["en"] |
        .source_remarks[0].tier1_assertions[0].applicability.viewports = ["desktop"] |
        .requirements.req-0001.acceptance.exact_source_quotes[0].verbatim_quote = "The comparison may remain readable on desktop in English." |
        .requirements.req-0001.acceptance.applicability.locales = ["en"] |
        .requirements.req-0001.acceptance.applicability.viewports = ["desktop"] |
        .requirements.req-0001.acceptance.production_assertion.applicability.locales = ["en"] |
        .requirements.req-0001.acceptance.production_assertion.applicability.viewports = ["desktop"] |
        .requirements.req-0001.acceptance.evidence.method.applicability.locales = ["en"] |
        .requirements.req-0001.acceptance.evidence.method.applicability.viewports = ["desktop"]
    ' "$narrowed" || return 1
    refresh_assertion_digests "$narrowed" || return 1

    run validate_requirement_contract "$narrowed"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_APPROVAL_PAYLOAD_DIGEST_MISMATCH:source-0001"* ]]
}

@test "resealed approval payload leaves cryptographic signature verification explicitly A2-owned" {
    local resealed="$BATS_TEST_TMPDIR/resealed-approval-payload.yaml"
    structured_requirement_fixture "$resealed" || return 1
    yq -i '
        .source_remarks[0].authority_approval.evidence_ref = "replacement-source-evidence" |
        .source_remarks[0].tier1_assertions[0].authority_approval.evidence_ref = "replacement-assertion-evidence"
    ' "$resealed" || return 1
    construct_placeholder_approvals "$resealed" || return 1

    validate_requirement_contract "$resealed" \
        && jq -e '."x-datarim-semantic-invariants".invariant_ids | index("source-signature-over-approval-payload-digest-valid") != null' "$REQUIREMENTS_SCHEMA" >/dev/null \
        && jq -e '."x-datarim-semantic-invariants".invariant_ids | index("tier1-assertion-signature-over-approval-payload-digest-valid") != null' "$REQUIREMENTS_SCHEMA" >/dev/null
}

@test "signed source commitment rejects coherent quote and acceptance rewrite" {
    run reject_contract_mutation '
        .source_remarks[0].verbatim_quote = "The comparison may remain readable on desktop only." |
        .requirements.req-0001.acceptance.exact_source_quotes[0].verbatim_quote = "The comparison may remain readable on desktop only."
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_DIGEST_MISMATCH:source-0001"* ]]
}

@test "source digest changes require matching authority approval" {
    run reject_contract_mutation '
        .source_remarks[0].verbatim_quote = "The comparison may remain readable on desktop only." |
        .requirements.req-0001.acceptance.exact_source_quotes[0].verbatim_quote = "The comparison may remain readable on desktop only." |
        .source_remarks[0].source_digest = "sha256:13dc577a184f01bc44e9b21b243dc868a827fbb6a85deca6e73b3eb7ef1ce844"
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_APPROVAL_DIGEST_MISMATCH:source-0001"* ]]
}

@test "assertion source digest must equal its containing source commitment" {
    run reject_contract_mutation \
        '.source_remarks[0].tier1_assertions[0].source_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"ASSERTION_SOURCE_DIGEST_MISMATCH:assertion-0001"* ]]
}

@test "append-only source correction retains and links its prior source digest" {
    local correction="$BATS_TEST_TMPDIR/source-correction.yaml"
    local dangling="$BATS_TEST_TMPDIR/source-correction-dangling.yaml"
    structured_requirement_fixture "$correction" || return 1
    yq -i '
        .source_remarks += [.source_remarks[0]] |
        .source_remarks[1].source_id = "source-0002" |
        .source_remarks[1].revision = "2" |
        .source_remarks[1].verbatim_quote = "The comparison must remain readable across the complete visitor matrix." |
        .source_remarks[1].captured_at = "2026-01-02T09:06:00Z" |
        .source_remarks[1].source_ref = "customer-correction-0002" |
        .source_remarks[1].supersedes_source_digest = .source_remarks[0].source_digest |
        .source_remarks[1].authority_approval.approved_at = "2026-01-02T09:07:00Z" |
        .source_remarks[1].authority_approval.evidence_ref = "source-authority-approval-0002" |
        .source_remarks[1].tier1_assertions[0].assertion_id = "assertion-0002" |
        .source_remarks[1].tier1_assertions[0].revision = "2" |
        .source_remarks[1].tier1_assertions[0].asserted_at = "2026-01-02T09:08:00Z" |
        .source_remarks[1].tier1_assertions[0].authority_approval.approved_at = "2026-01-02T09:09:00Z" |
        .source_remarks[1].tier1_assertions[0].authority_approval.evidence_ref = "authority-approval-0002" |
        .requirements.req-0001.source_ids += ["source-0002"] |
        .requirements.req-0001.tier1_assertion_ids += ["assertion-0002"] |
        .requirements.req-0001.acceptance.exact_source_quotes += [{
          "source_id": "source-0002",
          "verbatim_quote": "The comparison must remain readable across the complete visitor matrix."
        }]
    ' "$correction" || return 1
    refresh_assertion_digests "$correction" || return 1
    construct_placeholder_approvals "$correction" || return 1
    cp "$correction" "$dangling" || return 1
    yq -i '.source_remarks[1].supersedes_source_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$dangling" || return 1
    refresh_assertion_digests "$dangling" || return 1
    construct_placeholder_approvals "$dangling" || return 1

    validate_requirement_contract "$correction" \
        && run validate_requirement_contract "$dangling" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_SUPERSEDED_DIGEST_DANGLING:source-0002"* ]]
}

@test "source history retains every prior record unchanged and appends a linked correction" {
    local before="$BATS_TEST_TMPDIR/source-history-before.yaml"
    local after="$BATS_TEST_TMPDIR/source-history-after.yaml"
    local deleted="$BATS_TEST_TMPDIR/source-history-deleted.yaml"
    local mutated="$BATS_TEST_TMPDIR/source-history-mutated.yaml"
    local unlinked="$BATS_TEST_TMPDIR/source-history-unlinked.yaml"
    structured_requirement_fixture "$before" || return 1
    cp "$before" "$after" || return 1
    yq -i '
        .source_remarks += [.source_remarks[0]] |
        .source_remarks[1].source_id = "source-0002" |
        .source_remarks[1].revision = "2" |
        .source_remarks[1].verbatim_quote = "The comparison must remain readable across the complete visitor matrix." |
        .source_remarks[1].captured_at = "2026-01-02T09:06:00Z" |
        .source_remarks[1].source_ref = "customer-correction-0002" |
        .source_remarks[1].supersedes_source_digest = .source_remarks[0].source_digest |
        .source_remarks[1].authority_approval.approved_at = "2026-01-02T09:07:00Z" |
        .source_remarks[1].authority_approval.evidence_ref = "source-authority-approval-0002" |
        .source_remarks[1].tier1_assertions[0].assertion_id = "assertion-0002" |
        .source_remarks[1].tier1_assertions[0].revision = "2" |
        .source_remarks[1].tier1_assertions[0].asserted_at = "2026-01-02T09:08:00Z" |
        .source_remarks[1].tier1_assertions[0].authority_approval.approved_at = "2026-01-02T09:09:00Z" |
        .source_remarks[1].tier1_assertions[0].authority_approval.evidence_ref = "authority-approval-0002" |
        .requirements.req-0001.source_ids += ["source-0002"] |
        .requirements.req-0001.tier1_assertion_ids += ["assertion-0002"] |
        .requirements.req-0001.acceptance.exact_source_quotes += [{
          "source_id": "source-0002",
          "verbatim_quote": "The comparison must remain readable across the complete visitor matrix."
        }]
    ' "$after" || return 1
    refresh_assertion_digests "$after" || return 1
    construct_placeholder_approvals "$after" || return 1
    cp "$after" "$deleted" || return 1
    cp "$after" "$mutated" || return 1
    cp "$after" "$unlinked" || return 1
    yq -i 'del(.source_remarks[0])' "$deleted" || return 1
    yq -i '.source_remarks[0].authority_approval.evidence_ref = "mutated-prior-evidence"' "$mutated" || return 1
    yq -i 'del(.source_remarks[1].supersedes_source_digest)' "$unlinked" || return 1

    validate_source_history "$before" "$after" \
        && run validate_source_history "$before" "$deleted" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_HISTORY_PRIOR_DIGEST_DELETED"* ]] \
        && run validate_source_history "$before" "$mutated" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_HISTORY_PRIOR_RECORD_MUTATED"* ]] \
        && run validate_source_history "$before" "$unlinked" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_HISTORY_CORRECTION_SUPERSEDES_PRIOR_MISSING"* ]]
}

@test "customer acceptance tuple requires product surface before-after and evidence ownership" {
    run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        'del(.requirements.req-0001.acceptance.product)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            'del(.requirements.req-0001.acceptance.evidence.owner)' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            'del(.requirements.req-0001.acceptance.before_state)' \
        && [ "$status" -eq 1 ]
}

@test "customer acceptance tuple pins every knowledge kind by revision digest and pre-implementation timestamp" {
    run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        'del(.requirements.req-0001.acceptance.knowledge_selection.policies)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            '.requirements.req-0001.acceptance.knowledge_selection.roles[0].digest = "main"' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_before_implementation = false' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_at = "before implementation"' \
        && [ "$status" -eq 1 ]
}

@test "implementation scope requires normalized code and content path declarations" {
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.implementation.code_paths)'
    [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.implementation.code_paths = [] |
             .requirements.req-0001.acceptance.implementation.content_paths = []' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.implementation.code_paths = ["/absolute/path.ts"]' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.implementation.content_paths = ["content/../escape.md"]' \
        && [ "$status" -eq 1 ]
}

@test "Gap and Unbound knowledge cannot self-label product delivery in any kind or identity field" {
    local kind field sentinel
    for kind in roles skills blueprints constraints policies success_criteria; do
        for field in id revision; do
            for sentinel in Gap Unbound; do
                run reject_contract_mutation \
                    ".requirements.req-0001.acceptance.knowledge_selection.${kind}[0].${field} = \"${sentinel}\""
                [ "$status" -eq 1 ] \
                    && [[ "$output" == *"KNOWLEDGE_SELECTION_GAP_UNBOUND:req-0001:${kind}:${field}:${sentinel}"* ]] \
                    || {
                        echo "accepted prohibited knowledge sentinel: ${kind}.${field}=${sentinel}" >&2
                        return 1
                    }
            done
        done
    done
}

@test "date-time fields use strict RFC3339 while accepting Z and numeric offsets" {
    local offset="$BATS_TEST_TMPDIR/rfc3339-offset.yaml"
    cp "$REQUIREMENTS_TEMPLATE" "$offset" || return 1
    yq -i '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_at = "2026-01-02T10:00:00+02:30"' "$offset" || return 1

    validate_yaml "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        && validate_yaml "$REQUIREMENTS_SCHEMA" "$offset" \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            '.requirements.req-0001.acceptance.knowledge_selection.roles[0].selected_at = "2026-01-02X10:00:00+00:00"' \
        && [ "$status" -eq 1 ]
}

@test "tier-one assertion accepts exactly preserved acceptance scope" {
    local structured="$BATS_TEST_TMPDIR/exact-scope.yaml"
    structured_requirement_fixture "$structured"

    validate_requirement_contract "$structured"
}

@test "tier-one assertion accepts acceptance scope strengthened by added dimensions" {
    local structured="$BATS_TEST_TMPDIR/strengthened-scope.yaml"
    structured_requirement_fixture "$structured" || return 1
    yq -i '
        .source_remarks[0].tier1_assertions[0].applicability.locales = ["ru"] |
        .source_remarks[0].tier1_assertions[0].applicability.viewports = ["mobile"] |
        .source_remarks[0].tier1_assertions[0].applicability.themes = ["light"]
    ' "$structured" || return 1
    refresh_assertion_digests "$structured" || return 1
    construct_placeholder_approvals "$structured" || return 1

    validate_requirement_contract "$structured"
}

@test "unchanged source digest rejects coordinated assertion and acceptance narrowing" {
    run reject_contract_mutation '
        .source_remarks[0].tier1_assertions[0].applicability.locales = ["en"] |
        .source_remarks[0].tier1_assertions[0].applicability.viewports = ["desktop"] |
        .source_remarks[0].tier1_assertions[0].applicability.themes = ["light"] |
        .requirements.req-0001.acceptance.applicability.locales = ["en"] |
        .requirements.req-0001.acceptance.applicability.viewports = ["desktop"] |
        .requirements.req-0001.acceptance.applicability.themes = ["light"] |
        .requirements.req-0001.acceptance.production_assertion.applicability.locales = ["en"] |
        .requirements.req-0001.acceptance.production_assertion.applicability.viewports = ["desktop"] |
        .requirements.req-0001.acceptance.production_assertion.applicability.themes = ["light"] |
        .requirements.req-0001.acceptance.evidence.method.applicability.locales = ["en"] |
        .requirements.req-0001.acceptance.evidence.method.applicability.viewports = ["desktop"] |
        .requirements.req-0001.acceptance.evidence.method.applicability.themes = ["light"]
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_DIGEST_MISMATCH:assertion-0001"* ]]
}

@test "source-owned assertion requires immutable digest and signed authority approval" {
    local late_approval="$BATS_TEST_TMPDIR/late-assertion-approval.yaml"
    structured_requirement_fixture "$late_approval" || return 1
    yq -i '.source_remarks[0].tier1_assertions[0].authority_approval.approved_at = "2026-01-02T10:00:00Z"' "$late_approval" || return 1
    construct_placeholder_approvals "$late_approval" || return 1

    run reject_contract_mutation \
        'del(.source_remarks[0].tier1_assertions[0].revision)'
    [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            'del(.source_remarks[0].tier1_assertions[0].assertion_digest)' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            'del(.source_remarks[0].tier1_assertions[0].authority_approval)' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.source_remarks[0].tier1_assertions[0].authority_approval.signature = "not-a-signature"' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.source_remarks[0].tier1_assertions[0].authority_approval.approved_digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_APPROVAL_DIGEST_MISMATCH:assertion-0001"* ]] \
        && run validate_requirement_contract "$late_approval" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_APPROVAL_NOT_BEFORE_IMPLEMENTATION:assertion-0001"* ]]
}

@test "preserved quote cannot hide dropped RU acceptance scope" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.applicability.locales = ["en"]'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_SCOPE_WEAKENED:req-0001:locales:ru"* ]]
}

@test "preserved quote cannot hide dropped mobile acceptance scope" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.applicability.viewports = ["desktop"]'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_SCOPE_WEAKENED:req-0001:viewports:mobile"* ]]
}

@test "preserved quote cannot hide dropped dark acceptance scope" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.applicability.themes = ["light"]'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_SCOPE_WEAKENED:req-0001:themes:dark"* ]]
}

@test "tier-one predicate identity cannot change in acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.predicate_id = "predicate-substitute"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_PREDICATE_CHANGED:req-0001"* ]]
}

@test "tier-one product identity cannot change in acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.product = "substitute-product"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_PRODUCT_CHANGED:req-0001"* ]]
}

@test "tier-one surface identity cannot change in acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.surface = "substitute-surface"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_SURFACE_CHANGED:req-0001"* ]]
}

@test "surface class is required and structurally follows visitor visibility" {
    run reject_contract_mutation \
        'del(.source_remarks[0].tier1_assertions[0].surface_class)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"surface_class"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.surface_class = "ENABLING"' \
        && [ "$status" -eq 1 ]
}

@test "product identity rejects URL laundering across every visitor layer" {
    run reject_contract_mutation '
        .source_remarks[0].tier1_assertions[0].product = "https://example.invalid/docs" |
        .requirements.req-0001.acceptance.product = "https://example.invalid/docs" |
        .requirements.req-0001.acceptance.production_assertion.product = "https://example.invalid/docs" |
        .requirements.req-0001.acceptance.evidence.method.product = "https://example.invalid/docs"
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"product"* ]]
}

@test "surface identity rejects prose laundering across every visitor layer" {
    run reject_contract_mutation '
        .source_remarks[0].tier1_assertions[0].surface = "Unit test and docs only" |
        .requirements.req-0001.acceptance.surface = "Unit test and docs only" |
        .requirements.req-0001.acceptance.production_assertion.surface = "Unit test and docs only" |
        .requirements.req-0001.acceptance.evidence.method.surface = "Unit test and docs only"
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"surface"* ]]
}

@test "each product identity call site independently rejects an invalid slug" {
    local label expression
    while IFS='|' read -r label expression; do
        run reject_contract_mutation "$expression"
        [ "$status" -eq 1 ] || {
            echo "product slug call site accepted invalid identity: $label" >&2
            return 1
        }
    done <<'CASES'
source-assertion|.source_remarks[0].tier1_assertions[0].product = "https://example.invalid/docs"
acceptance|.requirements.req-0001.acceptance.product = "https://example.invalid/docs"
production-assertion|.requirements.req-0001.acceptance.production_assertion.product = "https://example.invalid/docs"
evidence-method|.requirements.req-0001.acceptance.evidence.method.product = "https://example.invalid/docs"
CASES
}

@test "each surface identity call site independently rejects invalid prose" {
    local label expression
    while IFS='|' read -r label expression; do
        run reject_contract_mutation "$expression"
        [ "$status" -eq 1 ] || {
            echo "surface slug call site accepted invalid identity: $label" >&2
            return 1
        }
    done <<'CASES'
source-assertion|.source_remarks[0].tier1_assertions[0].surface = "Unit test output and documentation review only"
acceptance|.requirements.req-0001.acceptance.surface = "Unit test output and documentation review only"
production-assertion|.requirements.req-0001.acceptance.production_assertion.surface = "Unit test output and documentation review only"
evidence-method|.requirements.req-0001.acceptance.evidence.method.surface = "Unit test output and documentation review only"
CASES
}

@test "each dedicated slug vector kills relaxation of its own schema reference" {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" <<'PY'
import copy
import json
import sys

import jsonschema
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    schema = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    template = yaml.safe_load(handle)

cases = [
    (
        "source-assertion-product",
        ("$defs", "tier1Assertion", "properties", "product"),
        ("source_remarks", 0, "tier1_assertions", 0, "product"),
        "https://example.invalid/docs",
    ),
    (
        "acceptance-product",
        ("$defs", "acceptanceTuple", "properties", "product"),
        ("requirements", "req-0001", "acceptance", "product"),
        "https://example.invalid/docs",
    ),
    (
        "production-product",
        ("$defs", "productionAssertion", "properties", "product"),
        ("requirements", "req-0001", "acceptance", "production_assertion", "product"),
        "https://example.invalid/docs",
    ),
    (
        "evidence-product",
        ("$defs", "visitorEvidenceMethod", "properties", "product"),
        ("requirements", "req-0001", "acceptance", "evidence", "method", "product"),
        "https://example.invalid/docs",
    ),
    (
        "source-assertion-surface",
        ("$defs", "tier1Assertion", "properties", "surface"),
        ("source_remarks", 0, "tier1_assertions", 0, "surface"),
        "Unit test output and documentation review only",
    ),
    (
        "acceptance-surface",
        ("$defs", "acceptanceTuple", "properties", "surface"),
        ("requirements", "req-0001", "acceptance", "surface"),
        "Unit test output and documentation review only",
    ),
    (
        "production-surface",
        ("$defs", "productionAssertion", "properties", "surface"),
        ("requirements", "req-0001", "acceptance", "production_assertion", "surface"),
        "Unit test output and documentation review only",
    ),
    (
        "evidence-surface",
        ("$defs", "visitorEvidenceMethod", "properties", "surface"),
        ("requirements", "req-0001", "acceptance", "evidence", "method", "surface"),
        "Unit test output and documentation review only",
    ),
]

for label, schema_path, instance_path, invalid_value in cases:
    mutant_schema = copy.deepcopy(schema)
    schema_node = mutant_schema
    for part in schema_path[:-1]:
        schema_node = schema_node[part]
    if schema_node[schema_path[-1]] not in (
        {"$ref": "#/$defs/productIdentity"},
        {"$ref": "#/$defs/surfaceIdentity"},
    ):
        raise SystemExit(f"unexpected identity reference at {label}")
    schema_node[schema_path[-1]] = {"type": "string"}

    invalid_instance = copy.deepcopy(template)
    instance_node = invalid_instance
    for part in instance_path[:-1]:
        instance_node = instance_node[part]
    instance_node[instance_path[-1]] = invalid_value

    try:
        jsonschema.Draft202012Validator(schema).validate(invalid_instance)
    except jsonschema.ValidationError:
        pass
    else:
        raise SystemExit(f"baseline did not reject dedicated vector: {label}")

    try:
        jsonschema.Draft202012Validator(mutant_schema).validate(invalid_instance)
    except jsonschema.ValidationError as exc:
        raise SystemExit(
            f"dedicated vector did not kill relaxed reference: {label}: {exc.message}"
        ) from None
PY
}

@test "visitor-visible tier-one assertion cannot become non-visitor acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.visitor_visible = false |
         .requirements.req-0001.acceptance.surface_class = "ENABLING" |
         .requirements.req-0001.acceptance.evidence.evidence_class = "NON_VISITOR" |
         .requirements.req-0001.acceptance.evidence.method = "Schema validation." |
         del(.requirements.req-0001.acceptance.rendered_test_evidence) |
         del(.requirements.req-0001.acceptance.production_assertion)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_VISITOR_VISIBLE_WEAKENED:req-0001"* ]]
}

@test "painted tier-one applicability cannot become non-painted acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.applicability.painted_matrix_applicable = false |
         .requirements.req-0001.acceptance.applicability.not_applicable_reason = "Substituted with a narrower non-painted check."'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_PAINTED_APPLICABILITY_WEAKENED:req-0001"* ]]
}

@test "tier-one assertion requires a stable assertion ID" {
    run reject_contract_mutation \
        'del(.source_remarks[0].tier1_assertions[0].assertion_id)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"tier1_assertion"*"assertion_id"* ]]
}

@test "tier-one assertion IDs are unique across requirements" {
    local duplicate="$BATS_TEST_TMPDIR/duplicate-assertion-id.yaml"
    structured_requirement_fixture "$duplicate" || return 1
    yq -i '
        .requirements.req-0002 = .requirements.req-0001 |
        .source_remarks[0].requirement_ids += ["req-0002"] |
        .source_remarks[0].tier1_assertions += [.source_remarks[0].tier1_assertions[0]] |
        .source_remarks[0].tier1_assertions[1].requirement_id = "req-0002"
    ' "$duplicate" || return 1
    refresh_assertion_digests "$duplicate" || return 1
    construct_placeholder_approvals "$duplicate" || return 1

    run validate_requirement_contract "$duplicate"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_DUPLICATE:assertion-0001"* ]]
}

@test "source-owned tier-one assertions reject sibling authority references" {
    run reject_contract_mutation \
        '.source_remarks[0].tier1_assertions[0].authority_ref = "source-9999"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"authority_ref"* ]]
}

@test "tier-one authority source IDs are unique" {
    run reject_contract_mutation '
        .source_remarks += [.source_remarks[0]] |
        .source_remarks[1].verbatim_quote = "Conflicting duplicate authority."
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_AUTHORITY_DUPLICATE:source-0001"* ]]
}

@test "source-to-requirement-to-assertion mapping is exact" {
    run reject_contract_mutation '
        .requirements.req-0001.tier1_assertion_ids = ["assertion-9999"]
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_MAPPING_MISMATCH:req-0001"* ]]
}

@test "acceptance rejects a dangling tier-one assertion ID" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.tier1_assertion_id = "assertion-9999"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_DANGLING:assertion-9999"* ]]
}

@test "acceptance cannot replace its tier-one assertion with another valid assertion" {
    local replaced="$BATS_TEST_TMPDIR/replaced-assertion.yaml"
    structured_requirement_fixture "$replaced" || return 1
    yq -i '
        .requirements.req-0002 = .requirements.req-0001 |
        .requirements.req-0002.tier1_assertion_ids = ["assertion-0002"] |
        .requirements.req-0002.acceptance.tier1_assertion_id = "assertion-0002" |
        .requirements.req-0002.acceptance.predicate_id = "predicate-second" |
        .requirements.req-0001.acceptance.tier1_assertion_id = "assertion-0002" |
        .source_remarks[0].requirement_ids += ["req-0002"] |
        .source_remarks[0].tier1_assertions += [.source_remarks[0].tier1_assertions[0]] |
        .source_remarks[0].tier1_assertions[1].assertion_id = "assertion-0002" |
        .source_remarks[0].tier1_assertions[1].requirement_id = "req-0002" |
        .source_remarks[0].tier1_assertions[1].predicate_id = "predicate-second"
    ' "$replaced" || return 1
    refresh_assertion_digests "$replaced" || return 1
    construct_placeholder_approvals "$replaced" || return 1

    run validate_requirement_contract "$replaced"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_REPLACED:req-0001:assertion-0002"* ]]
}

@test "legacy atomic statement is rejected even beside a valid tier-one assertion" {
    run reject_contract_mutation \
        '.requirements.req-0001.atomic_statement = "Legacy authoritative paraphrase."'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"atomic_statement"* ]]
}

@test "supersession target must exist in the same requirement document" {
    run reject_contract_mutation '
        .requirements.req-0001.acceptance.disposition = "superseded" |
        .requirements.req-0001.acceptance.superseded_by = "req-9999"
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SUPERSESSION_TARGET_DANGLING:req-0001:req-9999"* ]]
}

@test "visitor acceptance requires a closed production assertion" {
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.production_assertion)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion"* ]]
}

@test "visitor acceptance requires closed rendered test evidence and nonvisitor forbids it" {
    local nonvisitor="$BATS_TEST_TMPDIR/nonvisitor-with-rendered-test.yaml"
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.rendered_test_evidence)'
    [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.rendered_test_evidence.environment = "PRODUCTION"' \
        && [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.rendered_test_evidence.method = "Docs only"' \
        && [ "$status" -eq 1 ] \
        || return 1

    structured_requirement_fixture "$nonvisitor" || return 1
    yq -i '.requirements.req-0001.acceptance.visitor_visible = false |
        .requirements.req-0001.acceptance.surface_class = "ENABLING" |
        .requirements.req-0001.acceptance.evidence.evidence_class = "NON_VISITOR" |
        .requirements.req-0001.acceptance.evidence.method = "Schema validation." |
        .source_remarks[0].tier1_assertions[0].visitor_visible = false |
        .source_remarks[0].tier1_assertions[0].surface_class = "ENABLING" |
        del(.requirements.req-0001.acceptance.production_assertion)' "$nonvisitor" || return 1
    run validate_yaml "$REQUIREMENTS_SCHEMA" "$nonvisitor"
    [ "$status" -eq 1 ]
}

@test "rendered test evidence identity and timestamp stay bound to acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.rendered_test_evidence.product = "substitute-product"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"RENDERED_TEST_IDENTITY_CHANGED:req-0001:product"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.rendered_test_evidence.applicability.themes = ["light"]' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"RENDERED_TEST_SCOPE_CHANGED:req-0001:themes"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.rendered_test_evidence.observed_at = "2026-01-02T09:59:59Z"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"RENDERED_TEST_BEFORE_IMPLEMENTATION:req-0001"* ]]
}

@test "visitor production assertion requires visitor actor and production environment" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.production_assertion.actor = "TEST_RUNNER"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion.actor"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.production_assertion.environment = "TEST"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion.environment"* ]]
}

@test "visitor production assertion rejects tool-only observation kinds" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.production_assertion.observation_kind = "CLI_OUTPUT"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion.observation_kind"* ]]
}

@test "visitor production assertion requires structural product and applicability identity" {
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.production_assertion.product)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion"*"product"* ]] \
        && run reject_contract_mutation \
            'del(.requirements.req-0001.acceptance.production_assertion.applicability)' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion"*"applicability"* ]]
}

@test "visitor production assertion identity stays bound to acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.production_assertion.product = "docs-product"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"PRODUCTION_ASSERTION_IDENTITY_CHANGED:req-0001:product"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.production_assertion.predicate_id = "predicate-substitute"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"PRODUCTION_ASSERTION_IDENTITY_CHANGED:req-0001:predicate_id"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.production_assertion.surface_class = "ENABLING"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"PRODUCTION_ASSERTION_IDENTITY_CHANGED:req-0001:surface_class"* ]]
}

@test "visitor production assertion scope stays equal to accepted scope" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.production_assertion.applicability.locales = ["en"]'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"PRODUCTION_ASSERTION_SCOPE_CHANGED:req-0001:locales"* ]]
}

@test "visitor evidence method identity stays bound to acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.evidence.method.surface = "docs-surface"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_METHOD_IDENTITY_CHANGED:req-0001:surface"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.evidence.method.surface_class = "ENABLING"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_METHOD_IDENTITY_CHANGED:req-0001:surface_class"* ]]
}

@test "visitor evidence method requires predicate and applicability" {
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.evidence.method.predicate_id)'
    [ "$status" -eq 1 ] \
        && run reject_contract_mutation \
            'del(.requirements.req-0001.acceptance.evidence.method.applicability)' \
        && [ "$status" -eq 1 ]
}

@test "visitor evidence predicate and scope stay equal to acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.evidence.method.predicate_id = "predicate-substitute"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_METHOD_IDENTITY_CHANGED:req-0001:predicate_id"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.evidence.method.applicability.themes = ["light"]' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_METHOD_SCOPE_CHANGED:req-0001:themes"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.evidence.method.applicability.painted_matrix_applicable = false' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_METHOD_SCOPE_CHANGED:req-0001:painted"* ]]
}

@test "visitor evidence method rejects arbitrary prose and tool-only kinds" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.evidence.method = "The CLI says the page is done."'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"acceptance.evidence.method"* ]] \
        && run reject_contract_mutation \
            '.requirements.req-0001.acceptance.evidence.method.kind = "CLI_ASSERTION"' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"acceptance.evidence.method"* ]]
}

@test "browser labels cannot self-label documentation and unit-test prose as visitor evidence" {
    run reject_contract_mutation '
        .requirements.req-0001.acceptance.evidence.method.kind = "BROWSER_AUTOMATION" |
        .requirements.req-0001.acceptance.evidence.method.surface_ref = "https://example.invalid/docs/acceptance" |
        .requirements.req-0001.acceptance.production_assertion.observation_kind = "BROWSER_RENDERED" |
        .requirements.req-0001.acceptance.production_assertion.surface_ref = "https://example.invalid/docs/acceptance" |
        .requirements.req-0001.acceptance.production_assertion.observable_outcome = "Unit test and docs only; no visitor product observation."
    '
    [ "$status" -eq 1 ]
}

@test "two differently worded source remarks remain linked to one canonical requirement" {
    local plural="$BATS_TEST_TMPDIR/two-source-requirement.yaml"
    two_source_requirement_fixture "$plural"

    validate_requirement_contract "$plural"
}

@test "acceptance exact source quote set cannot omit a linked authority" {
    local plural="$BATS_TEST_TMPDIR/quote-row-omitted.yaml"
    two_source_requirement_fixture "$plural" || return 1
    yq -i 'del(.requirements.req-0001.acceptance.exact_source_quotes[1])' "$plural" || return 1

    run validate_requirement_contract "$plural"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_QUOTE_SET_MISMATCH:req-0001"* ]]
}

@test "acceptance exact source quote set cannot change or add authority" {
    local changed="$BATS_TEST_TMPDIR/quote-row-changed.yaml"
    local added="$BATS_TEST_TMPDIR/quote-row-added.yaml"
    two_source_requirement_fixture "$changed" || return 1
    cp "$changed" "$added" || return 1
    yq -i '.requirements.req-0001.acceptance.exact_source_quotes[1].verbatim_quote = "Narrowed replacement."' "$changed" || return 1
    yq -i '.requirements.req-0001.acceptance.exact_source_quotes += [{"source_id": "source-9999", "verbatim_quote": "Invented authority."}]' "$added" || return 1

    run validate_requirement_contract "$changed"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_QUOTE_SET_MISMATCH:req-0001"* ]] \
        && run validate_requirement_contract "$added" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_QUOTE_SET_MISMATCH:req-0001"* ]]
}

@test "acceptance exact source quote set rejects duplicate source rows" {
    local duplicate="$BATS_TEST_TMPDIR/quote-source-duplicate.yaml"
    two_source_requirement_fixture "$duplicate" || return 1
    yq -i '.requirements.req-0001.acceptance.exact_source_quotes += [{"source_id": "source-0001", "verbatim_quote": "Conflicting quote for the same authority."}]' "$duplicate" || return 1

    run validate_requirement_contract "$duplicate"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_QUOTE_SOURCE_DUPLICATE:req-0001:source-0001"* ]]
}

@test "legacy singular exact source quote is rejected" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.exact_source_quote = "Legacy singular quote."'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"exact_source_quote"* ]]
}

@test "requirement source IDs cannot dangle" {
    run reject_contract_mutation \
        '.requirements.req-0001.source_ids += ["source-9999"]'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_SOURCE_DANGLING:req-0001:source-9999"* ]]
}

@test "source requirement IDs cannot dangle" {
    local dangling="$BATS_TEST_TMPDIR/dangling-source-requirement.yaml"
    structured_requirement_fixture "$dangling" || return 1
    yq -i '.source_remarks[0].requirement_ids += ["req-9999"]' "$dangling" || return 1
    refresh_assertion_digests "$dangling" || return 1
    construct_placeholder_approvals "$dangling" || return 1

    run validate_requirement_contract "$dangling"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_REQUIREMENT_DANGLING:source-0001:req-9999"* ]]
}

@test "user-facing customer requirements reject non-visitor evidence class" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.evidence.evidence_class = "NON_VISITOR" |
         .requirements.req-0001.acceptance.evidence.method = "Schema validation."'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"acceptance.evidence.evidence_class"* ]]
}

@test "customer requirements reject undocumented fields and invalid dispositions" {
    run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
        '.requirements.req-0001.acceptance.docs_only_is_enough = true'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            'del(.requirements.req-0001.acceptance.disposition)' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
            '.requirements.req-0001.acceptance.disposition = "done"' \
        && [ "$status" -eq 1 ]
}

@test "delivery receipt requires every deterministic coverage-chain edge" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        'del(.requirements.req-0001.coverage_chain.live_evidence)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            'del(.requirements.req-0001.coverage_chain.merged_revision)' \
        && [ "$status" -eq 1 ]
}

@test "visitor live evidence requires closed production identity fields" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        'del(.requirements.req-0001.coverage_chain.live_evidence.product)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            'del(.requirements.req-0001.coverage_chain.live_evidence.predicate_id)' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            'del(.requirements.req-0001.coverage_chain.live_evidence.applicability)' \
        && [ "$status" -eq 1 ]
}

@test "receipt cannot self-label unit tests and documentation as visitor evidence" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        '.requirements.req-0001.coverage_chain.live_evidence.method = "Unit test output and documentation review only"'
    [ "$status" -eq 1 ]
}

@test "receipt live product and surface identities reject URLs and prose" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        '.requirements.req-0001.coverage_chain.live_evidence.product = "https://example.invalid/docs"'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            '.requirements.req-0001.coverage_chain.live_evidence.surface = "Unit test output and documentation review only"' \
        && [ "$status" -eq 1 ]
}

@test "receipt visitor and non-visitor live evidence branches are structurally closed" {
    local non_visitor="$BATS_TEST_TMPDIR/non-visitor-live-identity.yaml"
    cp "$RECEIPT_TEMPLATE" "$non_visitor" || return 1
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.visitor_visible = false |
        .requirements.req-0001.coverage_chain.live_evidence.observation_kind = "NON_VISITOR_CONTROL" |
        .requirements.req-0001.coverage_chain.live_evidence.surface_class = "ENABLING" |
        .requirements.req-0001.coverage_chain.live_evidence.environment = "CONTROL" |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "This is an enabling delivery control." |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = [] |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_count = 0 |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes = []' "$non_visitor" || return 1

    validate_yaml "$RECEIPT_SCHEMA" "$non_visitor" \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            '.requirements.req-0001.coverage_chain.live_evidence.environment = "CONTROL"' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            '.requirements.req-0001.coverage_chain.live_evidence.observation_kind = "NON_VISITOR_CONTROL"' \
        && [ "$status" -eq 1 ]
}

@test "delivery receipt accepts plural closed source quote digests" {
    local plural="$BATS_TEST_TMPDIR/plural-source-digests.yaml"
    plural_receipt_fixture "$plural"

    validate_yaml "$RECEIPT_SCHEMA" "$plural"
}

@test "requirement document and receipt requirement key sets are exactly equal" {
    local requirements="$BATS_TEST_TMPDIR/two-requirement-keys.yaml"
    local incomplete="$BATS_TEST_TMPDIR/one-receipt-key.yaml"
    local complete="$BATS_TEST_TMPDIR/two-receipt-keys.yaml"
    structured_requirement_fixture "$requirements" || return 1
    cp "$RECEIPT_TEMPLATE" "$incomplete" || return 1
    yq -i '.requirements.req-0002 = .requirements.req-0001' "$requirements" || return 1
    cp "$incomplete" "$complete" || return 1
    yq -i '.requirements.req-0002 = .requirements.req-0001 |
        .requirements.req-0002.coverage_chain.requirement.requirement_id = "req-0002"' "$complete" || return 1

    run validate_requirement_receipt_key_contract "$requirements" "$incomplete"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"REQUIREMENT_RECEIPT_KEY_SET_MISMATCH:req-0002"* ]] \
        && validate_requirement_receipt_key_contract "$requirements" "$complete"
}

@test "two-source requirement and receipt preserve exact quote digest content" {
    local requirements="$BATS_TEST_TMPDIR/two-source-digest-requirements.yaml"
    local receipt="$BATS_TEST_TMPDIR/two-source-digest-receipt.yaml"
    two_source_requirement_fixture "$requirements" || return 1
    plural_receipt_fixture "$receipt" || return 1

    validate_receipt_digest_contract "$requirements" "$receipt"
}

@test "plural quote digest set rejects missing duplicate wrong and foreign rows" {
    local requirements="$BATS_TEST_TMPDIR/digest-vector-requirements.yaml"
    local base="$BATS_TEST_TMPDIR/digest-vector-base.yaml"
    local missing="$BATS_TEST_TMPDIR/digest-vector-missing.yaml"
    local duplicate="$BATS_TEST_TMPDIR/digest-vector-duplicate.yaml"
    local wrong="$BATS_TEST_TMPDIR/digest-vector-wrong.yaml"
    local foreign="$BATS_TEST_TMPDIR/digest-vector-foreign.yaml"
    two_source_requirement_fixture "$requirements" || return 1
    plural_receipt_fixture "$base" || return 1
    cp "$base" "$missing" || return 1
    cp "$base" "$duplicate" || return 1
    cp "$base" "$wrong" || return 1
    cp "$base" "$foreign" || return 1
    yq -i 'del(.requirements.req-0001.coverage_chain.requirement.source_quote_digests[1])' "$missing" || return 1
    yq -i '.requirements.req-0001.coverage_chain.requirement.source_quote_digests += [{"source_id": "source-0001", "digest": "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}]' "$duplicate" || return 1
    yq -i '.requirements.req-0001.coverage_chain.requirement.source_quote_digests[1].digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$wrong" || return 1
    yq -i '.requirements.req-0001.coverage_chain.requirement.source_quote_digests += [{"source_id": "source-9999", "digest": "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}]' "$foreign" || return 1

    run validate_receipt_digest_contract "$requirements" "$missing"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_QUOTE_DIGEST_SET_MISMATCH:req-0001"* ]] \
        && run validate_receipt_digest_contract "$requirements" "$duplicate" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_QUOTE_DIGEST_SOURCE_DUPLICATE:req-0001:source-0001"* ]] \
        && run validate_receipt_digest_contract "$requirements" "$wrong" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_QUOTE_DIGEST_CONTENT_MISMATCH:req-0001:source-0002"* ]] \
        && run validate_receipt_digest_contract "$requirements" "$foreign" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"SOURCE_QUOTE_DIGEST_SET_MISMATCH:req-0001"* ]]
}

@test "delivery receipt rejects legacy singular source quote digest" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        '.requirements.req-0001.coverage_chain.requirement.source_quote_digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
    [ "$status" -eq 1 ]
}

@test "a missing coverage edge is valid only when explicitly declared NOT_MET" {
    local mutated="$BATS_TEST_TMPDIR/not-met.yaml"
    cp "$RECEIPT_TEMPLATE" "$mutated"
    yq -i '.requirements.req-0001.coverage_status = "NOT_MET" |
        .requirements.req-0001.missing_edges = ["live_evidence"] |
        del(.requirements.req-0001.coverage_chain.live_evidence)' "$mutated"

    validate_yaml "$RECEIPT_SCHEMA" "$mutated"
}

@test "delivery receipt counts enabling and visitor-visible deltas separately" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        'del(.requirements.req-0001.coverage_chain.implementation_delta.enabling_changes)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            'del(.requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes)' \
        && [ "$status" -eq 1 ]
}

@test "delivery receipt requires RED GREEN merge deploy and live evidence" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        'del(.requirements.req-0001.coverage_chain.red_green.red)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            'del(.requirements.req-0001.coverage_chain.deployed_revision.evidence_ref)' \
        && [ "$status" -eq 1 ] \
        && run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
            'del(.requirements.req-0001.coverage_chain.live_evidence.owner)' \
        && [ "$status" -eq 1 ]
}

@test "non-applicable painted evidence accepts an empty matrix with a reason" {
    local non_applicable="$BATS_TEST_TMPDIR/non-applicable-painted.yaml"
    cp "$RECEIPT_TEMPLATE" "$non_applicable" || return 1
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "This surface has no painted locale, viewport, or theme variants." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = []' "$non_applicable" || return 1

    validate_yaml "$RECEIPT_SCHEMA" "$non_applicable"
}

@test "non-visitor requirements accept zero visible deltas but cannot claim visitor-visible evidence" {
    local non_visitor_requirement="$BATS_TEST_TMPDIR/non-visitor-requirement.yaml"
    local contradictory_requirement="$BATS_TEST_TMPDIR/contradictory-non-visitor-requirement.yaml"
    local non_visitor_receipt="$BATS_TEST_TMPDIR/non-visitor-receipt.yaml"
    local false_visitor_claim="$BATS_TEST_TMPDIR/false-visitor-claim.yaml"
    structured_requirement_fixture "$non_visitor_requirement" || return 1
    cp "$RECEIPT_TEMPLATE" "$non_visitor_receipt" || return 1
    yq -i '.requirements.req-0001.acceptance.visitor_visible = false |
        .requirements.req-0001.acceptance.surface_class = "ENABLING" |
        .requirements.req-0001.acceptance.evidence.evidence_class = "NON_VISITOR" |
        .requirements.req-0001.acceptance.evidence.method = "Schema validation against the internal contract." |
        del(.requirements.req-0001.acceptance.rendered_test_evidence) |
        del(.requirements.req-0001.acceptance.production_assertion) |
        .source_remarks[0].tier1_assertions[0].visitor_visible = false |
        .source_remarks[0].tier1_assertions[0].surface_class = "ENABLING" |
        .source_remarks[0].tier1_assertions[0].applicability.painted_matrix_applicable = false |
        .source_remarks[0].tier1_assertions[0].applicability.not_applicable_reason = "This requirement changes an internal delivery control only." |
        .requirements.req-0001.acceptance.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.acceptance.applicability.not_applicable_reason = "This requirement changes an internal delivery control only."' "$non_visitor_requirement" || return 1
    refresh_assertion_digests "$non_visitor_requirement" || return 1
    construct_placeholder_approvals "$non_visitor_requirement" || return 1
    cp "$non_visitor_requirement" "$contradictory_requirement" || return 1
    yq -i '.requirements.req-0001.acceptance.evidence.evidence_class = "VISITOR_VISIBLE_PRODUCTION"' "$contradictory_requirement" || return 1
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_count = 0 |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes = [] |
        .requirements.req-0001.coverage_chain.live_evidence.visitor_visible = false |
        .requirements.req-0001.coverage_chain.live_evidence.observation_kind = "NON_VISITOR_CONTROL" |
        .requirements.req-0001.coverage_chain.live_evidence.surface_class = "ENABLING" |
        .requirements.req-0001.coverage_chain.live_evidence.environment = "CONTROL" |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "This requirement changes an internal delivery control only." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = []' "$non_visitor_receipt" || return 1
    cp "$non_visitor_receipt" "$false_visitor_claim" || return 1
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.visitor_visible = true' "$false_visitor_claim" || return 1

    validate_requirement_contract "$non_visitor_requirement" \
        && validate_yaml "$RECEIPT_SCHEMA" "$non_visitor_receipt" \
        && run validate_yaml "$REQUIREMENTS_SCHEMA" "$contradictory_requirement" \
        && [ "$status" -eq 1 ] \
        && run validate_yaml "$RECEIPT_SCHEMA" "$false_visitor_claim" \
        && [ "$status" -eq 1 ]
}

@test "applicable live evidence requires the complete RU EN painted matrix" {
    local nine_cells="$BATS_TEST_TMPDIR/nine-painted-cells.yaml"
    local duplicate_combination="$BATS_TEST_TMPDIR/duplicate-painted-combination.yaml"
    local schema_mutant="$BATS_TEST_TMPDIR/receipt-schema-without-en-desktop-dark.json"
    "$PYTHON" - "$RECEIPT_SCHEMA" <<'PY' || return 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    schema = json.load(handle)

matrix_rules = schema["$defs"]["liveEvidence"]["allOf"][1]["then"]["properties"]["painted_matrix"]["allOf"]
actual = [rule["contains"]["$ref"] for rule in matrix_rules]
expected = [
    "#/$defs/ruMobileLight",
    "#/$defs/ruMobileDark",
    "#/$defs/ruDesktopLight",
    "#/$defs/ruDesktopDark",
    "#/$defs/enMobileLight",
    "#/$defs/enMobileDark",
    "#/$defs/enDesktopLight",
    "#/$defs/enDesktopDark",
]
if actual != expected:
    raise SystemExit(f"painted matrix contains drift: {actual!r}")
PY
    cp "$RECEIPT_TEMPLATE" "$nine_cells" || return 1
    cp "$RECEIPT_TEMPLATE" "$duplicate_combination" || return 1
    cp "$RECEIPT_SCHEMA" "$schema_mutant" || return 1
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.painted_matrix += [{
          "locale": "ru",
          "viewport": "mobile",
          "theme": "light",
          "evidence_ref": "artifacts/live/extra-ru-mobile-light.png",
          "observed_at": "2026-01-02T13:28:00Z"
        }]' "$nine_cells" || return 1
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.painted_matrix[7].locale = "ru" |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix[7].viewport = "mobile" |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix[7].theme = "light"' "$duplicate_combination" || return 1
    # $defs is the literal JSON Schema key.
    # shellcheck disable=SC2016
    yq -i 'del(."$defs".liveEvidence.allOf[1].then.properties.painted_matrix.allOf[7])' "$schema_mutant" || return 1

    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        'del(.requirements.req-0001.coverage_chain.live_evidence.painted_matrix[7])'
    [ "$status" -eq 1 ] \
        && run validate_yaml "$RECEIPT_SCHEMA" "$nine_cells" \
        && [ "$status" -eq 1 ] \
        && run validate_yaml "$RECEIPT_SCHEMA" "$duplicate_combination" \
        && [ "$status" -eq 1 ] \
        && validate_yaml "$schema_mutant" "$duplicate_combination"
}

@test "delivery receipt preserves parent links without authored parent state" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        '.parent_links[0].state = "complete"'
    [ "$status" -eq 1 ]
}

@test "delivery receipt customer disposition is closed to four states" {
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        '.requirements.req-0001.coverage_chain.customer_disposition.status = "approved"'
    [ "$status" -eq 1 ]
}

@test "terminal customer disposition requires closed authority while pending may omit it" {
    local pending="$BATS_TEST_TMPDIR/pending-without-authority.yaml"
    local terminal_status expression
    cp "$RECEIPT_TEMPLATE" "$pending" || return 1
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.status = "pending" |
        del(.requirements.req-0001.coverage_chain.customer_disposition.authority)' "$pending" || return 1

    validate_yaml "$RECEIPT_SCHEMA" "$pending" || return 1
    for terminal_status in accepted rejected superseded; do
        expression=".requirements.req-0001.coverage_chain.customer_disposition.status = \"${terminal_status}\" | del(.requirements.req-0001.coverage_chain.customer_disposition.authority)"
        if [ "$terminal_status" = "superseded" ]; then
            expression="${expression} | .requirements.req-0001.coverage_chain.customer_disposition.superseded_by = \"req-0002\""
        fi
        run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" "$expression"
        [ "$status" -eq 1 ] || return 1
    done
    run reject_mutation "$RECEIPT_SCHEMA" "$RECEIPT_TEMPLATE" \
        '.requirements.req-0001.coverage_chain.customer_disposition.authority.extra = "not closed"'
    [ "$status" -eq 1 ]
}

@test "qualitative and painted visitor acceptance require operator disposition authority" {
    local customer_authority="$BATS_TEST_TMPDIR/customer-authority.yaml"
    local late_rendered="$BATS_TEST_TMPDIR/late-rendered-test.yaml"
    local qualitative_requirement="$BATS_TEST_TMPDIR/qualitative-requirement.yaml"
    local qualitative_receipt="$BATS_TEST_TMPDIR/qualitative-receipt.yaml"
    cp "$RECEIPT_TEMPLATE" "$customer_authority" || return 1
    cp "$REQUIREMENTS_TEMPLATE" "$late_rendered" || return 1
    cp "$REQUIREMENTS_TEMPLATE" "$qualitative_requirement" || return 1
    cp "$RECEIPT_TEMPLATE" "$qualitative_receipt" || return 1
    yq -i '.requirements.req-0001.coverage_chain.customer_disposition.authority.authority_role = "CUSTOMER"' "$customer_authority" || return 1
    yq -i '.requirements.req-0001.acceptance.rendered_test_evidence.observed_at = "2026-01-02T14:00:00Z"' "$late_rendered" || return 1
    yq -i '.source_remarks[0].tier1_assertions[0].applicability.painted_matrix_applicable = false |
        .source_remarks[0].tier1_assertions[0].applicability.not_applicable_reason = "This visitor outcome is qualitative rather than matrix-based." |
        .requirements.req-0001.acceptance.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.acceptance.applicability.not_applicable_reason = "This visitor outcome is qualitative rather than matrix-based." |
        .requirements.req-0001.acceptance.rendered_test_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.acceptance.production_assertion.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.acceptance.evidence.method.applicability.painted_matrix_applicable = false' "$qualitative_requirement" || return 1
    refresh_assertion_digests "$qualitative_requirement" || return 1
    construct_placeholder_approvals "$qualitative_requirement" || return 1
    yq -i '.requirements.req-0001.coverage_chain.live_evidence.observation_kind = "BROWSER_RENDERED" |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.coverage_chain.live_evidence.not_applicable_reason = "This visitor outcome is qualitative rather than matrix-based." |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix = [] |
        .requirements.req-0001.coverage_chain.customer_disposition.authority.authority_role = "CUSTOMER"' "$qualitative_receipt" || return 1

    run validate_acceptance_receipt_authority_contract \
        "$REQUIREMENTS_TEMPLATE" "$customer_authority"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_DISPOSITION_OPERATOR_REQUIRED:req-0001"* ]] \
        && run validate_acceptance_receipt_authority_contract \
            "$late_rendered" "$RECEIPT_TEMPLATE" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"RENDERED_TEST_AFTER_LIVE_EVIDENCE:req-0001"* ]] \
        && run validate_acceptance_receipt_authority_contract \
            "$qualitative_requirement" "$qualitative_receipt" \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"VISITOR_DISPOSITION_OPERATOR_REQUIRED:req-0001"* ]]
}

@test "review evolution accepts only the six normative classifications" {
    run reject_mutation "$EVOLUTION_SCHEMA" "$EVOLUTION_TEMPLATE" \
        '.classification = "MISSING"'
    [ "$status" -eq 1 ]
}

@test "review evolution first five classifications require a revised artifact and red-capable enforcement" {
    run reject_mutation "$EVOLUTION_SCHEMA" "$EVOLUTION_TEMPLATE" \
        'del(.canonical_change.artifact_revision)'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$EVOLUTION_SCHEMA" "$EVOLUTION_TEMPLATE" \
            '.canonical_change.enforcement.red_capable = false' \
        && [ "$status" -eq 1 ]
}

@test "NO_CANON_CHANGE requires evidence and reviewer approval" {
    local no_change="$BATS_TEST_TMPDIR/no-canon-change.yaml"
    cp "$EVOLUTION_TEMPLATE" "$no_change"
    yq -i '.classification = "NO_CANON_CHANGE" |
        del(.canonical_change) |
        .no_canon_change = {
          "evidence": "The existing canonical rule already covers this exact failure.",
          "reviewer_approval": {
            "reviewer": "independent-reviewer",
            "approved": true,
            "approved_at": "2026-01-03T16:00:00Z"
          }
        }' "$no_change"

    validate_yaml "$EVOLUTION_SCHEMA" "$no_change" \
        && run reject_mutation "$EVOLUTION_SCHEMA" "$no_change" \
            'del(.no_canon_change.reviewer_approval)' \
        && [ "$status" -eq 1 ]
}

@test "review evolution cannot substitute for the product fix or author parent state" {
    run reject_mutation "$EVOLUTION_SCHEMA" "$EVOLUTION_TEMPLATE" \
        '.product_fix.substitution_prohibited = false'
    [ "$status" -eq 1 ] \
        && run reject_mutation "$EVOLUTION_SCHEMA" "$EVOLUTION_TEMPLATE" \
            '.parent_links[0].state = "complete"' \
        && [ "$status" -eq 1 ]
}

@test "open or changes-requested originating review blocks closure" {
    local review_state
    for review_state in OPEN CHANGES_REQUESTED; do
        run validate_review_closure_contract "$review_state" CLOSED
        [ "$status" -eq 1 ] \
            && [[ "$output" == *"ORIGINATING_REVIEW_BLOCKS_CLOSURE:${review_state}"* ]] \
            || return 1
    done

    validate_review_closure_contract APPROVED CLOSED
}
