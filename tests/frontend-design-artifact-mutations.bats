#!/usr/bin/env bats

# TALO-0001 G1/G2 mutation proof. Each case damages one independent contract
# boundary in an isolated fixture and requires the corresponding forward test
# to turn RED. A passing mutant is a failure of this suite.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CONTRACT="$REPO/tests/frontend-design-artifacts.bats"
    MUTANT="$BATS_TEST_TMPDIR/mutant"
    mkdir -p "$MUTANT/skills" "$MUTANT/agents" "$MUTANT/config" "$MUTANT/templates" "$MUTANT/dev-tools" "$MUTANT/tests/fixtures"
    cp -R "$REPO/skills/frontend-design" "$MUTANT/skills/frontend-design"
    cp "$REPO/agents/designer.md" "$REPO/agents/researcher.md" "$MUTANT/agents/"
    cp "$REPO/config/roles.yaml" "$MUTANT/config/roles.yaml"
    cp "$REPO/templates/insights-template.md" "$REPO/templates/frontend-design-brief.md" "$MUTANT/templates/"
    cp "$REPO/dev-tools/evaluate-frontend-design.py" "$MUTANT/dev-tools/evaluate-frontend-design.py"
    cp "$REPO/tests/fixtures/frontend-design-scenarios.yaml" "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml"
}

mutate_text() {
    python3 - "$1" "$2" "$3" <<'PY'
from pathlib import Path
import sys

path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
if old not in text:
    raise SystemExit(f"mutation source not found: {old}")
path.write_text(text.replace(old, new, 1))
PY
}

append_text() {
    python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

path, addition = Path(sys.argv[1]), sys.argv[2]
path.write_text(path.read_text() + "\n" + addition + "\n")
PY
}

recompute_decision_surface_digests() {
    python3 - "$MUTANT" <<'PY'
from pathlib import Path
import hashlib
import sys
import yaml

root = Path(sys.argv[1])
contract_path = root / "skills/frontend-design/references/decision-contract.yaml"
contract = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
for relative in contract["decision_surface_sha256"]:
    contract["decision_surface_sha256"][relative] = hashlib.sha256(
        (root / relative).read_bytes()
    ).hexdigest()
contract_path.write_text(
    yaml.safe_dump(contract, sort_keys=False, allow_unicode=True),
    encoding="utf-8",
)
PY
}

assert_evaluator_red() {
    local expected="$1"
    run python3 "$MUTANT/dev-tools/evaluate-frontend-design.py" \
        --contract "$MUTANT/skills/frontend-design/references/decision-contract.yaml" \
        --scenarios "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        --docs-root "$MUTANT" \
        --check
    [ "$status" -ne 0 ] \
        && jq -e --arg expected "$expected" \
            '([.contract_errors[], .scenario_errors[], .documentation_errors[]] | map(contains($expected)) | any)' \
            <<<"$output" >/dev/null
}

@test "M1: explicit designer projection is load-bearing" {
    mutate_text "$MUTANT/config/roles.yaml" 'agent: "agents/designer.md"' 'agent: "agents/not-present.md"'
    run env FRONTEND_DESIGN_ROOT="$MUTANT" bats -f 'designer and researcher execution projections' "$CONTRACT"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"not ok"* ]]
}

@test "M2: designer ownership and acceptance boundary is load-bearing" {
    append_text "$MUTANT/agents/designer.md" 'The designer owns customer acceptance.'
    assert_evaluator_red 'designer is assigned acceptance authority'
}

@test "M3: backend non-trigger is load-bearing" {
    append_text "$MUTANT/skills/frontend-design/SKILL.md" 'Invoke this skill for backend-only work.'
    assert_evaluator_red 'unsafe backend-only invocation rule'
}

@test "M4: sparse-brief autonomous direction is load-bearing" {
    append_text "$MUTANT/skills/frontend-design/references/design-decisions.md" 'Pause for preliminary taste approval.'
    assert_evaluator_red 'preliminary taste approval pause contradicts policy'
}

@test "M5: existing-system reuse-first rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" 'replacement_default: false' 'replacement_default: true'
    assert_evaluator_red 'policy replacement_default must equal False'
}

@test "M6: accessible-alternative rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" 'accessibility_conflict_strategy: accessible_alternative' 'accessibility_conflict_strategy: implement_unchanged'
    assert_evaluator_red "policy accessibility_conflict_strategy must equal 'accessible_alternative'"
}

@test "M7: real Russian stress-copy rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" 'ru_overflow_strategy: redesign_layout' 'ru_overflow_strategy: shrink_text'
    assert_evaluator_red "policy ru_overflow_strategy must equal 'redesign_layout'"
}

@test "M8: complete twelve-cell evidence rule is load-bearing" {
    append_text "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'A ten-cell matrix is sufficient.'
    assert_evaluator_red 'unsafe 10-cell sufficiency rule'
}

@test "M9: post-hoc rejection is load-bearing" {
    append_text "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'Allow post-hoc binding.'
    assert_evaluator_red 'post-hoc binding is allowed'
}

@test "M10: product-code Knowledge Contract gate is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" 'implementation_requires_knowledge_contract_state: MET' 'implementation_requires_knowledge_contract_state: OPTIONAL'
    assert_evaluator_red 'product implementation must require Knowledge Contract MET'
}

@test "M11: canonical CapabilityDescription boundary is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" '  - CapabilityDescription' '  - Competency'
    assert_evaluator_red 'managed_kinds must be the exact canonical seven-kind sequence'
}

@test "M12: Unbound delivery rejection is load-bearing" {
    append_text "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'Allow Unbound delivery.'
    assert_evaluator_red 'Unbound delivery is allowed'
}

@test "M13: resealed backend synonym fails the closed rule-ID grammar" {
    append_text "$MUTANT/skills/frontend-design/SKILL.md" 'Backend-only changes activate this capability.'
    recompute_decision_surface_digests
    assert_evaluator_red 'untagged decision line'
}

@test "M14: resealed proof-threshold synonym fails the closed rule-ID grammar" {
    append_text "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'Ten captures meet the complete proof threshold.'
    recompute_decision_surface_digests
    assert_evaluator_red 'untagged decision line'
}

@test "M15: unknown structured override fails closed" {
    append_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" $'documentation_override:\n  backend_only_invokes: true'
    assert_evaluator_red 'unknown contract keys are forbidden: documentation_override'
}

@test "M16: a scenario cannot silently omit a claimed output" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" $'      implementation_allowed: true\n      product_code_emitted: false' $'      implementation_allowed: true'
    assert_evaluator_red 'scenario positive_site_wave is missing expected outputs: product_code_emitted'
}

@test "M17: unknown brief-detail vocabulary fails closed" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" 'brief_detail: complete' 'brief_detail: ultraviolet'
    assert_evaluator_red "scenario positive_site_wave input brief_detail must be one of: complete, sparse"
}

@test "M18: scenario input types fail closed instead of coercing strings" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" 'rendered_customer_surface: true' 'rendered_customer_surface: "true"'
    assert_evaluator_red 'scenario positive_site_wave input rendered_customer_surface must be boolean'
}
