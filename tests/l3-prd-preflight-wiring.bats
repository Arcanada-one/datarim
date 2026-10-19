#!/usr/bin/env bats
#
# L3/L4 PRD pre-flight wiring.
#
# The "required PRD" condition of an L3/L4 task is decidable before any
# implementation starts, yet the only mechanical check (`spec-graph-gate.sh`)
# used to run at the end of `/dr-do` and at compliance. The `/dr-init` waiver
# prompt is prose that `/dr-auto` resolved through a memory lookup, so a task
# could reach compliance with neither a PRD nor a waiver and fail there,
# after all its evidence was recorded. These tests pin the check to the
# point before implementation in both the manual and the autonomous path.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_DO="$REPO_ROOT/commands/dr-do.md"
DR_AUTO="$REPO_ROOT/commands/dr-auto.md"
DR_INIT="$REPO_ROOT/commands/dr-init.md"
AUTO_SKILL="$REPO_ROOT/skills/autonomous-mode/SKILL.md"
CONTRACT="$REPO_ROOT/skills/datarim-system/task-identity-and-context.md"
GATE="$REPO_ROOT/dev-tools/spec-graph-gate.sh"

# line_of <file> <fixed string> — first line number, empty when absent.
line_of() {
    grep -nF -m1 -- "$2" "$1" | cut -d: -f1
}

@test "dr-do has an L3/L4 PRD pre-flight step that runs the gate before ACTION" {
    pre="$(line_of "$DR_DO" "**L3-L4 PRD PRE-FLIGHT**")"
    action="$(line_of "$DR_DO" "7.  **ACTION**")"
    [ -n "$pre" ]
    [ -n "$action" ]
    [ "$pre" -lt "$action" ]
    block="$(sed -n "${pre},${action}p" "$DR_DO")"
    [[ "$block" == *"spec-graph-gate.sh"* ]]
    [[ "$block" == *"--stage do"* ]]
    [[ "$block" == *"required PRD missing"* ]]
    [[ "$block" == *"/dr-prd {TASK-ID}"* ]]
}

@test "dr-do pre-flight forbids the agent from writing a waiver for the operator" {
    pre="$(line_of "$DR_DO" "**L3-L4 PRD PRE-FLIGHT**")"
    action="$(line_of "$DR_DO" "7.  **ACTION**")"
    block="$(sed -n "${pre},${action}p" "$DR_DO")"
    [[ "$block" == *'**PRD waived:**'* ]]
    [[ "$block" == *"operator"* ]]
}

@test "dr-auto checks PRD presence before the first do dispatch" {
    run grep -F "PRD pre-flight before the first \`do\` dispatch" "$DR_AUTO"
    [ "$status" -eq 0 ]
    start="$(line_of "$DR_AUTO" "PRD pre-flight before the first \`do\` dispatch")"
    block="$(sed -n "${start},$((start + 12))p" "$DR_AUTO")"
    [[ "$block" == *"spec-graph-gate.sh"* ]]
    [[ "$block" == *"architect"* ]]
}

@test "dr-init auto mode no longer resolves the waiver gate to a silent pass" {
    run grep -F "Step 4 PRD waiver gate (L3-4)" "$DR_INIT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/dr-prd"* ]]
    [[ "$output" == *"never states a waiver"* ]]
}

@test "autonomous-mode lists the missing PRD as a pre-resolved decision" {
    run grep -F "**Missing PRD on an L3/L4 task.**" "$AUTO_SKILL"
    [ "$status" -eq 0 ]
}

@test "the PRD waiver contract names the pre-implementation check" {
    run grep -F "spec-graph-gate.sh --stage do" "$CONTRACT"
    [ "$status" -eq 0 ]
}

@test "the gate the pre-flight relies on exits 2 for an L3 task with neither PRD nor waiver" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/datarim/tasks" "$tmp/datarim/prd" "$tmp/datarim/plans"
    printf -- '---\nid: PF-0001\ncomplexity: L3\n---\n# PF-0001\n' \
        > "$tmp/datarim/tasks/PF-0001-task-description.md"
    run bash "$GATE" --task PF-0001 --stage do --root "$tmp"
    rm -rf "$tmp"
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}

@test "the gate skips the same task once an operator waiver is recorded" {
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/datarim/tasks" "$tmp/datarim/prd" "$tmp/datarim/plans"
    printf -- '---\nid: PF-0002\ncomplexity: L3\n---\n# PF-0002\n**PRD waived:** scoped follow-up of a parent PRD, no new requirements.\n' \
        > "$tmp/datarim/tasks/PF-0002-task-description.md"
    run bash "$GATE" --task PF-0002 --stage do --root "$tmp"
    rm -rf "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}
