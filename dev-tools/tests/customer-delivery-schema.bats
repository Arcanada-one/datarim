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
    yq -i '
        .requirements.req-0001.tier1_assertion = {
          "assertion_id": "assertion-0001",
          "predicate_id": "predicate-visitor-readable",
          "product": "example-product",
          "surface": "public-comparison",
          "applicability": {
            "locales": ["ru", "en"],
            "viewports": ["mobile", "desktop"],
            "themes": ["light", "dark"],
            "painted_matrix_applicable": true
          },
          "visitor_visible": true,
          "authority_ref": "source-0001",
          "asserted_at": "2026-01-02T09:00:00Z"
        } |
        del(.requirements.req-0001.atomic_statement) |
        .requirements.req-0001.acceptance.tier1_assertion_id = "assertion-0001" |
        .requirements.req-0001.acceptance.predicate_id = "predicate-visitor-readable" |
        .requirements.req-0001.acceptance.evidence.method = {
          "kind": "PAINTED_SURFACE_PROBE",
          "surface_ref": "https://example.invalid/comparison"
        } |
        .requirements.req-0001.acceptance.production_assertion = {
          "actor": "VISITOR",
          "environment": "PRODUCTION",
          "observation_kind": "PAINTED_SURFACE",
          "surface_ref": "https://example.invalid/comparison",
          "observable_outcome": "The comparison remains readable without overlap."
        } |
        del(.requirements.req-0001.acceptance.production_acceptance_criterion)
    ' "$target" || return 2
}

validate_requirement_contract() {
    "$PYTHON" - "$REQUIREMENTS_SCHEMA" "$1" <<'PY'
import json
import sys

import jsonschema
import yaml

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
for source in instance["source_remarks"]:
    source_id = source["source_id"]
    if source_id in sources:
        raise SystemExit(f"TIER1_AUTHORITY_DUPLICATE:{source_id}")
    sources[source_id] = source

assertions = {}
for requirement_id, requirement in instance["requirements"].items():
    assertion = requirement["tier1_assertion"]
    assertion_id = assertion["assertion_id"]
    if assertion_id in assertions:
        raise SystemExit(f"TIER1_ASSERTION_DUPLICATE:{assertion_id}")
    assertions[assertion_id] = (requirement_id, assertion)

for requirement_id, requirement in instance["requirements"].items():
    own_assertion = requirement["tier1_assertion"]
    acceptance = requirement["acceptance"]
    authority_ref = own_assertion["authority_ref"]
    if authority_ref not in sources:
        raise SystemExit(
            f"TIER1_AUTHORITY_DANGLING:{requirement_id}:{authority_ref}"
        )
    if (
        authority_ref not in requirement["source_ids"]
        or requirement_id not in sources[authority_ref]["requirement_ids"]
    ):
        raise SystemExit(
            f"TIER1_AUTHORITY_NOT_BOUND:{requirement_id}:{authority_ref}"
        )
    assertion_id = acceptance["tier1_assertion_id"]
    if assertion_id not in assertions:
        raise SystemExit(f"TIER1_ASSERTION_DANGLING:{assertion_id}")
    asserted_requirement_id, assertion = assertions[assertion_id]
    if asserted_requirement_id != requirement_id or assertion is not own_assertion:
        raise SystemExit(
            f"TIER1_ASSERTION_REPLACED:{requirement_id}:{assertion_id}"
        )
    if acceptance["predicate_id"] != assertion["predicate_id"]:
        raise SystemExit(f"TIER1_PREDICATE_CHANGED:{requirement_id}")
    if acceptance["product"] != assertion["product"]:
        raise SystemExit(f"TIER1_PRODUCT_CHANGED:{requirement_id}")
    if acceptance["surface"] != assertion["surface"]:
        raise SystemExit(f"TIER1_SURFACE_CHANGED:{requirement_id}")

    asserted_scope = assertion["applicability"]
    accepted_scope = acceptance["applicability"]
    for dimension in ("locales", "viewports", "themes"):
        omitted = set(asserted_scope[dimension]) - set(accepted_scope[dimension])
        if omitted:
            raise SystemExit(
                f"TIER1_SCOPE_WEAKENED:{requirement_id}:{dimension}:"
                + ",".join(sorted(omitted))
            )
    if assertion["visitor_visible"] and not acceptance["visitor_visible"]:
        raise SystemExit(f"TIER1_VISITOR_VISIBLE_WEAKENED:{requirement_id}")
    if (
        asserted_scope["painted_matrix_applicable"]
        and not accepted_scope["painted_matrix_applicable"]
    ):
        raise SystemExit(f"TIER1_PAINTED_APPLICABILITY_WEAKENED:{requirement_id}")
PY
}

reject_contract_mutation() {
    local expression="$1"
    local mutated="$BATS_TEST_TMPDIR/structured-requirement.yaml"

    structured_requirement_fixture "$mutated" || return 2
    yq -i "$expression" "$mutated" || return 2
    validate_requirement_contract "$mutated"
}

