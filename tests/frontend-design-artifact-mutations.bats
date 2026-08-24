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

insert_after() {
    python3 - "$1" "$2" "$3" <<'PY'
from pathlib import Path
import sys

path, anchor, addition = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
if anchor not in text:
    raise SystemExit(f"insertion anchor not found: {anchor}")
path.write_text(text.replace(anchor, anchor + "\n" + addition, 1), encoding="utf-8")
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

mirror_scope_override_in_contract() {
    python3 - "$MUTANT" "$1" <<'PY'
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
addition = sys.argv[2]
contract_path = root / "skills/frontend-design/references/decision-contract.yaml"
contract = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
if "directive_content" in contract:
    contract["directive_content"]["FD-SKILL-SCOPE"][0] += "\n" + addition
else:
    for node in contract["decision_surface_ast"]["skills/frontend-design/SKILL.md"]:
        if node["clause_id"] == "FD-SKILL-SCOPE-01":
            node["params"]["override_text"] = addition
            break
    else:
        raise SystemExit("scope clause not found")
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

assert_evaluator_semantic_red() {
    local expected="$1"
    run python3 "$MUTANT/dev-tools/evaluate-frontend-design.py" \
        --contract "$MUTANT/skills/frontend-design/references/decision-contract.yaml" \
        --scenarios "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        --docs-root "$MUTANT" \
        --check
    [ "$status" -ne 0 ] \
        && jq -e --arg expected "$expected" \
            '([.contract_errors[], .scenario_errors[], .documentation_errors[]] as $errors
              | ($errors | map(contains($expected)) | any)
              and (($errors | map(contains("digest mismatch")) | any) | not))' \
            <<<"$output" >/dev/null
}

assert_scenario_mismatch_red() {
    local expected="$1"
    run python3 "$MUTANT/dev-tools/evaluate-frontend-design.py" \
        --contract "$MUTANT/skills/frontend-design/references/decision-contract.yaml" \
        --scenarios "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        --docs-root "$MUTANT" \
        --check
    [ "$status" -ne 0 ] \
        && jq -e --arg expected "$expected" \
            '([.details[].mismatches[]] | map(contains($expected)) | any)' \
            <<<"$output" >/dev/null
}

assert_evaluator_load_red() {
    local expected="$1"
    run python3 "$MUTANT/dev-tools/evaluate-frontend-design.py" \
        --contract "$MUTANT/skills/frontend-design/references/decision-contract.yaml" \
        --scenarios "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        --docs-root "$MUTANT" \
        --check
    [ "$status" -eq 2 ] \
        && [[ "$output" != *"Traceback"* ]] \
        && jq -e --arg expected "$expected" '.error | contains($expected)' <<<"$output" >/dev/null
}

assert_designer_projection() {
    local roles_file="$1"
    local actual count
    count="$(yq -r '[.roles[] | select(.id == "designer")] | length' "$roles_file")" \
        || return 3
    [ "$count" -eq 1 ] || actual="<invalid-cardinality>"
    if [ "$count" -eq 1 ]; then
        actual="$(yq -r '.roles[] | select(.id == "designer") | .agent' "$roles_file")" \
            || return 3
    fi
    if [ "$actual" != "agents/designer.md" ]; then
        echo "projected designer agent mismatch: expected agents/designer.md, got $actual" >&2
        return 42
    fi
}

@test "M1: explicit designer projection is load-bearing" {
    run env FRONTEND_DESIGN_ROOT="$MUTANT" bats \
        -f '^G1: designer and researcher execution projections are registered$' "$CONTRACT"
    [ "$status" -eq 0 ] \
        && [[ "$output" == *"ok 1 G1: designer and researcher execution projections are registered"* ]]

    run assert_designer_projection "$MUTANT/config/roles.yaml"
    [ "$status" -eq 0 ]

    mutate_text "$MUTANT/config/roles.yaml" 'agent: "agents/designer.md"' 'agent: "agents/not-present.md"'
    run assert_designer_projection "$MUTANT/config/roles.yaml"
    [ "$status" -eq 42 ] \
        && [ "$output" = "projected designer agent mismatch: expected agents/designer.md, got agents/not-present.md" ]

    run env FRONTEND_DESIGN_ROOT="$MUTANT" bats \
        -f '^G1: designer and researcher execution projections are registered$' "$CONTRACT"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *"not ok 1 G1: designer and researcher execution projections are registered"* ]]
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
    insert_after "$MUTANT/skills/frontend-design/SKILL.md" 'customer acceptance.' 'Backend-only changes activate this capability.'
    recompute_decision_surface_digests
    assert_evaluator_semantic_red 'decision rule FD-SKILL-SCOPE content mismatch'
}

