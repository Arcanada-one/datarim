#!/usr/bin/env bats
#
# tests/known-fix-persistence-wiring.bats
#
# Spec-regression wiring for the known-fix decision path. These assert the
# CONTRACT TEXT, because the steps themselves execute inside the agent, not in
# a shell — the same reason `archive-contract-lint.bats` exists.
#
# Each assertion pins one of the four defects that together produced zero
# known_fix records across every archive since the mechanism landed:
#
#   D1  the writer's target file was declared a precondition, and nothing
#       creates it for the ~95% of tasks that never hit Gap Discovery
#   D2  Step 0.5's freshness fast path jumped from reflection straight to
#       Step 1, skipping Step 0.6 entirely on the common path
#   D3  no deterministic gate — silence and a genuine "none" were the same
#   D4  the reflection template had no `## Known Fix` section, so an agent
#       building the reflection from the template had nowhere to put a verdict

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ARCHIVE="$ROOT/commands/dr-archive.md"
    SKILL="$ROOT/skills/reflecting/SKILL.md"
    TEMPLATE="$ROOT/templates/reflection-template.md"
    GATE="$ROOT/dev-tools/check-known-fix-persistence.sh"
}

# --- D4: the artefact has a slot for the verdict -----------------------------

@test "D4: the reflection template carries a '## Known Fix' section" {
    run grep -cE '^## Known Fix[[:space:]]*$' "$TEMPLATE"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "D4: the template states that 'none' is a passing answer, not a gap" {
    run grep -iF "none" "$TEMPLATE"
    [ "$status" -eq 0 ]
    run grep -iE "never invent a record" "$TEMPLATE"
    [ "$status" -eq 0 ]
}

# --- D1: the writer may create its own target --------------------------------

@test "D1: the known-fix writer no longer requires a pre-existing INSIGHTS file" {
    run grep -F 'to the existing `datarim/insights/INSIGHTS-{task-id}.md`' "$SKILL"
    [ "$status" -ne 0 ]
}

@test "D1: the writer is told to create the INSIGHTS file when absent" {
    run grep -iE "creating that file if it does not yet exist" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "D1: recording 'none' is stated as mandatory, not optional" {
    run grep -iE "Recording .?none.? is MANDATORY" "$SKILL"
    [ "$status" -eq 0 ]
}

# --- D2: the freshness fast path must not skip Step 0.6 ----------------------

@test "D2: the Step 0.5 reuse branch routes to Step 0.6, never straight to Step 1" {
    run grep -F "SKIP the workflow below" "$ARCHIVE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Step 0.6"* ]]
    [[ "$output" != *"and continue to Step 1."* ]]
}

@test "D2: the reuse branch names the steps it must not skip" {
    run grep -F "SKIP the workflow below" "$ARCHIVE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.95"* ]]
}

# --- D3: a deterministic gate exists and is wired ----------------------------

@test "D3: the persistence gate exists and is executable" {
    [ -x "$GATE" ]
}

@test "D3: Step 0.6 invokes the persistence gate" {
    run grep -F "check-known-fix-persistence.sh" "$ARCHIVE"
    [ "$status" -eq 0 ]
}

@test "D3: Step 0.6 documents all three verdicts plus the framework-error exit" {
    run grep -A 8 -F "check-known-fix-persistence.sh" "$ARCHIVE"
    [ "$status" -eq 0 ]
    [[ "$output" == *recorded* ]]
    [[ "$output" == *declined* ]]
    [[ "$output" == *silent* ]]
    [[ "$output" == *invalid* ]]
    [[ "$output" == *"exit 2"* ]]
}

@test "D3: Step 0.6 forbids inventing a record to clear the gate" {
    run grep -A 8 -F "check-known-fix-persistence.sh" "$ARCHIVE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Never invent a record"* ]]
}

@test "D3: Step 0.6 is still present and still the persistence step" {
    run grep -F "0.6. **KNOWN-FIX PERSISTENCE**" "$ARCHIVE"
    [ "$status" -eq 0 ]
}
