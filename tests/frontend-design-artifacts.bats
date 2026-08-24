#!/usr/bin/env bats

# TALO-0001 G1/G2: executable contract for the reusable frontend-design
# capability. These are prose-contract tests by design: the behavior lives in
# an agent and skill, so each scenario pins one independently removable clause.

setup() {
    ROOT="${FRONTEND_DESIGN_ROOT:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
    SKILL="$ROOT/skills/frontend-design/SKILL.md"
    DECISIONS="$ROOT/skills/frontend-design/references/design-decisions.md"
    HANDOFF="$ROOT/skills/frontend-design/references/handoff-and-evidence.md"
    DESIGNER="$ROOT/agents/designer.md"
    RESEARCHER="$ROOT/agents/researcher.md"
    ROLES="$ROOT/config/roles.yaml"
    INSIGHTS="$ROOT/templates/insights-template.md"
    BRIEF="$ROOT/templates/frontend-design-brief.md"
}

@test "G1: designer and researcher execution projections are registered" {
    [ -f "$DESIGNER" ] \
        && [ -f "$RESEARCHER" ] \
        && yq -e '.roles[] | select(.id == "designer") | .agent == "agents/designer.md"' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "designer") | .domain_skills[] == "skills/frontend-design"' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "researcher") | .agent == "agents/researcher.md"' "$ROLES" >/dev/null \
        && yq -e '.roles[] | select(.id == "researcher") | .domain_skills[] == "skills/research-workflow"' "$ROLES" >/dev/null
}

@test "G1: designer owns the pre-code packet but never customer acceptance" {
    grep -qF 'owns the pre-code design packet' "$DESIGNER" \
        && grep -qF 'MUST NOT claim customer or operator acceptance' "$DESIGNER"
}

@test "G1: shipped agent frontmatter and role registry validate" {
    "$ROOT/dev-tools/check-agent-frontmatter.sh" --root "$ROOT" \
        && "$ROOT/dev-tools/check-role-registry.sh" --root "$ROOT" --file "$ROLES"
}

@test "G2: frontend-design is a progressively disclosed skill" {
    [ -f "$SKILL" ] \
        && [ -f "$DECISIONS" ] \
        && [ -f "$HANDOFF" ] \
        && grep -qF 'Read `references/design-decisions.md`' "$SKILL" \
        && grep -qF 'Read `references/handoff-and-evidence.md`' "$SKILL"
}

@test "G2: frontend routing requires a rendered customer-facing surface" {
    grep -qF 'rendered customer-facing surface' "$SKILL"
}

@test "scenario backend-only: frontend-design is not invoked" {
    grep -qF 'For backend-only, data-only, infrastructure-only, or non-rendered work, do not invoke this skill.' "$SKILL"
}

@test "scenario sparse brief: produce a defensible first direction without taste approval pause" {
    grep -qF 'Do not pause for preliminary taste approval' "$DECISIONS" \
        && grep -qF 'defensible first direction' "$DECISIONS"
}

@test "scenario existing system: reuse and extend before proposing replacement" {
    grep -qF 'Reuse or extend compatible tokens, components, and page patterns before proposing replacements.' "$DECISIONS"
}

@test "scenario accessibility conflict: preserve intent through a conforming alternative" {
    grep -qF 'preserve the customer intent through an accessible alternative' "$DECISIONS" \
        && grep -qF 'WCAG 2.2 Level AA' "$DECISIONS"
}

@test "scenario long Russian: stress real RU copy and redesign instead of shrinking" {
    grep -qF 'real RU stress copy' "$DECISIONS" \
        && grep -qF 'redesign the container or flow; do not shrink critical text below the applicable policy' "$DECISIONS"
}

@test "scenario missing matrix: any absent locale viewport or theme keeps KC not met" {
    grep -qF 'RU/EN x desktop/tablet/mobile x light/dark' "$HANDOFF" \
        && grep -qF 'any absent cell keeps the Knowledge Contract `NOT_MET`' "$HANDOFF"
}

@test "scenario attribution: post-hoc and Unbound selections are rejected" {
    grep -qF 'Reject post-hoc attribution' "$HANDOFF" \
        && grep -qF '`Gap` or `Unbound`' "$HANDOFF"
}

@test "G2: workflow orders reuse research gaps artifacts and KC before product code" {
    grep -qF '1. Inventory reusable artifacts' "$SKILL" \
        && grep -qF '2. Research the unresolved design questions' "$SKILL" \
        && grep -qF '3. Analyze gaps across all seven managed kinds' "$SKILL" \
        && grep -qF '4. Create and validate every missing reusable artifact' "$SKILL" \
        && grep -qF '5. Issue the Knowledge Contract' "$SKILL" \
        && grep -qF 'Product code is forbidden until the contract is `MET`.' "$SKILL"
}

@test "G2: canonical kinds include CapabilityDescription and exclude Competency" {
    grep -qF 'CapabilityDescription' "$SKILL" \
        && grep -qF '`Competency` is not a managed kind' "$SKILL"
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
