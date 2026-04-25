#!/usr/bin/env bats
#
# Spec-regression tests for skills/cta-format.md (TUNE-0032 / v1.16.0).
#
# These tests guard the canonical CTA "Next Step" block contract:
#   - cta-format.md exists and declares the canonical format
#   - Every /dr-* command references the cta-format skill
#   - The 5 pipeline agents (planner, architect, developer, reviewer, compliance)
#     load the cta-format skill in their Context Loading section
#   - The Mode Transition documentation in datarim-system/backlog-and-routing.md
#     references cta-format
#   - Anti-patterns from the spec (box-drawing chars, missing primary marker)
#     do not regress in any command file
#
# If any of these tests fail, the CTA spec has drifted from one of its consumers
# and the canonical-spec contract is broken.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SKILL="${REPO_ROOT}/skills/cta-format.md"
TEMPLATE="${REPO_ROOT}/templates/cta-template.md"
ROUTING="${REPO_ROOT}/skills/datarim-system/backlog-and-routing.md"
COMMANDS_DIR="${REPO_ROOT}/commands"
AGENTS_DIR="${REPO_ROOT}/agents"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/cta-format/fixtures"

# ---------- skill + template existence ----------

@test "cta-format skill file exists" {
    [ -f "$SKILL" ]
}

@test "cta-format skill has YAML frontmatter with name=cta-format" {
    run grep -E "^name: cta-format$" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "cta-template.md exists" {
    [ -f "$TEMPLATE" ]
}

@test "cta-format skill documents Single Active Task block" {
    run grep -F "Canonical Block — Single Active Task" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "cta-format skill documents Multiple Active Tasks (Variant B)" {
    run grep -F "Canonical Block — Multiple Active Tasks" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "cta-format skill documents FAIL-Routing variant" {
    run grep -F "Canonical Block — FAIL-Routing" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "cta-format skill documents anti-patterns" {
    run grep -F "Anti-Patterns (DO NOT)" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "cta-format skill warns against box-drawing characters" {
    run grep -E "(box-drawing|Mojibake on Windows|U\+2500)" "$SKILL"
    [ "$status" -eq 0 ]
}

# ---------- command files reference cta-format ----------

@test "command dr-init.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "command dr-prd.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-prd.md"
    [ "$status" -eq 0 ]
}

@test "command dr-plan.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-plan.md"
    [ "$status" -eq 0 ]
}

@test "command dr-design.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-design.md"
    [ "$status" -eq 0 ]
}

@test "command dr-do.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-do.md"
    [ "$status" -eq 0 ]
}

@test "command dr-qa.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-qa.md"
    [ "$status" -eq 0 ]
}

@test "command dr-compliance.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-compliance.md"
    [ "$status" -eq 0 ]
}

@test "command dr-archive.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

@test "command dr-status.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-status.md"
    [ "$status" -eq 0 ]
}

@test "command dr-continue.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-continue.md"
    [ "$status" -eq 0 ]
}

@test "command dr-help.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-help.md"
    [ "$status" -eq 0 ]
}

@test "command dr-write.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-write.md"
    [ "$status" -eq 0 ]
}

@test "command dr-edit.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-edit.md"
    [ "$status" -eq 0 ]
}

@test "command dr-publish.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-publish.md"
    [ "$status" -eq 0 ]
}

@test "command dr-addskill.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-addskill.md"
    [ "$status" -eq 0 ]
}

@test "command dr-optimize.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-optimize.md"
    [ "$status" -eq 0 ]
}

@test "command dr-dream.md references cta-format" {
    run grep -F "cta-format.md" "${COMMANDS_DIR}/dr-dream.md"
    [ "$status" -eq 0 ]
}

# ---------- agents load cta-format ----------

@test "agent planner.md loads cta-format skill" {
    run grep -F "cta-format.md" "${AGENTS_DIR}/planner.md"
    [ "$status" -eq 0 ]
}

@test "agent architect.md loads cta-format skill" {
    run grep -F "cta-format.md" "${AGENTS_DIR}/architect.md"
    [ "$status" -eq 0 ]
}

@test "agent developer.md loads cta-format skill" {
    run grep -F "cta-format.md" "${AGENTS_DIR}/developer.md"
    [ "$status" -eq 0 ]
}

@test "agent reviewer.md loads cta-format skill" {
    run grep -F "cta-format.md" "${AGENTS_DIR}/reviewer.md"
    [ "$status" -eq 0 ]
}

@test "agent compliance.md loads cta-format skill" {
    run grep -F "cta-format.md" "${AGENTS_DIR}/compliance.md"
    [ "$status" -eq 0 ]
}

# ---------- routing skill references cta-format ----------

@test "backlog-and-routing.md references cta-format for transitions" {
    run grep -F "cta-format.md" "$ROUTING"
    [ "$status" -eq 0 ]
}

@test "backlog-and-routing.md documents FAIL-Routing layer-to-command map" {
    run grep -F "Layer-to-command map" "$ROUTING"
    [ "$status" -eq 0 ]
}

# ---------- anti-pattern regression guards ----------

@test "no command file uses U+2500 box-drawing as separator (Windows mojibake risk)" {
    # Search all dr-*.md command files for the specific pattern of box-drawing
    # used as a separator (3+ consecutive U+2500 characters).
    found=0
    for f in "${COMMANDS_DIR}"/dr-*.md; do
        if grep -qE '─{3,}' "$f"; then
            found=$((found + 1))
        fi
    done
    [ "$found" -eq 0 ]
}

# ---------- fixture sanity ----------

@test "fixture single-task.md exists and contains primary marker" {
    [ -f "${FIXTURES_DIR}/single-task.md" ]
    run grep -F "**рекомендуется**" "${FIXTURES_DIR}/single-task.md"
    [ "$status" -eq 0 ]
}

@test "fixture multi-task.md contains Variant B menu" {
    [ -f "${FIXTURES_DIR}/multi-task.md" ]
    run grep -F "**Другие активные задачи:**" "${FIXTURES_DIR}/multi-task.md"
    [ "$status" -eq 0 ]
}

@test "fixture fail-routing.md uses FAIL-Routing header" {
    [ -f "${FIXTURES_DIR}/fail-routing.md" ]
    run grep -E "QA failed для|Compliance NON-COMPLIANT для" "${FIXTURES_DIR}/fail-routing.md"
    [ "$status" -eq 0 ]
}

@test "fixture fail-routing.md mentions earliest failed layer" {
    run grep -F "earliest failed layer" "${FIXTURES_DIR}/fail-routing.md"
    [ "$status" -eq 0 ]
}

# ---------- canonical structure invariants (each fixture) ----------

@test "every fixture is wrapped by Markdown HR ---" {
    for f in "${FIXTURES_DIR}"/*.md; do
        head_line=$(head -n1 "$f")
        last_line=$(tail -n1 "$f")
        [ "$head_line" = "---" ] || { echo "head_line='$head_line' in $f"; return 1; }
        [ "$last_line" = "---" ] || { echo "last_line='$last_line' in $f"; return 1; }
    done
}

@test "every fixture contains exactly one primary marker" {
    for f in "${FIXTURES_DIR}"/single-task.md "${FIXTURES_DIR}"/multi-task.md "${FIXTURES_DIR}"/fail-routing.md; do
        count=$(grep -c '\*\*рекомендуется\*\*' "$f")
        [ "$count" -eq 1 ] || { echo "fixture $f has $count primary markers (expected 1)"; return 1; }
    done
}
