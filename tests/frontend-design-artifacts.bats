#!/usr/bin/env bats

# TALO-0001 G1/G2: executable contract for the reusable frontend-design
# capability. These are prose-contract tests by design: the behavior lives in
# an agent and skill, so each scenario pins one independently removable clause.

setup() {
    ROOT="${FRONTEND_DESIGN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
    SKILL="$ROOT/skills/frontend-design/SKILL.md"
    DECISIONS="$ROOT/skills/frontend-design/references/design-decisions.md"
    HANDOFF="$ROOT/skills/frontend-design/references/handoff-and-evidence.md"
    DECISION_CONTRACT="$ROOT/skills/frontend-design/references/decision-contract.yaml"
    DESIGNER="$ROOT/agents/designer.md"
    RESEARCHER="$ROOT/agents/researcher.md"
    ROLES="$ROOT/config/roles.yaml"
    INSIGHTS="$ROOT/templates/insights-template.md"
    BRIEF="$ROOT/templates/frontend-design-brief.md"
    EVALUATOR="$ROOT/dev-tools/evaluate-frontend-design.py"
    SCENARIOS="$ROOT/tests/fixtures/frontend-design-scenarios.yaml"
}

evaluate_scenario() {
    run python3 "$EVALUATOR" \
        --contract "$DECISION_CONTRACT" \
        --scenarios "$SCENARIOS" \
        --docs-root "$ROOT" \
        --scenario "$1"
}

@test "G1: designer and researcher execution projections are registered" {
    [ -f "$DESIGNER" ] \
        && [ -f "$RESEARCHER" ] \
        && yq -e '.roles[] | select(.id == "designer") | .agent == "agents/designer.md"' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "designer") | .domain_skills[] == "skills/frontend-design"' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "designer") | ((.allowed_paths | contains(["skills/**", "agents/**", "templates/**", "config/**"])) and (.forbidden_actions | contains(["product-code-write"])))' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "researcher") | .agent == "agents/researcher.md"' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "researcher") | .domain_skills[] == "skills/research-workflow"' "$ROLES" >/dev/null
}

@test "G1: designer owns the pre-code packet but never customer acceptance" {
    evaluate_scenario positive_site_wave
    [ "$status" -eq 0 ] \
        && jq -e '.design_owner == "designer" and .acceptance_owner == "operator" and .product_code_emitted == false' <<<"$output" >/dev/null
}

@test "G1: shipped agent frontmatter and role registry validate" {
    "$ROOT/dev-tools/check-agent-frontmatter.sh" --root "$ROOT" \
        && "$ROOT/dev-tools/check-role-registry.sh" --root "$ROOT" --file "$ROLES"
}

@test "G2: frontend-design is a progressively disclosed skill" {
    [ -f "$SKILL" ] \
        && [ -f "$DECISIONS" ] \
        && [ -f "$HANDOFF" ] \
        && [ -f "$DECISION_CONTRACT" ] \
        && grep -qF 'Read `references/design-decisions.md`' "$SKILL" \
        && grep -qF 'Read `references/handoff-and-evidence.md`' "$SKILL"
}

@test "G2: frontend-design discovery description fits the 155-character budget" {
    description="$(awk -F': ' '/^description:/{sub(/^description: /, ""); print; exit}' "$SKILL")"
    [ -n "$description" ] \
        && [ "${#description}" -le 155 ]
}

@test "G2: independent evaluator validates all eight forward scenarios" {
    run python3 "$EVALUATOR" --contract "$DECISION_CONTRACT" --scenarios "$SCENARIOS" --docs-root "$ROOT" --check
    [ "$status" -eq 0 ] \
        && jq -e '.checked == 8 and .failures == 0 and .contract_valid == true and .docs_consistent == true' <<<"$output" >/dev/null
}

@test "G2: decision surfaces are digest-pinned and structured rules fail closed" {
    run python3 "$EVALUATOR" --contract "$DECISION_CONTRACT" --scenarios "$SCENARIOS" --docs-root "$ROOT" --check
    [ "$status" -eq 0 ] \
        && yq -e '.decision_surface_sha256 | length == 4' "$DECISION_CONTRACT" >/dev/null \
        && jq -e '.docs_consistent == true and .contract_valid == true' <<<"$output" >/dev/null
}

@test "scenario positive site wave: complete pre-code packet reaches implementation handoff" {
    evaluate_scenario positive_site_wave
    [ "$status" -eq 0 ] \
        && jq -e '.invoke_skill == true and .design_action == "produce_design_packet" and .knowledge_contract_state == "MET" and .implementation_allowed == true and .product_code_emitted == false' <<<"$output" >/dev/null
}

