#!/usr/bin/env bats
#
# Spec-regression tests for the operator-only command class.
#
# Two slash commands are intentionally invisible to the Skill tool by
# carrying `disable-model-invocation: true` in their frontmatter:
# `dr-init` and `dr-archive`. These are lifecycle bookends — `/dr-init`
# creates `datarim/` and routes prefix→subdir mapping; `/dr-archive`
# performs irreversible workspace mutations (blob-swap, foreign-hunk audit,
# Operator-Handoff section). Both require operator authorisation each
# invocation, so the Skill enumeration MUST hide them and subagents MUST
# NOT attempt to invoke them via the Skill tool.
#
# These tests guard:
#   1. The set membership invariant — {dr-init, dr-archive} is exactly the
#      disabled set; no other /dr-* command carries the flag.
#   2. Each disabled command carries a visible "Operator-only" marker so
#      human readers see the contract.
#   3. `skills/cta-format.md` documents the operator-only class and its
#      🔒 badge convention.
#   4. The pipeline-routing agents (planner, compliance) carry an explicit
#      STOP rule for operator-only gates.
#
# If any of these tests fail, the operator-only contract has drifted and
# a subagent can regress to attempting `Skill(dr-archive)` again.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
COMMANDS_DIR="${REPO_ROOT}/commands"
AGENTS_DIR="${REPO_ROOT}/agents"
SKILLS_DIR="${REPO_ROOT}/skills"

# ---------- set membership invariant ----------
# Canonical disabled set: {dr-archive, dr-init} — asserted by the
# "no drift" test below.

@test "dr-archive carries disable-model-invocation: true" {
    run grep -E "^disable-model-invocation: true$" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

@test "dr-init carries disable-model-invocation: true" {
    run grep -E "^disable-model-invocation: true$" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "exactly dr-archive and dr-init carry disable-model-invocation: true (no drift)" {
    actual=$(grep -lE "^disable-model-invocation: true$" "${COMMANDS_DIR}"/dr-*.md \
        | xargs -n1 basename \
        | sed 's/\.md$//' \
        | sort \
        | tr '\n' ' ' \
        | sed 's/ $//')
    expected="dr-archive dr-init"
    [ "$actual" = "$expected" ]
}

# ---------- marker invariant ----------

@test "dr-archive.md contains visible Operator-only marker" {
    run grep -F "Operator-only" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

@test "dr-init.md contains visible Operator-only marker" {
    run grep -F "Operator-only" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "dr-archive.md marker explains agents cannot invoke it" {
    run grep -F "cannot invoke" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

@test "dr-init.md marker explains agents cannot invoke it" {
    run grep -F "cannot invoke" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -eq 0 ]
}

# ---------- cta-format documents the operator-only class ----------

@test "cta-format.md documents Operator-only command class" {
    run grep -F "Operator-only commands" "${SKILLS_DIR}/cta-format.md"
    [ "$status" -eq 0 ]
}

@test "cta-format.md references the lock badge convention" {
    run grep -F "🔒" "${SKILLS_DIR}/cta-format.md"
    [ "$status" -eq 0 ]
}

# ---------- pipeline-closure agents carry STOP rule ----------

@test "planner agent carries operator-only STOP rule" {
    run grep -F "operator-only" "${AGENTS_DIR}/planner.md"
    [ "$status" -eq 0 ]
}

@test "compliance agent carries operator-only STOP rule" {
    run grep -F "operator-only" "${AGENTS_DIR}/compliance.md"
    [ "$status" -eq 0 ]
}

# ---------- dr-help annotates the two entries ----------

@test "dr-help annotates dr-init and dr-archive as operator-only" {
    run grep -F "operator-only" "${COMMANDS_DIR}/dr-help.md"
    [ "$status" -eq 0 ]
}

# ---------- dr-compliance Next Steps routes via slash, not Skill ----------

@test "dr-compliance Next Steps section references operator-only" {
    run grep -F "operator-only" "${COMMANDS_DIR}/dr-compliance.md"
    [ "$status" -eq 0 ]
}
