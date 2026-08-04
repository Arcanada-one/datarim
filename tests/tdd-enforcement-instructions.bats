#!/usr/bin/env bats
# tdd-enforcement-instructions.bats — instruction-surface contract for the
# TDD enforcement toggle: canonical surfaces resolve state through the one
# workspace resolver and retain the mandatory-tests quality floor.

ROOT="$BATS_TEST_DIRNAME/.."

@test "I1 tdd-discipline skill references the canonical resolver" {
    grep -q "tdd-enforcement-state.sh" "$ROOT/skills/testing/tdd-discipline.md"
}

@test "I2 tdd-discipline skill documents both states with required as fail-safe" {
    grep -q '`required`' "$ROOT/skills/testing/tdd-discipline.md"
    grep -q '`optional`' "$ROOT/skills/testing/tdd-discipline.md"
    grep -qi "fail-safe" "$ROOT/skills/testing/tdd-discipline.md"
}

@test "I3 optional mode retains the mandatory-tests floor" {
    grep -qi "remain mandatory" "$ROOT/skills/testing/tdd-discipline.md"
    grep -qi "ordering only, never test existence" "$ROOT/skills/testing/tdd-discipline.md"
}

@test "I4 dr-do command references the canonical resolver" {
    grep -q "tdd-enforcement-state.sh" "$ROOT/commands/dr-do.md"
}

@test "I5 developer agent references the canonical resolver" {
    grep -q "tdd-enforcement-state.sh" "$ROOT/agents/developer.md"
}

@test "I6 dr-plugin command documents the default-plugin lifecycle" {
    grep -q "tdd-enforcement" "$ROOT/commands/dr-plugin.md"
    grep -q "Disabled Defaults" "$ROOT/commands/dr-plugin.md"
}

@test "I7 manifest template documents the Disabled Defaults section" {
    grep -q "Disabled Defaults" "$ROOT/templates/enabled-plugins.md.template"
}

@test "I8 plugin README exists and keeps the quality floor explicit" {
    [ -f "$ROOT/plugins/tdd-enforcement/README.md" ]
    grep -qi "remain mandatory" "$ROOT/plugins/tdd-enforcement/README.md"
}

@test "I9 how-to documentation exists" {
    [ -f "$ROOT/documentation/how-to/tdd-enforcement-plugin.md" ]
    grep -q "tdd-enforcement-state.sh" "$ROOT/documentation/how-to/tdd-enforcement-plugin.md"
}

@test "I10 no task identifiers leak into the shipped toggle surfaces" {
    run grep -nE '\b(TUNE|DATA)-[0-9]{4}\b' \
        "$ROOT/plugins/tdd-enforcement/plugin.yaml" \
        "$ROOT/plugins/tdd-enforcement/README.md" \
        "$ROOT/scripts/tdd-enforcement-state.sh"
    [ "$status" -ne 0 ]
}
