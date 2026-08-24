#!/usr/bin/env python3
"""Evaluate the frontend-design decision contract against forward scenarios."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml


EXPECTED_KINDS = [
    "Role",
    "Skill",
    "Blueprint",
    "Constraint",
    "SuccessCriterion",
    "Policy",
    "CapabilityDescription",
]
EXPECTED_SCENARIO_IDS = {
    "positive_site_wave",
    "sparse_visual_brief",
    "existing_design_system",
    "accessibility_conflict",
    "long_ru_overflow",
    "missing_matrix_cell",
    "post_hoc_unbound",
    "backend_only_migration",
}
SCENARIO_INPUT_SCHEMA = {
    "rendered_customer_surface": {"type": "boolean"},
    "backend_only": {"type": "boolean"},
    "brief_detail": {"type": "string", "enum": {"complete", "sparse"}},
    "existing_design_system": {"type": "boolean"},
    "accessibility_conflict": {"type": "boolean"},
    "ru_overflow": {"type": "boolean"},
    "evidence_cells_present": {"type": "integer", "minimum": 0, "maximum": 12},
    "binding_timing": {"type": "string", "enum": {"post_hoc", "pre_work"}},
    "binding_state": {"type": "string", "enum": {"Bound", "Gap", "Unbound"}},
    "reusable_artifacts_valid": {"type": "boolean"},
}
REQUIRED_SCENARIO_INPUTS = {
    "rendered_customer_surface",
    "backend_only",
    "evidence_cells_present",
    "binding_timing",
    "binding_state",
    "reusable_artifacts_valid",
}
REQUIRED_EXPECTED_OUTPUTS = {
    "invoke_skill",
    "design_action",
    "knowledge_contract_state",
    "implementation_allowed",
    "product_code_emitted",
}
DOC_PATHS = [
    "skills/frontend-design/SKILL.md",
    "skills/frontend-design/references/design-decisions.md",
    "skills/frontend-design/references/handoff-and-evidence.md",
    "agents/designer.md",
]
EXPECTED_SECTION_KEYS = {
    "activation": {"requires_rendered_customer_surface", "backend_only_invokes"},
    "workflow": {"ordered_stages", "implementation_requires_knowledge_contract_state"},
    "policies": {
        "preliminary_taste_approval_required",
        "existing_design_system_strategy",
        "accessibility_conflict_strategy",
        "accessibility_floor",
        "ru_overflow_strategy",
        "shrink_critical_text",
        "post_hoc_binding_allowed",
        "unbound_delivery_allowed",
        "replacement_default",
        "emits_product_code",
    },
    "evidence_matrix": {"locales", "viewports", "themes", "expected_cells_per_surface"},
}
EXPECTED_ROOT_KEYS = {
    "schema_version",
    "contract_id",
    "design_owner",
    "acceptance_owner",
    "managed_kinds",
    *EXPECTED_SECTION_KEYS,
    "decision_rules",
    "decision_surface_sha256",
}
ALLOWED_RULE_POLARITIES = {"forbid", "inform", "permit", "require"}
RULE_MARKER_RE = re.compile(
    r"^[ \t]*<!-- fd-rule: (?P<rule_id>[A-Z][A-Z0-9-]*); "
    r"polarity: (?P<polarity>forbid|inform|permit|require); "
    r"semantics: (?P<semantics>[a-z][a-z0-9_.-]*) -->[ \t]*$"
)
NUMBER_WORDS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
}


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = yaml.safe_load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a YAML object")
    return value


def contract_errors(contract: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    unknown_root = sorted(set(contract) - EXPECTED_ROOT_KEYS)
    if unknown_root:
        errors.append(f"unknown contract keys are forbidden: {', '.join(unknown_root)}")
    missing_root = sorted(EXPECTED_ROOT_KEYS - set(contract))
    if missing_root:
        errors.append(f"required contract keys are missing: {', '.join(missing_root)}")
    for section, expected_keys in EXPECTED_SECTION_KEYS.items():
        value = contract.get(section)
        if not isinstance(value, dict):
            errors.append(f"contract section {section} must be an object")
            continue
        unknown = sorted(set(value) - expected_keys)
        missing = sorted(expected_keys - set(value))
        if unknown:
            errors.append(f"unknown {section} keys are forbidden: {', '.join(unknown)}")
        if missing:
            errors.append(f"required {section} keys are missing: {', '.join(missing)}")
    if contract.get("schema_version") != 1:
        errors.append("contract schema_version must be 1")
    if contract.get("contract_id") != "datarim-frontend-design-decision-contract":
        errors.append("contract_id must identify the canonical frontend-design contract")
    if contract.get("managed_kinds") != EXPECTED_KINDS:
        errors.append("managed_kinds must be the exact canonical seven-kind sequence")
    if contract.get("design_owner") != "designer":
        errors.append("design_owner must be designer")
    if contract.get("acceptance_owner") != "operator":
        errors.append("acceptance_owner must be operator")

    activation = contract.get("activation") or {}
    if activation.get("requires_rendered_customer_surface") is not True:
        errors.append("frontend-design activation must require a rendered customer surface")
    if activation.get("backend_only_invokes") is not False:
        errors.append("backend-only work must not invoke frontend-design")

    workflow = contract.get("workflow") or {}
    expected_stages = [
        "reuse_inventory",
        "external_research",
        "seven_kind_gap_analysis",
        "reusable_artifact_creation_and_validation",
        "knowledge_contract_issuance",
    ]
    if workflow.get("ordered_stages") != expected_stages:
        errors.append("workflow stages must preserve the pre-code artifact sequence")
    if workflow.get("implementation_requires_knowledge_contract_state") != "MET":
        errors.append("product implementation must require Knowledge Contract MET")

    policies = contract.get("policies") or {}
    exact_policy = {
        "preliminary_taste_approval_required": False,
        "existing_design_system_strategy": "reuse_and_extend",
        "accessibility_conflict_strategy": "accessible_alternative",
        "accessibility_floor": "WCAG-2.2-AA",
        "ru_overflow_strategy": "redesign_layout",
        "shrink_critical_text": False,
        "post_hoc_binding_allowed": False,
        "unbound_delivery_allowed": False,
        "replacement_default": False,
        "emits_product_code": False,
    }
    for key, expected in exact_policy.items():
        if policies.get(key) != expected:
            errors.append(f"policy {key} must equal {expected!r}")

    matrix = contract.get("evidence_matrix") or {}
    locales = matrix.get("locales")
    viewports = matrix.get("viewports")
    themes = matrix.get("themes")
    if locales != ["RU", "EN"]:
        errors.append("evidence locales must be exactly RU and EN")
    if viewports != ["desktop", "tablet", "mobile"]:
        errors.append("evidence viewports must be exactly desktop, tablet, and mobile")
    if themes != ["light", "dark"]:
        errors.append("evidence themes must be exactly light and dark")
    if isinstance(locales, list) and isinstance(viewports, list) and isinstance(themes, list):
        calculated = len(locales) * len(viewports) * len(themes)
        if matrix.get("expected_cells_per_surface") != calculated or calculated != 12:
            errors.append("evidence matrix must be the complete 2 x 3 x 2 = 12 cells")

    rules = contract.get("decision_rules")
    if not isinstance(rules, dict) or not rules:
        errors.append("decision_rules must be a non-empty object")
    else:
        for rule_id, rule in rules.items():
            if not isinstance(rule_id, str) or not re.fullmatch(r"[A-Z][A-Z0-9-]*", rule_id):
                errors.append(f"decision rule ID is invalid: {rule_id!r}")
                continue
            if not isinstance(rule, dict):
                errors.append(f"decision rule {rule_id} must be an object")
                continue
            if set(rule) != {"polarity", "semantics", "surfaces"}:
                errors.append(
                    f"decision rule {rule_id} must contain only polarity, semantics, and surfaces"
                )
                continue
            polarity = rule.get("polarity")
            semantics = rule.get("semantics")
            surfaces = rule.get("surfaces")
            if polarity not in ALLOWED_RULE_POLARITIES:
                errors.append(f"decision rule {rule_id} has invalid polarity")
            if not isinstance(semantics, str) or not re.fullmatch(
                r"[a-z][a-z0-9_.-]*", semantics
            ):
                errors.append(f"decision rule {rule_id} has invalid semantics")
            if (
                not isinstance(surfaces, list)
                or not surfaces
                or len(surfaces) != len(set(surfaces))
                or any(surface not in DOC_PATHS for surface in surfaces)
            ):
                errors.append(f"decision rule {rule_id} has invalid surfaces")

    digests = contract.get("decision_surface_sha256")
    if not isinstance(digests, dict) or set(digests) != set(DOC_PATHS):
        errors.append("decision_surface_sha256 must pin exactly the four decision surfaces")
    elif any(not re.fullmatch(r"[0-9a-f]{64}", str(value)) for value in digests.values()):
        errors.append("decision surface digests must be lowercase SHA-256 values")
    return errors


def _scenario_value_errors(scenario_id: str, values: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for key, value in values.items():
        schema = SCENARIO_INPUT_SCHEMA.get(key)
        if schema is None:
            continue
        expected_type = schema["type"]
        type_valid = (
            (expected_type == "boolean" and type(value) is bool)
            or (expected_type == "integer" and type(value) is int)
            or (expected_type == "string" and type(value) is str)
        )
        if not type_valid:
            errors.append(f"scenario {scenario_id} input {key} must be {expected_type}")
            continue
        allowed = schema.get("enum")
        if allowed is not None and value not in allowed:
            errors.append(
                f"scenario {scenario_id} input {key} must be one of: "
                + ", ".join(sorted(allowed))
            )
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if minimum is not None and value < minimum:
            errors.append(f"scenario {scenario_id} input {key} must be >= {minimum}")
        if maximum is not None and value > maximum:
            errors.append(f"scenario {scenario_id} input {key} must be <= {maximum}")
    return errors


def scenario_errors(corpus: dict[str, Any]) -> list[str]:
    """Validate that the forward corpus cannot silently omit a claimed output."""

    errors: list[str] = []
    scenarios = corpus.get("scenarios")
    if corpus.get("schema_version") != 1:
        errors.append("scenario corpus schema_version must be 1")
    if not isinstance(scenarios, list):
        return [*errors, "scenario corpus scenarios must be a list"]
    ids = [item.get("id") for item in scenarios if isinstance(item, dict)]
    if len(scenarios) != 8 or len(ids) != 8 or set(ids) != EXPECTED_SCENARIO_IDS:
        errors.append("scenario corpus must contain each of the exact eight scenario IDs once")
    if len(ids) != len(set(ids)):
        errors.append("scenario IDs must be unique")
    for index, scenario in enumerate(scenarios):
        if not isinstance(scenario, dict):
            errors.append(f"scenario at index {index} must be an object")
            continue
        scenario_id = scenario.get("id", f"index-{index}")
        if set(scenario) != {"id", "input", "expected"}:
            errors.append(f"scenario {scenario_id} must contain only id, input, and expected")
        values = scenario.get("input")
        expected = scenario.get("expected")
        if not isinstance(values, dict):
            errors.append(f"scenario {scenario_id} input must be an object")
        else:
            unknown_inputs = sorted(set(values) - set(SCENARIO_INPUT_SCHEMA))
            missing_inputs = sorted(REQUIRED_SCENARIO_INPUTS - set(values))
            if unknown_inputs:
                errors.append(f"scenario {scenario_id} has unknown inputs: {', '.join(unknown_inputs)}")
            if missing_inputs:
                errors.append(f"scenario {scenario_id} is missing inputs: {', '.join(missing_inputs)}")
            errors.extend(_scenario_value_errors(str(scenario_id), values))
        if not isinstance(expected, dict):
            errors.append(f"scenario {scenario_id} expected must be an object")
        else:
            missing_outputs = sorted(REQUIRED_EXPECTED_OUTPUTS - set(expected))
            if missing_outputs:
                errors.append(f"scenario {scenario_id} is missing expected outputs: {', '.join(missing_outputs)}")
    return errors


def _is_negated(line: str) -> bool:
    return bool(re.search(r"\b(do not|does not|is not|must not|never|no .* required|cannot)\b", line))


def _declared_cell_counts(line: str) -> set[int]:
    counts = {int(value) for value in re.findall(r"\b(\d{1,2})[ -]cell", line)}
    for word, number in NUMBER_WORDS.items():
        if re.search(rf"\b{word}[ -]cell", line):
            counts.add(number)
        if re.search(rf"\b{word} cells\b", line):
            counts.add(number)
    return counts


def documentation_errors(root: Path, contract: dict[str, Any]) -> list[str]:
    """Reject unbound prose and unsafe claims on every decision surface."""

    errors: list[str] = []
    expected_cells = (contract.get("evidence_matrix") or {}).get("expected_cells_per_surface")
    expected_digests = contract.get("decision_surface_sha256") or {}
    declared_rules = contract.get("decision_rules") or {}
    used_rules: set[str] = set()
    for relative in DOC_PATHS:
        path = root / relative
        if not path.is_file():
            errors.append(f"missing decision surface: {relative}")
            continue
        content = path.read_bytes()
        actual_digest = hashlib.sha256(content).hexdigest()
        if expected_digests.get(relative) != actual_digest:
            errors.append(f"{relative}: decision surface digest mismatch")
        lines = content.decode("utf-8").splitlines()
        in_frontmatter = bool(lines and lines[0].strip() == "---")
        blocks: list[list[tuple[int, str]]] = []
        block: list[tuple[int, str]] = []
        for number, raw in enumerate(lines, start=1):
            if in_frontmatter:
                if number > 1 and raw.strip() == "---":
                    in_frontmatter = False
                continue
            if raw.strip():
                block.append((number, raw))
            elif block:
                blocks.append(block)
                block = []
        if block:
            blocks.append(block)

        for block in blocks:
            first_number, first_raw = block[0]
            location = f"{relative}:{first_number}"
            marker = RULE_MARKER_RE.fullmatch(first_raw)
            if marker is None:
                errors.append(f"{location}: untagged decision line")
                visible_lines = block
            else:
                rule_id = marker.group("rule_id")
                used_rules.add(rule_id)
                declared = declared_rules.get(rule_id)
                if not isinstance(declared, dict):
                    errors.append(f"{location}: unknown decision rule {rule_id}")
                else:
                    if declared.get("polarity") != marker.group("polarity"):
                        errors.append(f"{location}: decision rule {rule_id} polarity mismatch")
                    if declared.get("semantics") != marker.group("semantics"):
                        errors.append(f"{location}: decision rule {rule_id} semantics mismatch")
                    if relative not in (declared.get("surfaces") or []):
                        errors.append(f"{location}: decision rule {rule_id} is not authorized for this surface")
                if len(block) == 1:
                    errors.append(f"{location}: decision rule marker must bind visible content")
                    continue
                visible_lines = block[1:]
            for number, raw in visible_lines:
                line = raw.strip().lower()
                line_location = f"{relative}:{number}"
                if RULE_MARKER_RE.fullmatch(raw):
                    errors.append(f"{line_location}: decision rule marker is not block-leading")
                    continue
                if "backend-only" in line and "invoke" in line and not _is_negated(line):
                    errors.append(f"{line_location}: unsafe backend-only invocation rule")
                if ("cell" in line or "matrix" in line) and "sufficient" in line:
                    for count in _declared_cell_counts(line):
                        if count != expected_cells:
                            errors.append(f"{line_location}: unsafe {count}-cell sufficiency rule")
                if "taste approval" in line and "pause" in line and not _is_negated(line):
                    errors.append(f"{line_location}: preliminary taste approval pause contradicts policy")
                if "post-hoc" in line and re.search(r"\b(allow|accept|valid|bind)\w*\b", line) and not _is_negated(line):
                    errors.append(f"{line_location}: post-hoc binding is allowed")
                if "unbound" in line and re.search(r"\b(allow|accept|valid|delivery)\w*\b", line) and not _is_negated(line):
                    errors.append(f"{line_location}: Unbound delivery is allowed")
                if "designer" in line and "acceptance" in line and re.search(r"\b(owns|grants|claims|approves)\b", line) and not _is_negated(line):
                    errors.append(f"{line_location}: designer is assigned acceptance authority")
                if "product code" in line and re.search(r"\b(may|can|allowed to)\b.*\b(start|begin|ship)\b", line) and not _is_negated(line):
                    errors.append(f"{line_location}: product code is allowed before the MET gate")
                if "competency" in line and "managed kind" in line and not _is_negated(line):
                    errors.append(f"{line_location}: Competency is declared as a managed kind")
    if isinstance(declared_rules, dict):
        for rule_id in sorted(set(declared_rules) - used_rules):
            errors.append(f"decision rule {rule_id} is declared but unused")
    return errors


def evaluate(contract: dict[str, Any], scenario: dict[str, Any]) -> dict[str, Any]:
    values = scenario.get("input") or {}
    policies = contract["policies"]
    matrix = contract["evidence_matrix"]
    required_cells = matrix["expected_cells_per_surface"]
    present_cells = int(values.get("evidence_cells_present", 0))
    rendered = values.get("rendered_customer_surface") is True
    backend_only = values.get("backend_only") is True
    invoke = rendered and not backend_only

    result: dict[str, Any] = {
        "scenario_id": scenario.get("id"),
        "invoke_skill": invoke,
        "design_owner": contract["design_owner"],
        "acceptance_owner": contract["acceptance_owner"],
        "product_code_emitted": policies["emits_product_code"],
        "approval_pause": policies["preliminary_taste_approval_required"],
        "replacement_default": policies["replacement_default"],
        "accessibility_floor": policies["accessibility_floor"],
        "shrink_critical_text": policies["shrink_critical_text"],
        "evidence_cells_required": required_cells,
        "evidence_cells_present": present_cells,
    }
    if not invoke:
        result.update(
            design_action="route_without_frontend_design",
            knowledge_contract_state="NOT_APPLICABLE",
            implementation_allowed=None,
            binding_accepted=None,
        )
        return result

    timing = values.get("binding_timing")
    binding_state = values.get("binding_state")
    binding_accepted = timing == "pre_work" and binding_state == "Bound"
    result["binding_accepted"] = binding_accepted

    if timing == "post_hoc" or binding_state == "Unbound":
        action = "reject_binding"
    elif values.get("accessibility_conflict") is True:
        action = policies["accessibility_conflict_strategy"]
    elif values.get("ru_overflow") is True:
        action = policies["ru_overflow_strategy"]
    elif values.get("existing_design_system") is True:
        action = policies["existing_design_system_strategy"]
    elif values.get("brief_detail") == "sparse":
        action = "produce_first_direction"
    elif not binding_accepted:
        action = "produce_first_direction"
    elif present_cells != required_cells:
        action = "complete_evidence_plan"
    else:
        action = "produce_design_packet"

    artifacts_valid = values.get("reusable_artifacts_valid") is True
    contract_met = binding_accepted and artifacts_valid and present_cells == required_cells
    result.update(
        design_action=action,
        knowledge_contract_state="MET" if contract_met else "NOT_MET",
        implementation_allowed=contract_met,
    )
    return result


def expected_mismatches(actual: dict[str, Any], expected: dict[str, Any]) -> list[str]:
    return [
        f"{key}: expected {value!r}, got {actual.get(key)!r}"
        for key, value in expected.items()
        if actual.get(key) != value
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--scenarios", type=Path, required=True)
    parser.add_argument("--docs-root", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--scenario")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--describe-contract", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        contract = load_yaml(args.contract)
        corpus = load_yaml(args.scenarios)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(json.dumps({"error": str(exc)}))
        return 2

    errors = contract_errors(contract)
    corpus_errors = scenario_errors(corpus)
    doc_errors = documentation_errors(args.docs_root, contract)
    if errors or corpus_errors or doc_errors:
        print(
            json.dumps(
                {
                    "contract_errors": errors,
                    "scenario_errors": corpus_errors,
                    "documentation_errors": doc_errors,
                },
                sort_keys=True,
            )
        )
        return 1

    if args.describe_contract:
        print(
            json.dumps(
                {
                    "managed_kinds": contract["managed_kinds"],
                    "implementation_requires": contract["workflow"]["implementation_requires_knowledge_contract_state"],
                    "post_hoc_allowed": contract["policies"]["post_hoc_binding_allowed"],
                    "unbound_delivery_allowed": contract["policies"]["unbound_delivery_allowed"],
                },
                sort_keys=True,
            )
        )
        return 0

    scenarios = corpus["scenarios"]

    if args.scenario:
        selected = [item for item in scenarios if item.get("id") == args.scenario]
        if len(selected) != 1:
            print(json.dumps({"error": f"unknown or duplicate scenario: {args.scenario}"}))
            return 2
        print(json.dumps(evaluate(contract, selected[0]), sort_keys=True))
        return 0

    failures: list[dict[str, Any]] = []
    for scenario in scenarios:
        actual = evaluate(contract, scenario)
        mismatches = expected_mismatches(actual, scenario.get("expected") or {})
        if mismatches:
            failures.append({"scenario_id": scenario.get("id"), "mismatches": mismatches})
    print(
        json.dumps(
            {
                "checked": len(scenarios),
                "contract_valid": True,
                "docs_consistent": True,
                "failures": len(failures),
                "details": failures,
            },
            sort_keys=True,
        )
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
