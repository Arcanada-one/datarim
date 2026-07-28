#!/usr/bin/env bats

# immutability-wiring.bats — verify immutability/SKILL.md is wired into
# every pipeline command and the architect agent. Dogfood: written BEFORE
# wiring changes land.

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# --- Skill existence (V-AC-1, V-AC-2) ---

@test "immutability/SKILL.md exists" {
    [ -f "$REPO_DIR/skills/immutability/SKILL.md" ]
}

@test "immutability/SKILL.md contains Artefact Immutability Rule heading" {
    run grep -c "^#### Artefact Immutability Rule" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md contains Return-to-Source Transition heading" {
    run grep -c "^#### Return-to-Source Transition" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md contains V-AC Parity Rule heading" {
    run grep -c "^#### V-AC Parity Rule" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md contains Non-Code Parity Rule heading" {
    run grep -c "^#### Non-Code Parity Rule" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md contains Anti-Tautological Rule heading" {
    run grep -c "^#### Anti-Tautological Rule" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md contains Return-to-Source routing table" {
    run grep -c "^| Artefact being changed | Owned by | Routes to |" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- Command wiring (V-AC-3) ---

@test "dr-prd command references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/dr-prd.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-plan command references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/dr-plan.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-design command references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/dr-design.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-do command references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/dr-do.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-qa command references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/dr-qa.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-compliance command references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/dr-compliance.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- Agent wiring (V-AC-4) ---

@test "architect agent references immutability skill" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/agents/architect.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- Frontend-UI wiring (V-AC-5) ---

@test "frontend-ui skill references immutability Frontend-UI Rules" {
    run grep -c "immutability/SKILL.md" "$REPO_DIR/skills/frontend-ui/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- Disciplined exclusions: NOT referenced where it should not be ---

@test "immutability skill is NOT hardcoded in non-pipeline commands" {
    # dr-help, dr-status, dr-doctor, dr-save, dr-continue — none should
    # reference the immutability skill
    local non_pipeline="dr-help.md dr-status.md dr-doctor.md dr-save.md dr-continue.md dr-next.md"
    for cmd in $non_pipeline; do
        if [ -f "$REPO_DIR/commands/$cmd" ]; then
            run grep -c "immutability/SKILL.md" "$REPO_DIR/commands/$cmd"
            [ "$output" = "0" ] || { echo "FAIL: commands/$cmd unexpectedly references immutability/SKILL.md"; false; }
        fi
    done
}

# --- tdd-discipline.md still intact (V-AC-6) ---

@test "tdd-discipline.md still has Test Immutability Rule" {
    run grep -c "Test Immutability Rule" "$REPO_DIR/skills/testing/tdd-discipline.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md still has Return-to-Plan Transition" {
    run grep -c "Return-to-Plan Transition" "$REPO_DIR/skills/testing/tdd-discipline.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- Return-to-source edges in all stages (V-AC-7) ---

@test "immutability/SKILL.md has dr-prd fragment with routing" {
    run grep -c "^### /dr-prd Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md has dr-plan fragment with routing" {
    run grep -c "^### /dr-plan Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md has dr-design fragment with routing" {
    run grep -c "^### /dr-design Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md has dr-do fragment with routing" {
    run grep -c "^### /dr-do Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md has dr-qa fragment with routing" {
    run grep -c "^### /dr-qa Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md has dr-compliance fragment with routing" {
    run grep -c "^### /dr-compliance Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "immutability/SKILL.md has Frontend-UI Rules fragment" {
    run grep -c "^### Frontend-UI Rules" "$REPO_DIR/skills/immutability/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