@test "scenario sparse brief: produce a defensible first direction without taste approval pause" {
    evaluate_scenario sparse_visual_brief
    [ "$status" -eq 0 ] \
        && jq -e '.invoke_skill == true and .design_action == "produce_first_direction" and .approval_pause == false and .implementation_allowed == false' <<<"$output" >/dev/null
}

@test "scenario existing system: reuse and extend before proposing replacement" {
    evaluate_scenario existing_design_system
    [ "$status" -eq 0 ] \
        && jq -e '.design_action == "reuse_and_extend" and .replacement_default == false and .product_code_emitted == false' <<<"$output" >/dev/null
}

@test "scenario accessibility conflict: preserve intent through a conforming alternative" {
    evaluate_scenario accessibility_conflict
    [ "$status" -eq 0 ] \
        && jq -e '.design_action == "accessible_alternative" and .accessibility_floor == "WCAG-2.2-AA" and .product_code_emitted == false' <<<"$output" >/dev/null
}

@test "scenario long Russian: stress real RU copy and redesign instead of shrinking" {
    evaluate_scenario long_ru_overflow
    [ "$status" -eq 0 ] \
        && jq -e '.design_action == "redesign_layout" and .shrink_critical_text == false and .product_code_emitted == false' <<<"$output" >/dev/null
}

@test "scenario missing matrix: any absent locale viewport or theme keeps KC not met" {
    evaluate_scenario missing_matrix_cell
    [ "$status" -eq 0 ] \
        && jq -e '.design_action == "complete_evidence_plan" and .evidence_cells_required == 12 and .evidence_cells_present == 11 and .knowledge_contract_state == "NOT_MET" and .implementation_allowed == false' <<<"$output" >/dev/null
}

@test "scenario attribution: post-hoc and Unbound selections are rejected" {
    evaluate_scenario post_hoc_unbound
    [ "$status" -eq 0 ] \
        && jq -e '.design_action == "reject_binding" and .binding_accepted == false and .knowledge_contract_state == "NOT_MET" and .implementation_allowed == false' <<<"$output" >/dev/null
}

@test "scenario backend-only: frontend-design is not invoked" {
    evaluate_scenario backend_only_migration
    [ "$status" -eq 0 ] \
        && jq -e '.invoke_skill == false and .design_action == "route_without_frontend_design" and .knowledge_contract_state == "NOT_APPLICABLE" and .implementation_allowed == null' <<<"$output" >/dev/null
}

@test "G2: canonical contract has seven kinds and pre-code MET gate" {
    run python3 "$EVALUATOR" --contract "$DECISION_CONTRACT" --scenarios "$SCENARIOS" --docs-root "$ROOT" --describe-contract
    [ "$status" -eq 0 ] \
        && jq -e '.managed_kinds == ["Role","Skill","Blueprint","Constraint","SuccessCriterion","Policy","CapabilityDescription"] and .implementation_requires == "MET" and .post_hoc_allowed == false and .unbound_delivery_allowed == false' <<<"$output" >/dev/null
}

@test "G2: research template records replayable provenance and decisions" {
    grep -qF '| URL | Accessed (UTC) | Authority | Applicability | Selected use | Rejected alternative |' "$INSIGHTS" \
        && grep -qF '## Reuse-First Inventory' "$INSIGHTS" \
        && grep -qF '## Knowledge Artifact Gap Analysis' "$INSIGHTS"
}

@test "G2: reusable brief carries ownership hierarchy variants and implementation gate" {
    grep -qF 'Owner: designer' "$BRIEF" \
        && grep -qF '## Content hierarchy and task flow' "$BRIEF" \
        && grep -qF '## Alternatives and selected direction' "$BRIEF" \
        && grep -qF '## Knowledge Contract gate' "$BRIEF" \
        && grep -qF 'Implementation may start only when the issued contract is `MET`.' "$BRIEF"
}

@test "G1/G2: public inventories match the shipped designer skill and template counts" {
    agent_files=("$ROOT"/agents/*.md)
    skill_files=("$ROOT"/skills/*/SKILL.md)
    template_files=("$ROOT"/templates/*.md)
    [ "${#agent_files[@]}" -eq 20 ] \
        && [ "${#skill_files[@]}" -eq 74 ] \
        && [ "${#template_files[@]}" -eq 26 ] \
        && grep -qF '| designer | Frontend Design Lead |' "$ROOT/documentation/reference/agents.md" \
        && grep -qF '| frontend-design | Reference |' "$ROOT/documentation/reference/skills.md" \
        && grep -qF '(74 skills' "$ROOT/CLAUDE.md" \
        && grep -qF 'all 74 skills' "$ROOT/README.md" \
        && grep -qF 'templates/         # Task and document templates (26 templates)' "$ROOT/README.md"
}