@test "complete customer delivery examples validate against Draft 2020-12 schemas" {
    validate_yaml "$REQUIREMENTS_SCHEMA" "$REQUIREMENTS_TEMPLATE" \
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
        .requirements.req-0001.tier1_assertion.applicability.locales = ["ru"] |
        .requirements.req-0001.tier1_assertion.applicability.viewports = ["mobile"] |
        .requirements.req-0001.tier1_assertion.applicability.themes = ["light"]
    ' "$structured" || return 1

    validate_requirement_contract "$structured"
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

@test "visitor-visible tier-one assertion cannot become non-visitor acceptance" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.visitor_visible = false |
         .requirements.req-0001.acceptance.evidence.evidence_class = "NON_VISITOR" |
         .requirements.req-0001.acceptance.evidence.method = "Schema validation." |
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
        'del(.requirements.req-0001.tier1_assertion.assertion_id)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"tier1_assertion"*"assertion_id"* ]]
}

@test "tier-one assertion IDs are unique across requirements" {
    run reject_contract_mutation '
        .requirements.req-0002 = .requirements.req-0001 |
        .source_remarks[0].requirement_ids += ["req-0002"]
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_DUPLICATE:assertion-0001"* ]]
}

@test "tier-one authority reference cannot dangle" {
    run reject_contract_mutation \
        '.requirements.req-0001.tier1_assertion.authority_ref = "source-9999"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_AUTHORITY_DANGLING:req-0001:source-9999"* ]]
}

@test "tier-one authority source IDs are unique" {
    run reject_contract_mutation '
        .source_remarks += [.source_remarks[0]] |
        .source_remarks[1].verbatim_quote = "Conflicting duplicate authority."
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_AUTHORITY_DUPLICATE:source-0001"* ]]
}

@test "tier-one authority reference belongs to the requirement source set" {
    run reject_contract_mutation '
        .source_remarks += [{
          "source_id": "source-0002",
          "source_tier": "CUSTOMER_VERBATIM",
          "verbatim_quote": "A second independent remark.",
          "locale": "en",
          "captured_at": "2026-01-02T09:01:00Z",
          "source_ref": "customer-interview-0002",
          "requirement_ids": ["req-0001"]
        }] |
        .requirements.req-0001.tier1_assertion.authority_ref = "source-0002"
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_AUTHORITY_NOT_BOUND:req-0001:source-0002"* ]]
}

@test "acceptance rejects a dangling tier-one assertion ID" {
    run reject_contract_mutation \
        '.requirements.req-0001.acceptance.tier1_assertion_id = "assertion-9999"'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_DANGLING:assertion-9999"* ]]
}

@test "acceptance cannot replace its tier-one assertion with another valid assertion" {
    run reject_contract_mutation '
        .requirements.req-0002 = .requirements.req-0001 |
        .requirements.req-0002.tier1_assertion.assertion_id = "assertion-0002" |
        .requirements.req-0002.tier1_assertion.predicate_id = "predicate-second" |
        .requirements.req-0002.acceptance.tier1_assertion_id = "assertion-0002" |
        .requirements.req-0002.acceptance.predicate_id = "predicate-second" |
        .requirements.req-0001.acceptance.tier1_assertion_id = "assertion-0002" |
        .source_remarks[0].requirement_ids += ["req-0002"]
    '
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"TIER1_ASSERTION_REPLACED:req-0001:assertion-0002"* ]]
}

@test "legacy atomic statement is rejected even beside a valid tier-one assertion" {
    run reject_contract_mutation \
        '.requirements.req-0001.atomic_statement = "Legacy authoritative paraphrase."'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"atomic_statement"* ]]
}

@test "visitor acceptance requires a closed production assertion" {
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.production_assertion)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion"* ]]
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

@test "visitor production assertion requires a surface reference and observable outcome" {
    run reject_contract_mutation \
        'del(.requirements.req-0001.acceptance.production_assertion.surface_ref)'
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion"*"surface_ref"* ]] \
        && run reject_contract_mutation \
            'del(.requirements.req-0001.acceptance.production_assertion.observable_outcome)' \
        && [ "$status" -eq 1 ] \
        && [[ "$output" == *"production_assertion"*"observable_outcome"* ]]
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
        .requirements.req-0001.acceptance.evidence.evidence_class = "NON_VISITOR" |
        .requirements.req-0001.acceptance.evidence.method = "Schema validation against the internal contract." |
        del(.requirements.req-0001.acceptance.production_assertion) |
        .requirements.req-0001.tier1_assertion.visitor_visible = false |
        .requirements.req-0001.tier1_assertion.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.tier1_assertion.applicability.not_applicable_reason = "This requirement changes an internal delivery control only." |
        .requirements.req-0001.acceptance.applicability.painted_matrix_applicable = false |
        .requirements.req-0001.acceptance.applicability.not_applicable_reason = "This requirement changes an internal delivery control only."' "$non_visitor_requirement" || return 1
    cp "$non_visitor_requirement" "$contradictory_requirement" || return 1
    yq -i '.requirements.req-0001.acceptance.evidence.evidence_class = "VISITOR_VISIBLE_PRODUCTION"' "$contradictory_requirement" || return 1
    yq -i '.requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_count = 0 |
        .requirements.req-0001.coverage_chain.implementation_delta.visitor_visible_changes = [] |
        .requirements.req-0001.coverage_chain.live_evidence.visitor_visible = false |
        .requirements.req-0001.coverage_chain.live_evidence.painted_matrix_applicable = false |
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

matrix_rules = schema["$defs"]["liveEvidence"]["allOf"][0]["then"]["properties"]["painted_matrix"]["allOf"]
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
    yq -i 'del(."$defs".liveEvidence.allOf[0].then.properties.painted_matrix.allOf[7])' "$schema_mutant" || return 1

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
