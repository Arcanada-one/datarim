#!/usr/bin/env bats
#
# Contract test for dev-tools/check-skill-sibling-refs.sh.
#
# Verifies that SKILL.md files do not contain repo-root-relative
# self-skill sibling references (the operator-flagged defect closed
# by the 2026-05-25 sibling-ref rewrite).
#
# Exit codes: 0 PASS, 1 FAIL.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-skill-sibling-refs.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/skills"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_skill() {
    local name="$1" body="$2"
    mkdir -p "$TMPROOT/skills/$name"
    cat >"$TMPROOT/skills/$name/SKILL.md" <<EOF
---
name: $name
description: test
---

$body
EOF
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "PASS when SKILL.md uses sibling-relative refs (no skills/<own>/<file>)" {
    write_skill "alpha" "$(printf -- '- `pipeline-routing.md`\n- `stage-flows.md`\n')"
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "FAIL when SKILL.md uses repo-root-relative own-sibling refs" {
    write_skill "alpha" "$(printf -- '- \`skills/alpha/pipeline-routing.md\`\n')"
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"alpha"* ]]
}

@test "PASS when SKILL.md uses CROSS-skill refs (skills/<other>/<file> is OK)" {
    write_skill "alpha" "$(printf -- '- See \`skills/beta/recovery.md\` for cross-ref pattern.\n')"
    write_skill "beta"  "$(printf -- '- `bar.md`\n')"
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "ignores .system/ namespace (Codex bundled skills)" {
    mkdir -p "$TMPROOT/skills/.system/imagegen"
    cat >"$TMPROOT/skills/.system/imagegen/SKILL.md" <<EOF
---
name: imagegen
description: bundled codex skill
---
- \`skills/imagegen/foo.md\`
EOF
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "live framework repo currently PASSES the invariant" {
    REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run "$SCRIPT" "$REAL_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
