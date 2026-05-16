#!/usr/bin/env bats
#
# Spec-regression tests asserting the **absence** of the operator-only
# contract on `/dr-init` and `/dr-archive`.
#
# The operator-only contract (introduced as `disable-model-invocation: true`
# in command frontmatter + 🔒 marker in H1 + Operator-only marker blockquote
# in body + planner/compliance STOP-rule + cta-format § Operator-only
# commands + pipeline-routing Mermaid `classDef operatorOnly`) was removed
# to restore agent autonomy on the two lifecycle commands per the FB-rules
# (Autonomous Agent Operating Rules) mandate. Structural guards remain in
# code (see `tests/init-archive-structural-guards.bats`).
#
# This file inverts the original `operator-only-commands.bats` so the same
# surfaces continue to be tracked, but as «marker must be absent» rather
# than «marker must be present». A red test here means the operator-only
# contract has regressed into the runtime and the relaxation must be
# re-applied (or the change explicitly approved as a new governance
# decision).
#
# Renamed from `tests/operator-only-commands.bats` to preserve the
# git-history signal that the operator-only contract once existed on these
# two commands.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
COMMANDS_DIR="${REPO_ROOT}/commands"
AGENTS_DIR="${REPO_ROOT}/agents"
SKILLS_DIR="${REPO_ROOT}/skills"

# ---------- frontmatter flag invariant (set membership) ----------
# Canonical state: no /dr-* command carries `disable-model-invocation: true`.

@test "dr-archive does NOT carry disable-model-invocation: true" {
    run grep -E "^disable-model-invocation: true$" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -ne 0 ]
}

@test "dr-init does NOT carry disable-model-invocation: true" {
    run grep -E "^disable-model-invocation: true$" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -ne 0 ]
}

@test "no /dr-*.md command carries disable-model-invocation: true (no drift)" {
    actual=$(grep -lE "^disable-model-invocation: true$" "${COMMANDS_DIR}"/dr-*.md 2>/dev/null \
        | xargs -n1 basename 2>/dev/null \
        | sed 's/\.md$//' \
        | sort \
        | tr '\n' ' ' \
        | sed 's/ $//')
    [ -z "$actual" ]
}

# ---------- marker absence invariant ----------

@test "dr-archive.md does NOT contain visible Operator-only marker" {
    run grep -F "Operator-only" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -ne 0 ]
}

@test "dr-init.md does NOT contain visible Operator-only marker" {
    run grep -F "Operator-only" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -ne 0 ]
}

@test "dr-archive.md does NOT carry 'cannot invoke' wording" {
    run grep -F "cannot invoke" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -ne 0 ]
}

@test "dr-init.md does NOT carry 'cannot invoke' wording" {
    run grep -F "cannot invoke" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -ne 0 ]
}

# ---------- cta-format no longer documents the operator-only class ----------

@test "cta-format.md does NOT document Operator-only command class" {
    run grep -F "Operator-only commands" "${SKILLS_DIR}/cta-format.md"
    [ "$status" -ne 0 ]
}

@test "cta-format.md does NOT reference the lock badge (🔒)" {
    run grep -F "🔒" "${SKILLS_DIR}/cta-format.md"
    [ "$status" -ne 0 ]
}

# ---------- pipeline-closure agents no longer carry STOP rule ----------

@test "planner agent does NOT carry operator-only STOP rule" {
    run grep -F "operator-only" "${AGENTS_DIR}/planner.md"
    [ "$status" -ne 0 ]
}

@test "compliance agent does NOT carry operator-only STOP rule" {
    run grep -F "operator-only" "${AGENTS_DIR}/compliance.md"
    [ "$status" -ne 0 ]
}

# ---------- dr-help no longer annotates the two entries ----------

@test "dr-help does NOT annotate dr-init/dr-archive as operator-only" {
    run grep -F "operator-only" "${COMMANDS_DIR}/dr-help.md"
    [ "$status" -ne 0 ]
}

# ---------- dr-compliance Next Steps no longer references operator-only ----------

@test "dr-compliance Next Steps does NOT reference operator-only" {
    run grep -F "operator-only" "${COMMANDS_DIR}/dr-compliance.md"
    [ "$status" -ne 0 ]
}
