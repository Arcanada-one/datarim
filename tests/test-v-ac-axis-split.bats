#!/usr/bin/env bats
#
# Spec-regression tests for skills/v-ac-axis-split/SKILL.md.
#
# Guards two contracts:
#   1. Skill-internal shape (frontmatter / required headings / reference case /
#      no stack-specific terms) — protects the skill body from accidental
#      future edits that would erase the deterministic-vs-statistical axis
#      guidance.
#   2. Public-surface fanout — documentation/reference/skills.md catalog row + count bump,
#      README.md skill count, expectations-checklist.md cross-link.
#      Asymmetric drift between framework runtime and consumer-facing surfaces
#      would defeat the discoverability of the skill via main docs pages.
#
# If any test fails, the canonical-spec contract for v-ac-axis-split has
# regressed in either the skill body itself or in one of its public-surface
# consumers.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
SKILL="${REPO_ROOT}/skills/v-ac-axis-split/SKILL.md"
DOCS_SKILLS="${REPO_ROOT}/documentation/reference/skills.md"
README="${REPO_ROOT}/README.md"
EXPECTATIONS="${REPO_ROOT}/skills/expectations-checklist/SKILL.md"

# ---------- skill-internal shape ----------

@test "v-ac-axis-split skill file exists" {
    [ -f "$SKILL" ]
}

@test "frontmatter declares name: v-ac-axis-split" {
    run grep -E "^name: v-ac-axis-split$" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "frontmatter description mentions deterministic" {
    run grep -E "^description:.*deterministic" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "frontmatter description mentions statistical" {
    run grep -E "^description:.*statistical" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill body contains Pattern heading" {
    run grep -E "^## Pattern$" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill body contains Why heading" {
    run grep -E "^## Why$" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill body contains How to apply heading" {
    run grep -E "^## How to apply$" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill body contains Reference case heading" {
    run grep -E "^## Reference case$" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "Reference case section has at least one bullet" {
    # History-agnostic gate forbids literal task IDs in skills/*.md, so the
    # original check for the literal TUNE-0183 string is no longer valid.
    # Assert that the Reference case section contains at least one bullet
    # entry instead.
    run awk "/^## Reference case\$/{flag=1; next} /^## /{flag=0} flag && /^- /" "$SKILL"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# <!-- gate:example-only -->
# The grep pattern below intentionally enumerates stack-agnostic-gate
# denylist terms as a regression-test proxy. Wrapped in the gate's
# example-only escape hatch (skills/evolution/stack-agnostic-gate.md) so
# the gate itself does not flag this test's pattern as stack-specific.
@test "skill body has no stack-specific terms (stack-agnostic proxy)" {
    run grep -iE "nestjs|npm install|pnpm install|prisma|fastapi|cargo build|vitest" "$SKILL"
    [ "$status" -ne 0 ]
}
# <!-- /gate:example-only -->


# ---------- public-surface fanout (TUNE-0090) ----------

@test "documentation/reference/skills.md contains catalog row for v-ac-axis-split" {
    run grep -E "^\| v-ac-axis-split " "$DOCS_SKILLS"
    [ "$status" -eq 0 ]
}

@test "documentation/reference/skills.md skill count is a plausible integer" {
    run grep -E "^Datarim includes [0-9]+ reusable skill modules" "$DOCS_SKILLS"
    [ "$status" -eq 0 ]
}

@test "documentation/reference/skills.md Distribution line exists" {
    run grep -E "^\*\*Distribution:\*\*.*reference" "$DOCS_SKILLS"
    [ "$status" -eq 0 ]
}

@test "README.md mentions reusable skills at least twice" {
    run bash -c "grep -cE '[0-9]+ reusable skills' \"$README\""
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "skills/expectations-checklist/SKILL.md cross-links v-ac-axis-split" {
    run grep -E "v-ac-axis-split" "$EXPECTATIONS"
    [ "$status" -eq 0 ]
}
