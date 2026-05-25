#!/usr/bin/env bats
#
# TUNE-0259 — command-bound snapshot emission directive wiring.
#
# Architectural decision (creative-TUNE-0259): Variant 2 — the snapshot
# emission contract is bound to the COMMAND file (which owns stage), not
# the agent file (which is reused across multiple stages). Each of the 7
# CTA-emitting `commands/dr-*.md` declares a `## Stage Snapshot Emission`
# section carrying (a) a reference to the canonical recipe in
# `skills/cta-format.md § Snapshot Emission`, (b) the literal stage value,
# and (c) the literal command value. The body of the writer recipe lives
# in `skills/cta-format.md` (single source of truth).
#
# This suite enforces 3 checks per command × 7 commands = 21 tests.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# Stage-to-command mapping (bash 3.2 compatible — no associative arrays).
# Format: <basename>|<stage-literal>|<command-literal>
COMMAND_PAIRS=(
    "dr-init|init|/dr-init"
    "dr-prd|prd|/dr-prd"
    "dr-plan|plan|/dr-plan"
    "dr-design|design|/dr-design"
    "dr-do|do|/dr-do"
    "dr-qa|qa|/dr-qa"
    "dr-compliance|compliance|/dr-compliance"
)

# ---------- Check 1: section header present in every command ----------

@test "dr-init.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "dr-prd.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-prd.md"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-plan.md"
    [ "$status" -eq 0 ]
}

@test "dr-design.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-design.md"
    [ "$status" -eq 0 ]
}

@test "dr-do.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-do.md"
    [ "$status" -eq 0 ]
}

@test "dr-qa.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-qa.md"
    [ "$status" -eq 0 ]
}

@test "dr-compliance.md carries '## Stage Snapshot Emission' section" {
    run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/dr-compliance.md"
    [ "$status" -eq 0 ]
}

# ---------- Check 2: literal stage value bound per command ----------

@test "dr-init.md binds stage literal 'init'" {
    run grep -E '^- `stage`: `init`$' "${REPO_ROOT}/commands/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "dr-prd.md binds stage literal 'prd'" {
    run grep -E '^- `stage`: `prd`$' "${REPO_ROOT}/commands/dr-prd.md"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md binds stage literal 'plan'" {
    run grep -E '^- `stage`: `plan`$' "${REPO_ROOT}/commands/dr-plan.md"
    [ "$status" -eq 0 ]
}

@test "dr-design.md binds stage literal 'design'" {
    run grep -E '^- `stage`: `design`$' "${REPO_ROOT}/commands/dr-design.md"
    [ "$status" -eq 0 ]
}

@test "dr-do.md binds stage literal 'do'" {
    run grep -E '^- `stage`: `do`$' "${REPO_ROOT}/commands/dr-do.md"
    [ "$status" -eq 0 ]
}

@test "dr-qa.md binds stage literal 'qa'" {
    run grep -E '^- `stage`: `qa`$' "${REPO_ROOT}/commands/dr-qa.md"
    [ "$status" -eq 0 ]
}

@test "dr-compliance.md binds stage literal 'compliance'" {
    run grep -E '^- `stage`: `compliance`$' "${REPO_ROOT}/commands/dr-compliance.md"
    [ "$status" -eq 0 ]
}

# ---------- Check 3: reference to canonical recipe in cta-format.md ----------

@test "dr-init.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "dr-prd.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-prd.md"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-plan.md"
    [ "$status" -eq 0 ]
}

@test "dr-design.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-design.md"
    [ "$status" -eq 0 ]
}

@test "dr-do.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-do.md"
    [ "$status" -eq 0 ]
}

@test "dr-qa.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-qa.md"
    [ "$status" -eq 0 ]
}

@test "dr-compliance.md references cta-format.md § Snapshot Emission" {
    run grep -F 'skills/cta-format.md` § Snapshot Emission' "${REPO_ROOT}/commands/dr-compliance.md"
    [ "$status" -eq 0 ]
}

# ---------- AC-1 aggregate gate ----------

@test "AC-1 — exactly 7 commands carry 'snapshot emission per' directive" {
    count="$(grep -l 'snapshot emission per' "${REPO_ROOT}/commands/"dr-*.md | wc -l | tr -d ' ')"
    [ "$count" -eq 7 ]
}

@test "AC-1 — cta-format.md carries write_stage_snapshot recipe (>=1 hit)" {
    count="$(grep -c 'write_stage_snapshot' "${REPO_ROOT}/skills/cta-format.md" || true)"
    [ "$count" -ge 1 ]
}
