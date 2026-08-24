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
from yaml.constructor import ConstructorError
from yaml.events import AliasEvent, MappingStartEvent, ScalarEvent, SequenceStartEvent
from yaml.nodes import MappingNode


MAX_YAML_BYTES = 1_048_576
MAX_YAML_DEPTH = 64
MAX_YAML_NODES = 20_000


class StrictSafeLoader(yaml.SafeLoader):
    """Safe YAML loader with a closed, string-keyed mapping grammar."""


def _construct_strict_mapping(
    loader: StrictSafeLoader, node: MappingNode, deep: bool = False
) -> dict[str, Any]:
    if not isinstance(node, MappingNode):
        raise ConstructorError(None, None, "expected a YAML mapping", node.start_mark)
    mapping: dict[str, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if type(key) is not str:
            raise ConstructorError(
                None, None, "mapping keys must be strings", key_node.start_mark
            )
        if key in mapping:
            raise ConstructorError(
                None, None, f"duplicate YAML key: {key}", key_node.start_mark
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


StrictSafeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_strict_mapping
)


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
    "evidence_cells": {"type": "array"},
    "binding_timing": {"type": "string", "enum": {"post_hoc", "pre_work"}},
    "binding_state": {"type": "string", "enum": {"Bound", "Gap", "Unbound"}},
    "reusable_artifacts_valid": {"type": "boolean"},
}
REQUIRED_SCENARIO_INPUTS = {
    "rendered_customer_surface",
    "backend_only",
    "evidence_cells",
    "binding_timing",
    "binding_state",
    "reusable_artifacts_valid",
}
EXPECTED_OUTPUT_SCHEMA = {
    "invoke_skill": {"type": "boolean"},
    "design_action": {
        "type": "string",
        "enum": {
            "accessible_alternative",
            "complete_evidence_plan",
            "produce_design_packet",
            "produce_first_direction",
            "redesign_layout",
            "reject_binding",
            "reuse_and_extend",
            "route_without_frontend_design",
        },
    },
    "knowledge_contract_state": {"type": "string", "enum": {"MET", "NOT_APPLICABLE", "NOT_MET"}},
    "implementation_allowed": {"type": "boolean", "nullable": True},
    "product_code_emitted": {"type": "boolean"},
    "approval_pause": {"type": "boolean"},
    "replacement_default": {"type": "boolean"},
    "accessibility_floor": {"type": "string", "enum": {"WCAG-2.2-AA"}},
    "shrink_critical_text": {"type": "boolean"},
    "evidence_cells_required": {"type": "integer", "minimum": 0, "maximum": 12},
    "evidence_cells_present": {"type": "integer", "minimum": 0, "maximum": 12},
    "binding_accepted": {"type": "boolean"},
}
EXPECTED_KEYS_BY_SCENARIO = {
    "positive_site_wave": {
        "invoke_skill", "design_action", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
    "sparse_visual_brief": {
        "invoke_skill", "design_action", "approval_pause", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
    "existing_design_system": {
        "invoke_skill", "design_action", "replacement_default", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
    "accessibility_conflict": {
        "invoke_skill", "design_action", "accessibility_floor", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
    "long_ru_overflow": {
        "invoke_skill", "design_action", "shrink_critical_text", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
    "missing_matrix_cell": {
        "invoke_skill", "design_action", "evidence_cells_required", "evidence_cells_present",
        "knowledge_contract_state", "implementation_allowed", "product_code_emitted",
    },
    "post_hoc_unbound": {
        "invoke_skill", "design_action", "binding_accepted", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
    "backend_only_migration": {
        "invoke_skill", "design_action", "knowledge_contract_state",
        "implementation_allowed", "product_code_emitted",
    },
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
    "decision_surface_metadata",
    "decision_surface_ast",
    "decision_surface_sha256",
}
CANONICAL_RULES = {'FD-SKILL-TITLE': {'polarity': 'inform',
                    'semantics': 'scope.title',
                    'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-SCOPE': {'polarity': 'inform',
                    'semantics': 'scope.definition',
                    'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-EXCLUDES': {'polarity': 'forbid',
                       'semantics': 'scope.exclusions',
                       'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-INPUTS': {'polarity': 'require',
                     'semantics': 'inputs.required',
                     'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-ASSUME': {'polarity': 'permit',
                     'semantics': 'inputs.sparse_assumptions',
                     'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-SEQUENCE': {'polarity': 'require',
                       'semantics': 'workflow.pre_code_sequence',
                       'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-BINDING': {'polarity': 'forbid',
                      'semantics': 'binding.invalid_states',
                      'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-PACKET': {'polarity': 'require',
                     'semantics': 'design.packet',
                     'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-DISCLOSURE': {'polarity': 'require',
                         'semantics': 'routing.progressive_disclosure',
                         'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-HANDOFF': {'polarity': 'inform',
                      'semantics': 'routing.post_contract',
                      'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-SKILL-BOUNDARY': {'polarity': 'forbid',
                       'semantics': 'completion.customer_acceptance',
                       'surfaces': ['skills/frontend-design/SKILL.md']},
 'FD-DESIGN-TITLE': {'polarity': 'inform',
                     'semantics': 'design.title',
                     'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-SCOPE': {'polarity': 'inform',
                     'semantics': 'design.scope',
                     'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-VISITOR': {'polarity': 'require',
                       'semantics': 'design.visitor_decision',
                       'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-REUSE': {'polarity': 'require',
                     'semantics': 'design.reuse_first',
                     'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-DIRECTION': {'polarity': 'require',
                         'semantics': 'design.selected_direction',
                         'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-TOKENS': {'polarity': 'require',
                      'semantics': 'design.semantic_visual_rules',
                      'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-RESPONSIVE': {'polarity': 'require',
                          'semantics': 'design.responsive_i18n',
                          'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-DESIGN-A11Y': {'polarity': 'require',
                    'semantics': 'design.accessibility_performance',
                    'surfaces': ['skills/frontend-design/references/design-decisions.md']},
 'FD-HANDOFF-TITLE': {'polarity': 'inform',
                      'semantics': 'handoff.title',
                      'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-SCOPE': {'polarity': 'inform',
                      'semantics': 'handoff.scope',
                      'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-PACKET': {'polarity': 'require',
                       'semantics': 'handoff.packet',
                       'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-KC-REQUIRE': {'polarity': 'require',
                           'semantics': 'handoff.knowledge_contract_gate',
                           'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-KC-FORBID': {'polarity': 'forbid',
                          'semantics': 'handoff.invalid_bindings',
                          'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-AUTONOMY': {'polarity': 'permit',
                         'semantics': 'handoff.autonomous_first_result',
                         'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-EVIDENCE': {'polarity': 'require',
                         'semantics': 'handoff.evidence_matrix',
                         'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-AUTOMATION-LIMIT': {'polarity': 'forbid',
                                 'semantics': 'handoff.automated_acceptance',
                                 'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-OUTCOMES': {'polarity': 'inform',
                         'semantics': 'handoff.outcomes',
                         'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-HANDOFF-ACCEPTANCE': {'polarity': 'forbid',
                           'semantics': 'handoff.customer_acceptance',
                           'surfaces': ['skills/frontend-design/references/handoff-and-evidence.md']},
 'FD-ROLE-TITLE': {'polarity': 'inform',
                   'semantics': 'role.title',
                   'surfaces': ['agents/designer.md']},
 'FD-ROLE-GOAL': {'polarity': 'require',
                  'semantics': 'role.goal',
                  'surfaces': ['agents/designer.md']},
 'FD-ROLE-RESPONSIBILITIES': {'polarity': 'require',
                              'semantics': 'role.responsibilities',
                              'surfaces': ['agents/designer.md']},
 'FD-ROLE-BOUNDARIES': {'polarity': 'forbid',
                        'semantics': 'role.boundaries',
                        'surfaces': ['agents/designer.md']},
 'FD-ROLE-CONTEXT': {'polarity': 'require',
                     'semantics': 'role.context',
                     'surfaces': ['agents/designer.md']},
 'FD-ROLE-OUTPUT': {'polarity': 'require',
                    'semantics': 'role.output',
                    'surfaces': ['agents/designer.md']}}

CANONICAL_SURFACE_METADATA = {'skills/frontend-design/SKILL.md': {'kind': 'skill',
                                     'identity': 'frontend-design',
                                     'description_id': 'frontend-design-discovery',
                                     'current_aal': 1,
                                     'target_aal': 2},
 'skills/frontend-design/references/design-decisions.md': {'kind': 'reference'},
 'skills/frontend-design/references/handoff-and-evidence.md': {'kind': 'reference'},
 'agents/designer.md': {'kind': 'agent',
                        'identity': 'designer',
                        'description_id': 'designer-role-discovery',
                        'model': 'inherit',
                        'model_tier': 'reasoning'}}

CANONICAL_SURFACE_AST = {'skills/frontend-design/SKILL.md': [{'clause_id': 'FD-SKILL-TITLE-01',
                                      'rule_id': 'FD-SKILL-TITLE',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-SCOPE-01',
                                      'rule_id': 'FD-SKILL-SCOPE',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-EXCLUDES-01',
                                      'rule_id': 'FD-SKILL-EXCLUDES',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-INPUTS-01',
                                      'rule_id': 'FD-SKILL-INPUTS',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-INPUTS-02',
                                      'rule_id': 'FD-SKILL-INPUTS',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-ASSUME-01',
                                      'rule_id': 'FD-SKILL-ASSUME',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-SEQUENCE-01',
                                      'rule_id': 'FD-SKILL-SEQUENCE',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-SEQUENCE-02',
                                      'rule_id': 'FD-SKILL-SEQUENCE',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-SEQUENCE-03',
                                      'rule_id': 'FD-SKILL-SEQUENCE',
                                      'params': {'stages': ['reuse_inventory',
                                                            'external_research',
                                                            'seven_kind_gap_analysis',
                                                            'reusable_artifact_creation_and_validation',
                                                            'knowledge_contract_issuance']}},
                                     {'clause_id': 'FD-SKILL-BINDING-01',
                                      'rule_id': 'FD-SKILL-BINDING',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-PACKET-01',
                                      'rule_id': 'FD-SKILL-PACKET',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-PACKET-02',
                                      'rule_id': 'FD-SKILL-PACKET',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-PACKET-03',
                                      'rule_id': 'FD-SKILL-PACKET',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-PACKET-04',
                                      'rule_id': 'FD-SKILL-PACKET',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-DISCLOSURE-01',
                                      'rule_id': 'FD-SKILL-DISCLOSURE',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-DISCLOSURE-02',
                                      'rule_id': 'FD-SKILL-DISCLOSURE',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-HANDOFF-01',
                                      'rule_id': 'FD-SKILL-HANDOFF',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-BOUNDARY-01',
                                      'rule_id': 'FD-SKILL-BOUNDARY',
                                      'params': {}},
                                     {'clause_id': 'FD-SKILL-BOUNDARY-02',
                                      'rule_id': 'FD-SKILL-BOUNDARY',
                                      'params': {}}],
 'skills/frontend-design/references/design-decisions.md': [{'clause_id': 'FD-DESIGN-TITLE-01',
                                                            'rule_id': 'FD-DESIGN-TITLE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-SCOPE-01',
                                                            'rule_id': 'FD-DESIGN-SCOPE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-VISITOR-01',
                                                            'rule_id': 'FD-DESIGN-VISITOR',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-VISITOR-02',
                                                            'rule_id': 'FD-DESIGN-VISITOR',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-VISITOR-03',
                                                            'rule_id': 'FD-DESIGN-VISITOR',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-REUSE-01',
                                                            'rule_id': 'FD-DESIGN-REUSE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-REUSE-02',
                                                            'rule_id': 'FD-DESIGN-REUSE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-REUSE-03',
                                                            'rule_id': 'FD-DESIGN-REUSE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-DIRECTION-01',
                                                            'rule_id': 'FD-DESIGN-DIRECTION',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-DIRECTION-02',
                                                            'rule_id': 'FD-DESIGN-DIRECTION',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-DIRECTION-03',
                                                            'rule_id': 'FD-DESIGN-DIRECTION',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-TOKENS-01',
                                                            'rule_id': 'FD-DESIGN-TOKENS',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-TOKENS-02',
                                                            'rule_id': 'FD-DESIGN-TOKENS',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-TOKENS-03',
                                                            'rule_id': 'FD-DESIGN-TOKENS',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-TOKENS-04',
                                                            'rule_id': 'FD-DESIGN-TOKENS',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-TOKENS-05',
                                                            'rule_id': 'FD-DESIGN-TOKENS',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-RESPONSIVE-01',
                                                            'rule_id': 'FD-DESIGN-RESPONSIVE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-RESPONSIVE-02',
                                                            'rule_id': 'FD-DESIGN-RESPONSIVE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-RESPONSIVE-03',
                                                            'rule_id': 'FD-DESIGN-RESPONSIVE',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-A11Y-01',
                                                            'rule_id': 'FD-DESIGN-A11Y',
                                                            'params': {}},
                                                           {'clause_id': 'FD-DESIGN-A11Y-02',
                                                            'rule_id': 'FD-DESIGN-A11Y',
                                                            'params': {'accessibility_floor': 'WCAG-2.2-AA'}},
                                                           {'clause_id': 'FD-DESIGN-A11Y-03',
                                                            'rule_id': 'FD-DESIGN-A11Y',
                                                            'params': {}}],
 'skills/frontend-design/references/handoff-and-evidence.md': [{'clause_id': 'FD-HANDOFF-TITLE-01',
                                                                'rule_id': 'FD-HANDOFF-TITLE',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-SCOPE-01',
                                                                'rule_id': 'FD-HANDOFF-SCOPE',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-PACKET-01',
                                                                'rule_id': 'FD-HANDOFF-PACKET',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-PACKET-02',
                                                                'rule_id': 'FD-HANDOFF-PACKET',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-PACKET-03',
                                                                'rule_id': 'FD-HANDOFF-PACKET',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-PACKET-04',
                                                                'rule_id': 'FD-HANDOFF-PACKET',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-KC-REQUIRE-01',
                                                                'rule_id': 'FD-HANDOFF-KC-REQUIRE',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-KC-REQUIRE-02',
                                                                'rule_id': 'FD-HANDOFF-KC-REQUIRE',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-KC-FORBID-01',
                                                                'rule_id': 'FD-HANDOFF-KC-FORBID',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-AUTONOMY-01',
                                                                'rule_id': 'FD-HANDOFF-AUTONOMY',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-EVIDENCE-01',
                                                                'rule_id': 'FD-HANDOFF-EVIDENCE',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-EVIDENCE-02',
                                                                'rule_id': 'FD-HANDOFF-EVIDENCE',
                                                                'params': {'locales': ['RU', 'EN'],
                                                                           'viewports': ['desktop',
                                                                                         'tablet',
                                                                                         'mobile'],
                                                                           'themes': ['light',
                                                                                      'dark'],
                                                                           'expected_cells': 12}},
                                                               {'clause_id': 'FD-HANDOFF-EVIDENCE-03',
                                                                'rule_id': 'FD-HANDOFF-EVIDENCE',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-AUTOMATION-LIMIT-01',
                                                                'rule_id': 'FD-HANDOFF-AUTOMATION-LIMIT',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-OUTCOMES-01',
                                                                'rule_id': 'FD-HANDOFF-OUTCOMES',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-OUTCOMES-02',
                                                                'rule_id': 'FD-HANDOFF-OUTCOMES',
                                                                'params': {}},
                                                               {'clause_id': 'FD-HANDOFF-ACCEPTANCE-01',
                                                                'rule_id': 'FD-HANDOFF-ACCEPTANCE',
                                                                'params': {}}],
 'agents/designer.md': [{'clause_id': 'FD-ROLE-TITLE-01', 'rule_id': 'FD-ROLE-TITLE', 'params': {}},
                        {'clause_id': 'FD-ROLE-GOAL-01', 'rule_id': 'FD-ROLE-GOAL', 'params': {}},
                        {'clause_id': 'FD-ROLE-RESPONSIBILITIES-01',
                         'rule_id': 'FD-ROLE-RESPONSIBILITIES',
                         'params': {}},
                        {'clause_id': 'FD-ROLE-BOUNDARIES-01',
                         'rule_id': 'FD-ROLE-BOUNDARIES',
                         'params': {}},
                        {'clause_id': 'FD-ROLE-CONTEXT-01',
                         'rule_id': 'FD-ROLE-CONTEXT',
                         'params': {}},
                        {'clause_id': 'FD-ROLE-OUTPUT-01',
                         'rule_id': 'FD-ROLE-OUTPUT',
                         'params': {}}]}

CANONICAL_CLAUSE_SPECS = {'FD-SKILL-TITLE-01': {'rule_id': 'FD-SKILL-TITLE', 'params': {}, 'text': '# Frontend Design'},
 'FD-SKILL-SCOPE-01': {'rule_id': 'FD-SKILL-SCOPE',
                       'params': {},
                       'text': 'Use this skill before product code when a task creates or '
                               'materially changes a\n'
                               'rendered customer-facing surface. It turns atomic customer '
                               'requirements into a\n'
                               'designer-owned design packet and a Knowledge Contract-ready '
                               'handoff. It does\n'
                               'not implement HTML/CSS/components, capture final browser evidence, '
                               'or grant\n'
                               'customer acceptance.'},
 'FD-SKILL-EXCLUDES-01': {'rule_id': 'FD-SKILL-EXCLUDES',
                          'params': {},
                          'text': 'For backend-only, data-only, infrastructure-only, or '
                                  'non-rendered work, do not invoke this skill.\n'
                                  'Content-only work uses this skill only when hierarchy, layout, '
                                  'interaction, or\n'
                                  'visual treatment changes materially.'},
 'FD-SKILL-INPUTS-01': {'rule_id': 'FD-SKILL-INPUTS', 'params': {}, 'text': '## Required inputs'},
 'FD-SKILL-INPUTS-02': {'rule_id': 'FD-SKILL-INPUTS',
                        'params': {},
                        'text': '- Verbatim customer remarks mapped to stable atomic Requirement '
                                'IDs.\n'
                                '- Affected routes or surface classes, locales, viewport classes, '
                                'and themes.\n'
                                '- Current product screenshots or renderable source, brand assets, '
                                'tokens,\n'
                                '  components, content, and known constraints.\n'
                                '- The applicable project authority, lifecycle, and Knowledge '
                                'Contract rules.'},
 'FD-SKILL-ASSUME-01': {'rule_id': 'FD-SKILL-ASSUME',
                        'params': {},
                        'text': 'If an input is sparse, make the smallest safe assumption that '
                                'preserves the\n'
                                "customer's stated outcome, label it, and continue. A missing "
                                'preliminary taste\n'
                                'review is not a routine implementation gate.'},
 'FD-SKILL-SEQUENCE-01': {'rule_id': 'FD-SKILL-SEQUENCE',
                          'params': {},
                          'text': '## Pre-code sequence'},
 'FD-SKILL-SEQUENCE-02': {'rule_id': 'FD-SKILL-SEQUENCE',
                          'params': {},
                          'text': 'Perform these steps in order and preserve their evidence:'},
 'FD-SKILL-SEQUENCE-03': {'rule_id': 'FD-SKILL-SEQUENCE',
                          'params': {'stages': ['reuse_inventory',
                                                'external_research',
                                                'seven_kind_gap_analysis',
                                                'reusable_artifact_creation_and_validation',
                                                'knowledge_contract_issuance']},
                          'text': None},
 'FD-SKILL-BINDING-01': {'rule_id': 'FD-SKILL-BINDING',
                         'params': {},
                         'text': '`Gap` and `Unbound` authorize research or artifact creation '
                                 'only. They cannot\n'
                                 'be delivery bindings. Never select an artifact after '
                                 'implementation starts and\n'
                                 'present the selection as if it governed that implementation.'},
 'FD-SKILL-PACKET-01': {'rule_id': 'FD-SKILL-PACKET', 'params': {}, 'text': '## Design packet'},
 'FD-SKILL-PACKET-02': {'rule_id': 'FD-SKILL-PACKET',
                        'params': {},
                        'text': 'The designer owns the following pre-code decisions:'},
 'FD-SKILL-PACKET-03': {'rule_id': 'FD-SKILL-PACKET',
                        'params': {},
                        'text': '- visitor, primary task, first-screen promise, trust evidence, '
                                'and ordered\n'
                                '  content hierarchy;\n'
                                '- primary and secondary actions with visible outcomes;\n'
                                '- two or more viable directions when the choice is material, with '
                                'a selected\n'
                                '  direction and explicit reasons;\n'
                                '- semantic design tokens and component states for light and dark '
                                'themes;\n'
                                '- responsive behavior for desktop, tablet, and mobile, including '
                                'keyboard,\n'
                                '  pointer, and touch intent;\n'
                                '- RU/EN semantic parity and realistic long-copy stress behavior;\n'
                                '- accessibility and performance constraints expressed as '
                                'observable criteria;\n'
                                '- a route/surface evidence plan covering the complete required '
                                'matrix.'},
 'FD-SKILL-PACKET-04': {'rule_id': 'FD-SKILL-PACKET',
                        'params': {},
                        'text': 'Use '
                                '`${DATARIM_RUNTIME:-$HOME/.claude}/templates/frontend-design-brief.md` '
                                'for\n'
                                'the reusable packet structure.'},
 'FD-SKILL-DISCLOSURE-01': {'rule_id': 'FD-SKILL-DISCLOSURE',
                            'params': {},
                            'text': '## Progressive disclosure'},
 'FD-SKILL-DISCLOSURE-02': {'rule_id': 'FD-SKILL-DISCLOSURE',
                            'params': {},
                            'text': '- Read `references/decision-contract.yaml` before routing or '
                                    'handoff. It is the\n'
                                    '  deterministic authority for activation, stage order, '
                                    'ownership, evidence\n'
                                    '  axes, and safe conflict resolution; prose may explain but '
                                    'never override it.\n'
                                    '- Read `references/design-decisions.md` when choosing '
                                    'hierarchy, visual\n'
                                    '  direction, tokens, responsive behavior, theme behavior, '
                                    'i18n treatment,\n'
                                    '  accessibility, or performance constraints.\n'
                                    '- Read `references/handoff-and-evidence.md` when assembling '
                                    'the design packet,\n'
                                    '  checking Knowledge Contract readiness, or handing work to '
                                    'implementation and\n'
                                    '  browser QA.'},
 'FD-SKILL-HANDOFF-01': {'rule_id': 'FD-SKILL-HANDOFF',
                         'params': {},
                         'text': 'After the contract is `MET`, route implementation hygiene to\n'
                                 '`skills/frontend-ui/SKILL.md` and browser capture to\n'
                                 '`skills/playwright-qa/SKILL.md`. Those skills verify '
                                 'implementation and output;\n'
                                 'they do not replace this pre-code design decision surface.'},
 'FD-SKILL-BOUNDARY-01': {'rule_id': 'FD-SKILL-BOUNDARY',
                          'params': {},
                          'text': '## Completion boundary'},
 'FD-SKILL-BOUNDARY-02': {'rule_id': 'FD-SKILL-BOUNDARY',
                          'params': {},
                          'text': 'This skill completes when the design packet is internally '
                                  'consistent, all\n'
                                  'missing reusable artifacts are validated, and the issued '
                                  'Knowledge Contract is\n'
                                  '`MET`. The designer may recommend a direction but MUST NOT '
                                  'claim customer or\n'
                                  'operator acceptance. Final qualitative disposition remains with '
                                  'the authorized\n'
                                  'operator after production evidence exists.'},
 'FD-DESIGN-TITLE-01': {'rule_id': 'FD-DESIGN-TITLE',
                        'params': {},
                        'text': '# Frontend design decisions'},
 'FD-DESIGN-SCOPE-01': {'rule_id': 'FD-DESIGN-SCOPE',
                        'params': {},
                        'text': 'Read this reference only when a frontend-design task needs '
                                'concrete design\n'
                                "decisions. Preserve the project's brand and stack; external "
                                'design systems are\n'
                                'evidence sources, not visual themes to copy.'},
 'FD-DESIGN-VISITOR-01': {'rule_id': 'FD-DESIGN-VISITOR',
                          'params': {},
                          'text': '## Start from the visitor decision'},
 'FD-DESIGN-VISITOR-02': {'rule_id': 'FD-DESIGN-VISITOR',
                          'params': {},
                          'text': 'State the visitor, the decision or task the surface supports, '
                                  'the first-screen\n'
                                  'promise, and the evidence required to trust that promise. Order '
                                  'content before\n'
                                  'decoration. Every primary or secondary action needs a visible '
                                  'outcome and an\n'
                                  'owner.'},
 'FD-DESIGN-VISITOR-03': {'rule_id': 'FD-DESIGN-VISITOR',
                          'params': {},
                          'text': 'Build the hierarchy from real customer remarks and '
                                  'representative content.\n'
                                  'Place proof next to the claim it supports. Separate navigation, '
                                  'explanation,\n'
                                  'evidence, action, and status so the hierarchy remains '
                                  'understandable without\n'
                                  'color or motion.'},
 'FD-DESIGN-REUSE-01': {'rule_id': 'FD-DESIGN-REUSE',
                        'params': {},
                        'text': '## Reuse before replacement'},
 'FD-DESIGN-REUSE-02': {'rule_id': 'FD-DESIGN-REUSE',
                        'params': {},
                        'text': 'Inspect the current brand assets, tokens, typography, layout '
                                'primitives,\n'
                                'components, states, and page patterns at exact source revisions. '
                                'Reuse or extend compatible tokens, components, and page patterns '
                                'before proposing replacements.\n'
                                'Record what is reused unchanged, extended, replaced, or rejected '
                                'and why.'},
 'FD-DESIGN-REUSE-03': {'rule_id': 'FD-DESIGN-REUSE',
                        'params': {},
                        'text': 'A current design system is a constraint and an asset, not '
                                'automatic proof that\n'
                                'the requested surface is already designed. Reject a pattern only '
                                'for a named\n'
                                'requirement conflict, accessibility failure, i18n failure, or '
                                'measured product\n'
                                'constraint.'},
 'FD-DESIGN-DIRECTION-01': {'rule_id': 'FD-DESIGN-DIRECTION',
                            'params': {},
                            'text': '## Choose a defensible direction'},
 'FD-DESIGN-DIRECTION-02': {'rule_id': 'FD-DESIGN-DIRECTION',
                            'params': {},
                            'text': 'When the brief is sparse, derive a defensible first direction '
                                    'from customer\n'
                                    'intent, the reuse inventory, research, and observable success '
                                    'criteria. Do not pause for preliminary taste approval. Expose '
                                    'assumptions, alternatives, and\n'
                                    'reasons so later feedback can produce a precise follow-up '
                                    'instead of erasing\n'
                                    'the first result.'},
 'FD-DESIGN-DIRECTION-03': {'rule_id': 'FD-DESIGN-DIRECTION',
                            'params': {},
                            'text': 'When alternatives are materially different, compare at least '
                                    'two across user\n'
                                    'task fit, evidence clarity, brand continuity, accessibility, '
                                    'responsive\n'
                                    'behavior, i18n risk, implementation cost, and performance '
                                    'risk. Select one;\n'
                                    'do not blend incompatible directions into an untestable '
                                    'compromise.'},
 'FD-DESIGN-TOKENS-01': {'rule_id': 'FD-DESIGN-TOKENS',
                         'params': {},
                         'text': '## Define semantic visual rules'},
 'FD-DESIGN-TOKENS-02': {'rule_id': 'FD-DESIGN-TOKENS',
                         'params': {},
                         'text': 'Prefer a bounded three-layer token model:'},
 'FD-DESIGN-TOKENS-03': {'rule_id': 'FD-DESIGN-TOKENS',
                         'params': {},
                         'text': '1. Primitive scales for color, space, type, radius, elevation, '
                                 'and motion.\n'
                                 '2. Semantic roles such as `text-primary`, `surface-raised`, '
                                 '`border-focus`,\n'
                                 '   `action-primary`, and `status-danger`.\n'
                                 '3. Component/state aliases only where a component needs a '
                                 'distinct contract.'},
 'FD-DESIGN-TOKENS-04': {'rule_id': 'FD-DESIGN-TOKENS',
                         'params': {},
                         'text': 'Specify light and dark values for every color role and test '
                                 'contrast against\n'
                                 'the actual composited background. Include default, hover, focus, '
                                 'active,\n'
                                 'disabled, loading, error, empty, success, forced-colors, and '
                                 'reduced-motion\n'
                                 'behavior where applicable. Color must not be the sole carrier of '
                                 'meaning.'},
 'FD-DESIGN-TOKENS-05': {'rule_id': 'FD-DESIGN-TOKENS',
                         'params': {},
                         'text': 'Typography must include Latin and Cyrillic glyph coverage, '
                                 'relative units,\n'
                                 'deliberate weights and line heights, and a bounded responsive '
                                 'scale. Use\n'
                                 'consistent spacing instead of arbitrary one-off values.'},
 'FD-DESIGN-RESPONSIVE-01': {'rule_id': 'FD-DESIGN-RESPONSIVE',
                             'params': {},
                             'text': '## Design responsive and input behavior'},
 'FD-DESIGN-RESPONSIVE-02': {'rule_id': 'FD-DESIGN-RESPONSIVE',
                             'params': {},
                             'text': 'Describe content priority and component transformation at '
                                     'desktop, tablet, and\n'
                                     'mobile rather than merely scaling a desktop screenshot. '
                                     'Preserve logical DOM\n'
                                     'and focus order, visible focus, keyboard operation, touch '
                                     'targets, zoom/reflow,\n'
                                     'and reduced-motion behavior. Avoid hover-only information '
                                     'and layout changes\n'
                                     'that move essential actions unpredictably.'},
 'FD-DESIGN-RESPONSIVE-03': {'rule_id': 'FD-DESIGN-RESPONSIVE',
                             'params': {},
                             'text': 'Use representative EN copy and real RU stress copy before '
                                     'handoff. When the RU\n'
                                     'variant no longer fits, redesign the container or flow; do '
                                     'not shrink critical text below the applicable policy. '
                                     'Semantic parity means equivalent claims,\n'
                                     'evidence, actions, and states, not only equal translation '
                                     'keys.'},
 'FD-DESIGN-A11Y-01': {'rule_id': 'FD-DESIGN-A11Y',
                       'params': {},
                       'text': '## Resolve accessibility and performance conflicts'},
 'FD-DESIGN-A11Y-02': {'rule_id': 'FD-DESIGN-A11Y',
                       'params': {'accessibility_floor': 'WCAG-2.2-AA'},
                       'text': None},
 'FD-DESIGN-A11Y-03': {'rule_id': 'FD-DESIGN-A11Y',
                       'params': {},
                       'text': 'Declare performance-aware design constraints before '
                               'implementation: critical\n'
                               'content priority, image dimensions and formats, font strategy, '
                               'animation\n'
                               'budget, script or interaction cost, and measurable lab/field '
                               'targets where the\n'
                               'product can support them. A score alone is not a design rationale, '
                               'and lab\n'
                               'evidence does not become production field evidence.'},
 'FD-HANDOFF-TITLE-01': {'rule_id': 'FD-HANDOFF-TITLE',
                         'params': {},
                         'text': '# Frontend design handoff and evidence'},
 'FD-HANDOFF-SCOPE-01': {'rule_id': 'FD-HANDOFF-SCOPE',
                         'params': {},
                         'text': 'Read this reference when completing the pre-code design packet '
                                 'or deciding\n'
                                 'whether it may enter implementation.'},
 'FD-HANDOFF-PACKET-01': {'rule_id': 'FD-HANDOFF-PACKET',
                          'params': {},
                          'text': '## Minimum handoff packet'},
 'FD-HANDOFF-PACKET-02': {'rule_id': 'FD-HANDOFF-PACKET',
                          'params': {},
                          'text': 'The packet must identify:'},
 'FD-HANDOFF-PACKET-03': {'rule_id': 'FD-HANDOFF-PACKET',
                          'params': {},
                          'text': '- atomic Requirement IDs and verbatim source pointers;\n'
                                  '- designer owner, affected product, routes or surface classes, '
                                  'and audience;\n'
                                  '- exact reuse inventory and external-research ledger;\n'
                                  '- seven-kind gap dispositions and every created or revised '
                                  'artifact;\n'
                                  '- content hierarchy, task flow, selected direction, '
                                  'alternatives, and reasons;\n'
                                  '- token, typography, component/state, theme, responsive, i18n, '
                                  'accessibility,\n'
                                  '  and performance contracts;\n'
                                  '- implementation boundaries and code/content owners;\n'
                                  '- acceptance methods and the planned production evidence '
                                  'cells;\n'
                                  '- the issued Knowledge Contract identifier and validation '
                                  'evidence.'},
 'FD-HANDOFF-PACKET-04': {'rule_id': 'FD-HANDOFF-PACKET',
                          'params': {},
                          'text': 'Use '
                                  '`${DATARIM_RUNTIME:-$HOME/.claude}/templates/frontend-design-brief.md` '
                                  'and\n'
                                  'link supporting artifacts rather than duplicating them.'},
 'FD-HANDOFF-KC-REQUIRE-01': {'rule_id': 'FD-HANDOFF-KC-REQUIRE',
                              'params': {},
                              'text': '## Knowledge Contract entry gate'},
 'FD-HANDOFF-KC-REQUIRE-02': {'rule_id': 'FD-HANDOFF-KC-REQUIRE',
                              'params': {},
                              'text': 'Implementation may start only when all applicable managed '
                                      'kinds are bound to\n'
                                      'immutable approved revisions and content digests selected '
                                      'before the recorded\n'
                                      'implementation start. Provenance and typed relations must '
                                      'resolve; required\n'
                                      'artifacts must pass their independent forward scenarios and '
                                      'meaningful\n'
                                      'mutations.'},
 'FD-HANDOFF-KC-FORBID-01': {'rule_id': 'FD-HANDOFF-KC-FORBID',
                             'params': {},
                             'text': 'Reject post-hoc attribution, mutable `latest` references, '
                                     'missing digests,\n'
                                     'deprecated or rejected revisions, and selection after '
                                     'implementation starts.\n'
                                     '`Gap` or `Unbound` may describe why research or artifact '
                                     'creation continues,\n'
                                     'but either state makes a delivery-bound contract `NOT_MET`.'},
 'FD-HANDOFF-AUTONOMY-01': {'rule_id': 'FD-HANDOFF-AUTONOMY',
                            'params': {},
                            'text': 'No taste-approval checkpoint is required before producing the '
                                    'first strong\n'
                                    'design packet when the operator has authorized autonomous '
                                    'execution. This does\n'
                                    'not transfer final visual acceptance to the designer.'},
 'FD-HANDOFF-EVIDENCE-01': {'rule_id': 'FD-HANDOFF-EVIDENCE',
                            'params': {},
                            'text': '## Evidence plan'},
 'FD-HANDOFF-EVIDENCE-02': {'rule_id': 'FD-HANDOFF-EVIDENCE',
                            'params': {'locales': ['RU', 'EN'],
                                       'viewports': ['desktop', 'tablet', 'mobile'],
                                       'themes': ['light', 'dark'],
                                       'expected_cells': 12},
                            'text': None},
 'FD-HANDOFF-EVIDENCE-03': {'rule_id': 'FD-HANDOFF-EVIDENCE',
                            'params': {},
                            'text': 'Each planned cell names locale, viewport dimensions and '
                                    'class, theme, route,\n'
                                    'browser/runtime version, source and deployed SHA, screenshot '
                                    'path, structural\n'
                                    'checks, accessibility result, performance result where '
                                    'applicable, and\n'
                                    'customer disposition state. A screenshot without revision and '
                                    'environment\n'
                                    'metadata is not production evidence.'},
 'FD-HANDOFF-AUTOMATION-LIMIT-01': {'rule_id': 'FD-HANDOFF-AUTOMATION-LIMIT',
                                    'params': {},
                                    'text': 'The pre-code packet defines this evidence contract. '
                                            'After implementation,\n'
                                            '`frontend-ui` checks implementation hygiene and '
                                            '`playwright-qa` captures\n'
                                            'browser artifacts. Automated checks cannot supply '
                                            'qualitative operator\n'
                                            'acceptance.'},
 'FD-HANDOFF-OUTCOMES-01': {'rule_id': 'FD-HANDOFF-OUTCOMES',
                            'params': {},
                            'text': '## Handoff outcomes'},
 'FD-HANDOFF-OUTCOMES-02': {'rule_id': 'FD-HANDOFF-OUTCOMES',
                            'params': {},
                            'text': '- `READY_FOR_CONTRACT`: design packet complete; reusable '
                                    'artifacts validated;\n'
                                    '  contract not yet issued or not yet `MET`.\n'
                                    '- `READY_FOR_IMPLEMENTATION`: issued contract is `MET`; '
                                    'implementation may\n'
                                    '  begin at the recorded timestamp.\n'
                                    '- `NOT_MET`: any required binding, relation, lifecycle '
                                    'approval, forward test,\n'
                                    '  mutation, locale, viewport, theme, or evidence plan cell is '
                                    'missing.'},
 'FD-HANDOFF-ACCEPTANCE-01': {'rule_id': 'FD-HANDOFF-ACCEPTANCE',
                              'params': {},
                              'text': 'The designer reports one of these states with evidence. The '
                                      'designer never\n'
                                      'reports the customer-visible requirement delivered; '
                                      'delivery additionally\n'
                                      'requires merged and deployed revisions, live proof, '
                                      'zero-residual review\n'
                                      'coverage, and authorized customer disposition.'},
 'FD-ROLE-TITLE-01': {'rule_id': 'FD-ROLE-TITLE',
                      'params': {},
                      'text': 'You are the **Frontend Design Lead**.'},
 'FD-ROLE-GOAL-01': {'rule_id': 'FD-ROLE-GOAL',
                     'params': {},
                     'text': 'Your goal is to make customer-visible frontend work design-ready '
                             'before product\n'
                             'implementation. The designer owns the pre-code design packet: '
                             'content hierarchy, visual\n'
                             'direction, design-system reuse, tokens and states, responsive and '
                             'theme\n'
                             'behavior, RU/EN stress behavior, accessibility and performance '
                             'constraints,\n'
                             'and the evidence plan.'},
 'FD-ROLE-RESPONSIBILITIES-01': {'rule_id': 'FD-ROLE-RESPONSIBILITIES',
                                 'params': {},
                                 'text': '**Responsibilities**:\n'
                                         '- Trace decisions to atomic verbatim customer '
                                         'requirements.\n'
                                         '- Inspect existing product and knowledge artifacts '
                                         'before proposing new ones.\n'
                                         '- Use current authoritative research and record '
                                         'replayable provenance.\n'
                                         '- Identify gaps across the seven canonical managed '
                                         'artifact kinds.\n'
                                         '- Produce a defensible first direction when taste '
                                         'guidance is sparse.\n'
                                         '- Hand off only after every missing reusable artifact is '
                                         'validated and the\n'
                                         '  issued Knowledge Contract is `MET`.'},
 'FD-ROLE-BOUNDARIES-01': {'rule_id': 'FD-ROLE-BOUNDARIES',
                           'params': {},
                           'text': '**Boundaries**:\n'
                                   '- Do not write product implementation code while acting in '
                                   'this role.\n'
                                   '- Do not treat `Gap`, `Unbound`, mutable revisions, or '
                                   'post-hoc selections as\n'
                                   '  delivery bindings.\n'
                                   '- You MAY recommend and defend a design direction, but you '
                                   'MUST NOT claim customer or operator acceptance.\n'
                                   '- Do not let an approval pause replace autonomous creation of '
                                   'a strong first\n'
                                   '  result when the operator has authorized it.'},
 'FD-ROLE-CONTEXT-01': {'rule_id': 'FD-ROLE-CONTEXT',
                        'params': {},
                        'text': '**Context Loading**:\n'
                                '- READ: the init-task append-log, atomic requirement ledger, '
                                'current product\n'
                                '  surfaces, existing design system, and applicable Knowledge '
                                'Contract.\n'
                                '- ALWAYS APPLY:\n'
                                '  - `$HOME/.claude/skills/frontend-design/SKILL.md`\n'
                                '  - `$HOME/.claude/skills/research-workflow/SKILL.md`\n'
                                '  - `$HOME/.claude/skills/customer-delivery/SKILL.md`\n'
                                '- LOAD FOR HANDOFF:\n'
                                '  - `$HOME/.claude/skills/frontend-ui/SKILL.md`\n'
                                '  - `$HOME/.claude/skills/playwright-qa/SKILL.md`'},
 'FD-ROLE-OUTPUT-01': {'rule_id': 'FD-ROLE-OUTPUT',
                       'params': {},
                       'text': '**Output**: A completed frontend design brief using\n'
                               '`${DATARIM_RUNTIME:-$HOME/.claude}/templates/frontend-design-brief.md`, '
                               'plus\n'
                               'the exact artifact and Knowledge Contract evidence required to '
                               'justify its\n'
                               'handoff state.'}}

EXPECTED_EVIDENCE_CELLS = {
    (locale, viewport, theme)
    for locale in ("RU", "EN")
    for viewport in ("desktop", "tablet", "mobile")
    for theme in ("light", "dark")
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
    raw = path.read_bytes()
    if len(raw) > MAX_YAML_BYTES:
        raise ValueError(
            f"{path}: exceeds maximum byte size {MAX_YAML_BYTES}"
        )
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path}: invalid UTF-8 at byte {exc.start}") from exc

    depth = 0
    nodes = 0
    try:
        for event in yaml.parse(text, Loader=StrictSafeLoader):
            if isinstance(event, AliasEvent):
                raise ValueError(f"{path}: YAML aliases are forbidden")
            if isinstance(event, (ScalarEvent, MappingStartEvent, SequenceStartEvent)):
                nodes += 1
                if nodes > MAX_YAML_NODES:
                    raise ValueError(
                        f"{path}: exceeds maximum node count {MAX_YAML_NODES}"
                    )
            if isinstance(event, (MappingStartEvent, SequenceStartEvent)):
                depth += 1
                if depth > MAX_YAML_DEPTH:
                    raise ValueError(
                        f"{path}: exceeds maximum nesting depth {MAX_YAML_DEPTH}"
                    )
            elif isinstance(event, yaml.events.CollectionEndEvent):
                depth -= 1
        value = yaml.load(text, Loader=StrictSafeLoader)
    except RecursionError as exc:
        raise ValueError(f"{path}: YAML recursion limit exceeded") from exc
    except MemoryError as exc:
        raise ValueError(f"{path}: YAML resource limit exceeded") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a YAML object")
    return value


def _typed_equal(actual: Any, expected: Any) -> bool:
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return set(actual) == set(expected) and all(
            _typed_equal(actual[key], value) for key, value in expected.items()
        )
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(
            _typed_equal(actual_value, expected_value)
            for actual_value, expected_value in zip(actual, expected)
        )
    return actual == expected


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
    if type(contract.get("schema_version")) is not int or contract.get("schema_version") != 1:
        errors.append("contract schema_version must be integer 1")
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
                or any(type(surface) is not str for surface in surfaces)
                or len(surfaces) != len(set(surfaces))
                or any(surface not in DOC_PATHS for surface in surfaces)
            ):
                errors.append(f"decision rule {rule_id} has invalid surfaces")
    if not _typed_equal(rules, CANONICAL_RULES):
        errors.append("decision_rules must equal the closed canonical rule registry")

    metadata = contract.get("decision_surface_metadata")
    if not _typed_equal(metadata, CANONICAL_SURFACE_METADATA):
        errors.append("decision_surface_metadata must equal the closed typed surface registry")

    ast = contract.get("decision_surface_ast")
    if not isinstance(ast, dict) or set(ast) != set(CANONICAL_SURFACE_AST):
        errors.append("decision_surface_ast must cover exactly the four decision surfaces")
    else:
        for relative, expected_nodes in CANONICAL_SURFACE_AST.items():
            actual_nodes = ast.get(relative)
            if not isinstance(actual_nodes, list) or len(actual_nodes) != len(expected_nodes):
                errors.append(f"decision_surface_ast for {relative} has invalid clause count")
                continue
            for index, (actual, expected) in enumerate(zip(actual_nodes, expected_nodes)):
                expected_clause_id = expected["clause_id"]
                if not isinstance(actual, dict) or set(actual) != {"clause_id", "rule_id", "params"}:
                    errors.append(f"decision clause {expected_clause_id} must contain only clause_id, rule_id, and params")
                    continue
                if actual.get("clause_id") != expected_clause_id:
                    errors.append(f"decision_surface_ast for {relative} has invalid clause at index {index}")
                    continue
                if actual.get("rule_id") != expected["rule_id"]:
                    errors.append(f"decision clause {expected_clause_id} has invalid rule_id")
                if not _typed_equal(actual.get("params"), expected["params"]):
                    errors.append(f"decision clause {expected_clause_id} has invalid params")

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
            or (expected_type == "array" and type(value) is list)
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
    cells = values.get("evidence_cells")
    if type(cells) is list:
        seen: set[tuple[str, str, str]] = set()
        duplicate = False
        for index, cell in enumerate(cells):
            if not isinstance(cell, dict):
                errors.append(f"scenario {scenario_id} input evidence_cells[{index}] must be an object")
                continue
            if set(cell) != {"locale", "viewport", "theme"}:
                errors.append(
                    f"scenario {scenario_id} input evidence_cells[{index}] must contain only locale, viewport, and theme"
                )
                continue
            valid_cell = True
            for axis, allowed in (
                ("locale", {"EN", "RU"}),
                ("viewport", {"desktop", "mobile", "tablet"}),
                ("theme", {"dark", "light"}),
            ):
                value = cell.get(axis)
                if type(value) is not str or value not in allowed:
                    errors.append(
                        f"scenario {scenario_id} input evidence_cells[{index}].{axis} must be one of: "
                        + ", ".join(sorted(allowed))
                    )
                    valid_cell = False
            if valid_cell:
                identity = (cell["locale"], cell["viewport"], cell["theme"])
                if identity in seen:
                    duplicate = True
                seen.add(identity)
        if duplicate:
            errors.append(f"scenario {scenario_id} input evidence_cells contains duplicate cells")
    return errors


def _expected_value_errors(scenario_id: str, expected: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    expected_keys = EXPECTED_KEYS_BY_SCENARIO.get(scenario_id, set())
    unknown = sorted(set(expected) - expected_keys)
    missing = sorted(expected_keys - set(expected))
    if unknown:
        errors.append(f"scenario {scenario_id} expected has unknown outputs: {', '.join(unknown)}")
    if missing:
        errors.append(f"scenario {scenario_id} is missing expected outputs: {', '.join(missing)}")
    for key, value in expected.items():
        schema = EXPECTED_OUTPUT_SCHEMA.get(key)
        if schema is None:
            continue
        if value is None and schema.get("nullable") is True:
            continue
        expected_type = schema["type"]
        type_valid = (
            (expected_type == "boolean" and type(value) is bool)
            or (expected_type == "integer" and type(value) is int)
            or (expected_type == "string" and type(value) is str)
        )
        if not type_valid:
            suffix = " or null" if schema.get("nullable") is True else ""
            errors.append(f"scenario {scenario_id} expected {key} must be {expected_type}{suffix}")
            continue
        allowed = schema.get("enum")
        if allowed is not None and value not in allowed:
            errors.append(
                f"scenario {scenario_id} expected {key} must be one of: "
                + ", ".join(sorted(allowed))
            )
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if minimum is not None and value < minimum:
            errors.append(f"scenario {scenario_id} expected {key} must be >= {minimum}")
        if maximum is not None and value > maximum:
            errors.append(f"scenario {scenario_id} expected {key} must be <= {maximum}")
    return errors


def scenario_errors(corpus: dict[str, Any]) -> list[str]:
    """Validate that the forward corpus cannot silently omit a claimed output."""

    errors: list[str] = []
    allowed_root = {"schema_version", "scenarios"}
    unknown_root = sorted(str(key) for key in set(corpus) - allowed_root)
    missing_root = sorted(allowed_root - set(corpus))
    if unknown_root:
        errors.append(f"scenario corpus has unknown root keys: {', '.join(unknown_root)}")
    if missing_root:
        errors.append(f"scenario corpus is missing root keys: {', '.join(missing_root)}")
    scenarios = corpus.get("scenarios")
    if type(corpus.get("schema_version")) is not int or corpus.get("schema_version") != 1:
        errors.append("scenario corpus schema_version must be integer 1")
    if not isinstance(scenarios, list):
        return [*errors, "scenario corpus scenarios must be a list"]
    ids: list[str] = []
    for index, item in enumerate(scenarios):
        if isinstance(item, dict):
            scenario_id = item.get("id")
            if type(scenario_id) is str:
                ids.append(scenario_id)
            else:
                errors.append(f"scenario at index {index} id must be a string")
    if len(scenarios) != 8 or len(ids) != 8 or set(ids) != EXPECTED_SCENARIO_IDS:
        errors.append("scenario corpus must contain each of the exact eight scenario IDs once")
    if len(ids) != len(set(ids)):
        errors.append("scenario IDs must be unique")
    for index, scenario in enumerate(scenarios):
        if not isinstance(scenario, dict):
            errors.append(f"scenario at index {index} must be an object")
            continue
        raw_scenario_id = scenario.get("id")
        scenario_id = raw_scenario_id if type(raw_scenario_id) is str else f"index-{index}"
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
            errors.extend(_expected_value_errors(str(scenario_id), expected))
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


def _split_decision_surface(content: str) -> tuple[str, list[list[tuple[int, str]]]]:
    lines = content.splitlines()
    preamble: list[str] = []
    start = 0
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                preamble = lines[: index + 1]
                start = index + 1
                break
        else:
            return "\n".join(lines), []
    blocks: list[list[tuple[int, str]]] = []
    block: list[tuple[int, str]] = []
    for index, raw in enumerate(lines[start:], start=start + 1):
        if raw.strip():
            block.append((index, raw))
        elif block:
            blocks.append(block)
            block = []
    if block:
        blocks.append(block)
    return "\n".join(preamble), blocks


def _render_preamble(relative: str) -> str:
    metadata = CANONICAL_SURFACE_METADATA[relative]
    if metadata["kind"] == "reference":
        return ""
    descriptions = {
        "frontend-design-discovery": (
            "Design a research-backed pre-code packet for rendered customer-facing frontend work; "
            "excludes backend, implementation, and final acceptance."
        ),
        "designer-role-discovery": (
            "Frontend Design Lead who converts customer-visible intent into a research-backed "
            "pre-code design packet and Knowledge Contract-ready handoff."
        ),
    }
    if metadata["kind"] == "skill":
        return "\n".join(
            [
                "---",
                f"name: {metadata['identity']}",
                f"description: {descriptions[metadata['description_id']]}",
                "metadata:",
                f"  current_aal: {metadata['current_aal']}",
                f"  target_aal: {metadata['target_aal']}",
                "---",
            ]
        )
    return "\n".join(
        [
            "---",
            f"name: {metadata['identity']}",
            f"description: {descriptions[metadata['description_id']]}",
            f"model: {metadata['model']}",
            "metadata:",
            f"  model_tier: {metadata['model_tier']}",
            "---",
        ]
    )


def _render_clause(clause_id: str, params: dict[str, Any]) -> str:
    spec = CANONICAL_CLAUSE_SPECS[clause_id]
    if clause_id == "FD-SKILL-SEQUENCE-03":
        stage_text = {
            "reuse_inventory": (
                "Inventory reusable artifacts in the product, its design system, the Datarim\n"
                "   runtime, and the applicable knowledge graph. Record exact paths, revisions,\n"
                "   digests, lifecycle state, and reuse/modify/create/reject disposition."
            ),
            "external_research": (
                "Research the unresolved design questions with current primary standards,\n"
                "   official documentation, and strong maintained reference implementations.\n"
                "   Record URL, UTC access date, authority, applicability, selected use, and\n"
                "   rejected alternatives in `INSIGHTS-{TASK-ID}.md`."
            ),
            "seven_kind_gap_analysis": (
                "Analyze gaps across all seven managed kinds: `Role`, `Skill`, `Blueprint`,\n"
                "   `Constraint`, `SuccessCriterion`, `Policy`, and `CapabilityDescription`.\n"
                "   `Competency` is not a managed kind; express competency-shaped needs through\n"
                "   `CapabilityDescription`, `provides`, and pinned dependency relations."
            ),
            "reusable_artifact_creation_and_validation": (
                "Create and validate every missing reusable artifact. Run its schema,\n"
                "   frontmatter, lifecycle, provenance, relation, forward-scenario, and mutation\n"
                "   checks before any product implementation."
            ),
            "knowledge_contract_issuance": (
                "Issue the Knowledge Contract with immutable artifact revisions and digests,\n"
                "   pre-work timestamps, requirement bindings, and red-capable evidence.\n"
                "   Product code is forbidden until the contract is `MET`."
            ),
        }
        return "\n".join(
            f"{index}. {stage_text[stage]}" for index, stage in enumerate(params["stages"], start=1)
        )
    if clause_id == "FD-DESIGN-A11Y-02":
        floor = {"WCAG-2.2-AA": "WCAG 2.2 Level AA"}[params["accessibility_floor"]]
        return (
            f"{floor} is the minimum accessibility baseline unless a stricter\n"
            "project policy applies. When a requested treatment conflicts with contrast,\n"
            "keyboard, reflow, motion, or assistive-technology requirements, preserve the customer intent through an accessible alternative and record the constraint and\n"
            "rationale. Never silently implement a known failure."
        )
    if clause_id == "FD-HANDOFF-EVIDENCE-02":
        count_word = {12: "twelve"}[params["expected_cells"]]
        return (
            "For every affected painted surface, plan the full "
            f"{'/'.join(params['locales'])} x {'/'.join(params['viewports'])} x "
            f"{'/'.join(params['themes'])} matrix. That is {count_word} cells per surface class; "
            "any absent cell keeps the Knowledge Contract `NOT_MET` when the matrix is required."
        )
    text = spec["text"]
    if not isinstance(text, str):
        raise ValueError(f"decision clause {clause_id} has no deterministic renderer")
    return text


def _render_surface(relative: str) -> str:
    blocks: list[str] = []
    for node in CANONICAL_SURFACE_AST[relative]:
        rule = CANONICAL_RULES[node["rule_id"]]
        marker = (
            f"<!-- fd-rule: {node['rule_id']}; polarity: {rule['polarity']}; "
            f"semantics: {rule['semantics']} -->"
        )
        blocks.append(f"{marker}\n{_render_clause(node['clause_id'], node['params'])}")
    body = "\n\n".join(blocks)
    preamble = _render_preamble(relative)
    return f"{preamble}\n\n{body}\n" if preamble else f"{body}\n"


def documentation_errors(root: Path, contract: dict[str, Any]) -> list[str]:
    """Reject unbound prose and unsafe claims on every decision surface."""

    errors: list[str] = []
    expected_cells = (contract.get("evidence_matrix") or {}).get("expected_cells_per_surface")
    expected_digests = contract.get("decision_surface_sha256") or {}
    declared_rules = CANONICAL_RULES
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
        decoded = content.decode("utf-8")
        if decoded != _render_surface(relative):
            errors.append(f"{relative}: deterministic decision surface render mismatch")
        preamble, blocks = _split_decision_surface(decoded)
        if _render_preamble(relative) != preamble:
            errors.append(f"{relative}: decision surface preamble mismatch")

        observed_rule_ids: list[str] = []
        expected_nodes = CANONICAL_SURFACE_AST[relative]
        for block_index, block in enumerate(blocks):
            first_number, first_raw = block[0]
            location = f"{relative}:{first_number}"
            expected_node = expected_nodes[block_index] if block_index < len(expected_nodes) else None
            marker = RULE_MARKER_RE.fullmatch(first_raw)
            if marker is None:
                errors.append(f"{location}: untagged decision line")
                visible_lines = block
            else:
                rule_id = marker.group("rule_id")
                observed_rule_ids.append(rule_id)
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
                if expected_node is None or rule_id != expected_node["rule_id"]:
                    errors.append(f"{location}: decision rule {rule_id} is out of canonical order")
                if len(block) == 1:
                    errors.append(f"{location}: decision rule marker must bind visible content")
                    continue
                visible_lines = block[1:]
                actual_directive = "\n".join(raw for _, raw in visible_lines)
                if (
                    expected_node is None
                    or _render_clause(expected_node["clause_id"], expected_node["params"])
                    != actual_directive
                ):
                    errors.append(f"{location}: decision rule {rule_id} content mismatch")
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
        expected_order = [node["rule_id"] for node in expected_nodes]
        if observed_rule_ids != expected_order:
            errors.append(f"{relative}: decision surface rule order mismatch")
    if isinstance(declared_rules, dict):
        for rule_id in sorted(set(declared_rules) - used_rules):
            errors.append(f"decision rule {rule_id} is declared but unused")
    return errors


def evaluate(contract: dict[str, Any], scenario: dict[str, Any]) -> dict[str, Any]:
    values = scenario.get("input") or {}
    policies = contract["policies"]
    matrix = contract["evidence_matrix"]
    required_cells = matrix["expected_cells_per_surface"]
    evidence_cells = values.get("evidence_cells") or []
    cell_identities = {
        (cell["locale"], cell["viewport"], cell["theme"])
        for cell in evidence_cells
        if isinstance(cell, dict) and set(cell) == {"locale", "viewport", "theme"}
    }
    present_cells = len(evidence_cells)
    matrix_complete = cell_identities == EXPECTED_EVIDENCE_CELLS and present_cells == len(EXPECTED_EVIDENCE_CELLS)
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
    elif not matrix_complete:
        action = "complete_evidence_plan"
    else:
        action = "produce_design_packet"

    artifacts_valid = values.get("reusable_artifacts_valid") is True
    contract_met = binding_accepted and artifacts_valid and matrix_complete
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
    except (OSError, ValueError, yaml.YAMLError, UnicodeError, RecursionError, MemoryError) as exc:
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
