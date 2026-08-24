#!/usr/bin/env bats

# TALO-0001 G1/G2 mutation proof. Each case damages one independent contract
# boundary in an isolated fixture and requires the corresponding forward test
# to turn RED. A passing mutant is a failure of this suite.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CONTRACT="$REPO/tests/frontend-design-artifacts.bats"
    MUTANT="$BATS_TEST_TMPDIR/mutant"
    mkdir -p "$MUTANT/skills" "$MUTANT/agents" "$MUTANT/config" "$MUTANT/templates"
    cp -R "$REPO/skills/frontend-design" "$MUTANT/skills/frontend-design"
    cp "$REPO/agents/designer.md" "$REPO/agents/researcher.md" "$MUTANT/agents/"
    cp "$REPO/config/roles.yaml" "$MUTANT/config/roles.yaml"
    cp "$REPO/templates/insights-template.md" "$REPO/templates/frontend-design-brief.md" "$MUTANT/templates/"
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

assert_named_red() {
    local pattern="$1"
    run env FRONTEND_DESIGN_ROOT="$MUTANT" bats -f "$pattern" "$CONTRACT"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"not ok"* ]]
}

@test "M1: explicit designer projection is load-bearing" {
    mutate_text "$MUTANT/config/roles.yaml" 'agent: "agents/designer.md"' 'agent: "agents/not-present.md"'
    assert_named_red 'designer and researcher execution projections'
}

@test "M2: designer ownership and acceptance boundary is load-bearing" {
    mutate_text "$MUTANT/agents/designer.md" 'The designer owns the pre-code design packet' 'The developer may draft the design packet'
    assert_named_red 'designer owns the pre-code packet'
}

@test "M3: backend non-trigger is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/SKILL.md" 'For backend-only, data-only, infrastructure-only, or non-rendered work, do not invoke this skill.' 'Invoke this skill for every task.'
    assert_named_red 'backend-only'
}

@test "M4: sparse-brief autonomous direction is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/design-decisions.md" 'Do not pause for preliminary taste approval' 'Pause for preliminary taste approval'
    assert_named_red 'sparse brief'
}

@test "M5: existing-system reuse-first rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/design-decisions.md" 'Reuse or extend compatible tokens, components, and page patterns before proposing replacements.' 'Replace existing tokens and components by default.'
    assert_named_red 'existing system'
}

@test "M6: accessible-alternative rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/design-decisions.md" 'preserve the customer intent through an accessible alternative' 'implement the requested treatment unchanged'
    assert_named_red 'accessibility conflict'
}

@test "M7: real Russian stress-copy rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/design-decisions.md" 'real RU stress copy' 'translated copy later'
    assert_named_red 'long Russian'
}

@test "M8: complete twelve-cell evidence rule is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'RU/EN x desktop/tablet/mobile x light/dark' 'RU/EN x desktop/mobile x light/dark'
    assert_named_red 'missing matrix'
}

@test "M9: post-hoc rejection is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/references/handoff-and-evidence.md" 'Reject post-hoc attribution' 'Allow post-hoc attribution'
    assert_named_red 'scenario attribution'
}

@test "M10: product-code Knowledge Contract gate is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/SKILL.md" 'Product code is forbidden until the contract is `MET`.' 'Product code may start while the contract is incomplete.'
    assert_named_red 'workflow orders reuse research gaps artifacts and KC'
}

@test "M11: canonical CapabilityDescription boundary is load-bearing" {
    mutate_text "$MUTANT/skills/frontend-design/SKILL.md" '`Competency` is not a managed kind' '`Competency` is a managed kind'
    assert_named_red 'canonical kinds include CapabilityDescription'
}