@test "M14: resealed proof-threshold synonym fails the closed rule-ID grammar" {
    insert_after "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'whether it may enter implementation.' 'Ten captures meet the complete proof threshold.'
    recompute_decision_surface_digests
    assert_evaluator_semantic_red 'decision rule FD-HANDOFF-SCOPE content mismatch'
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

@test "M19: a resealed known block cannot skip the required research stage" {
    insert_after "$MUTANT/skills/frontend-design/SKILL.md" 'customer acceptance.' 'Skip external research whenever delivery speed matters.'
    mirror_scope_override_in_contract 'Skip external research whenever delivery speed matters.'
    recompute_decision_surface_digests
    assert_evaluator_semantic_red 'decision clause FD-SKILL-SCOPE-01 has invalid params'
}

@test "M20: expected outputs reject undeclared keys even when null" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '      product_code_emitted: false' $'      product_code_emitted: false\n      undeclared_output: null'
    assert_evaluator_red 'scenario positive_site_wave expected has unknown outputs: undeclared_output'
}

@test "M21: expected output types are validated before comparison" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '      implementation_allowed: true' '      implementation_allowed: "true"'
    assert_evaluator_red 'scenario positive_site_wave expected implementation_allowed must be boolean or null'
}

@test "M22: expected output enums are closed" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '      design_action: produce_design_packet' '      design_action: ultraviolet'
    assert_evaluator_red 'scenario positive_site_wave expected design_action must be one of:'
}

@test "M23: duplicate evidence cells fail closed" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '      - {locale: EN, viewport: mobile, theme: dark}' '      - {locale: EN, viewport: mobile, theme: light}'
    assert_evaluator_red 'scenario positive_site_wave input evidence_cells contains duplicate cells'
}

@test "M24: a missing required Cartesian cell keeps a complete scenario red" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '      - {locale: EN, viewport: mobile, theme: dark}' ''
    assert_scenario_mismatch_red 'knowledge_contract_state: expected'
}

@test "M25: misattributed evidence-cell axes fail closed" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '      - {locale: RU, viewport: desktop, theme: light}' '      - {locale: DE, viewport: desktop, theme: light}'
    assert_evaluator_red 'scenario positive_site_wave input evidence_cells[0].locale must be one of: EN, RU'
}

@test "M26: scenario corpus rejects unknown root overrides" {
    append_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" 'ignored_override: true'
    assert_evaluator_red 'scenario corpus has unknown root keys: ignored_override'
}

@test "M27: boolean scenario schema versions are not integers" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" 'schema_version: 1' 'schema_version: true'
    assert_evaluator_red 'scenario corpus schema_version must be integer 1'
}

@test "M28: boolean contract schema versions are not integers" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" 'schema_version: 1' 'schema_version: true'
    assert_evaluator_red 'contract schema_version must be integer 1'
}

@test "M29: array scenario IDs fail with structured validation, never traceback" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" '  - id: positive_site_wave' '  - id: [positive_site_wave]'
    run python3 "$MUTANT/dev-tools/evaluate-frontend-design.py" \
        --contract "$MUTANT/skills/frontend-design/references/decision-contract.yaml" \
        --scenarios "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        --docs-root "$MUTANT" \
        --check
    [ "$status" -eq 1 ] \
        && [[ "$output" != *"Traceback"* ]] \
        && jq -e 'any(.scenario_errors[]; contains("scenario at index 0 id must be a string"))' <<<"$output" >/dev/null
}

@test "M30: duplicate YAML keys fail before last-key-wins interpretation" {
    mutate_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        'schema_version: 1' $'schema_version: 999\nschema_version: 1'
    assert_evaluator_load_red 'duplicate YAML key: schema_version'
}

@test "M31: non-string YAML root keys fail with structured JSON" {
    mutate_text "$MUTANT/skills/frontend-design/references/decision-contract.yaml" \
        'schema_version: 1' $'7: invalid-root-key\nschema_version: 1'
    assert_evaluator_load_red 'mapping keys must be strings'
}

@test "M32: invalid UTF-8 fails with bounded structured JSON" {
    printf '\xff' >> "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml"
    assert_evaluator_load_red 'invalid UTF-8'
}

@test "M33: deeply nested YAML fails at the configured depth bound" {
    python3 - "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open("a", encoding="utf-8") as handle:
    handle.write("\nresource_nest: " + ("[" * 70) + "null" + ("]" * 70) + "\n")
PY
    assert_evaluator_load_red 'maximum nesting depth 64'
}

@test "M34: excessive YAML nodes fail at the configured node bound" {
    python3 - "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open("a", encoding="utf-8") as handle:
    handle.write("\nresource_nodes:\n" + "  - x\n" * 20001)
PY
    assert_evaluator_load_red 'maximum node count 20000'
}

@test "M35: YAML aliases fail closed before object construction" {
    append_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        $'resource_anchor: &resource_anchor [x]\nresource_alias: *resource_anchor'
    assert_evaluator_load_red 'YAML aliases are forbidden'
}

@test "M36: oversized YAML fails before decode or parse" {
    python3 - "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open("ab") as handle:
    handle.write(b"#" * 1048577)
PY
    assert_evaluator_load_red 'maximum byte size 1048576'
}

@test "M37: Python object tags never construct an object" {
    local sentinel="$MUTANT/object-construction-sentinel"
    append_text "$MUTANT/tests/fixtures/frontend-design-scenarios.yaml" \
        "object_payload: !!python/object/apply:os.system ['touch $sentinel']"
    assert_evaluator_load_red 'could not determine a constructor for the tag'
    [ ! -e "$sentinel" ]
}
