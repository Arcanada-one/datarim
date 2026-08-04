#!/usr/bin/env bats
#
# /dr-init "License auto-sync" (governance-artefacts step) regression guard.
#
# Stage-rule contract: commands/dr-init.md MUST keep the README license
# auto-sync bullet — after the operator license decision, the scaffolded
# README "License" section's TBD placeholder is replaced with the canonical
# render matched against the project manifest's license field (SPDX
# expression, single or dual), idempotently and never overwriting an
# operator-set value.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_INIT="$REPO_ROOT/commands/dr-init.md"

# Extract the bullet block: from the License auto-sync heading to the next
# 4-space-indent sibling bullet or next step heading.
bullet_block() {
    awk '/^    - \*\*License auto-sync\*\*/ {flag=1; print; next}
         flag && (/^    - \*\*/ || /^[0-9]/) {exit}
         flag {print}' "$DR_INIT"
}

@test "L1: dr-init.md contains the License auto-sync bullet" {
    [ -f "$DR_INIT" ]
    run grep -c 'License auto-sync' "$DR_INIT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "L2: bullet replaces the TBD placeholder with a canonical render" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *'"TBD" placeholder'* ]]
    [[ "$block" == *"canonical render"* ]]
}

@test "L3: render is matched against the project manifest license field (SPDX)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"Match the render against the project manifest"* ]]
    [[ "$block" == *"SPDX expression"* ]]
    [[ "$block" == *"manifest is the source of truth"* ]]
}

@test "L4: dual-license (SPDX OR expression) render is specified" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *'SPDX `OR` expression'* ]]
}

@test "L5: manifest examples are fenced as example-only (stack-agnostic surface)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"<!-- gate:example-only -->"* ]]
    [[ "$block" == *"<!-- /gate:example-only -->"* ]]
}

@test "L6: sync stays idempotent — never overwrite an operator-set value" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"never overwrite an operator-set value"* ]]
}

@test "L7: dr-init.md passes the stack-agnostic gate after the addition" {
    run bash "$REPO_ROOT/scripts/stack-agnostic-gate.sh" "$DR_INIT"
    [ "$status" -eq 0 ]
}
