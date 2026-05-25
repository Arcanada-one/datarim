#!/usr/bin/env bats
#
# TUNE-0304 Phase 1: contract test for dev-tools/check-skill-layout.sh.
#
# Validates the directory-per-skill layout contract:
#   - each skills/<name>/ must contain a SKILL.md
#   - SKILL.md frontmatter.name must equal parent directory name
#   - directory name must match kebab-case ^[a-z][a-z0-9-]{0,63}$
#   - no flat skills/<name>.md may coexist (post-migration)
#
# Exit codes: 0 PASS, 1 FAIL.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-skill-layout.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/skills"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_skill() {
    local name="$1" frontmatter_name="$2"
    mkdir -p "$TMPROOT/skills/$name"
    cat >"$TMPROOT/skills/$name/SKILL.md" <<EOF
---
name: $frontmatter_name
description: test skill
---
body
EOF
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "PASS on valid layout (single skill, matching name)" {
    write_skill "alpha" "alpha"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "FAIL when SKILL.md missing in skill directory" {
    mkdir -p "$TMPROOT/skills/beta"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing SKILL.md"* ]] || [[ "$output" == *"beta"* ]]
}

@test "FAIL when frontmatter name mismatches directory" {
    write_skill "gamma" "wrong-name"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"name mismatch"* ]] || [[ "$output" == *"gamma"* ]]
}

@test "FAIL when flat skills/<name>.md coexists with directory" {
    write_skill "delta" "delta"
    echo "---" >"$TMPROOT/skills/delta.md"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"flat .md"* ]] || [[ "$output" == *"delta.md"* ]]
}

@test "FAIL when directory name violates kebab-case" {
    mkdir -p "$TMPROOT/skills/BadName"
    cat >"$TMPROOT/skills/BadName/SKILL.md" <<'EOF'
---
name: BadName
description: x
---
EOF
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"kebab"* ]] || [[ "$output" == *"BadName"* ]]
}

@test "skips reserved skills/.system/ namespace (C3)" {
    mkdir -p "$TMPROOT/skills/.system/bundled"
    cat >"$TMPROOT/skills/.system/bundled/SKILL.md" <<'EOF'
---
name: bundled
description: codex bundled
---
EOF
    write_skill "alpha" "alpha"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "PASS with --allow-flat-coexistence (Phase 2-4 hybrid window)" {
    write_skill "alpha" "alpha"
    echo "---" >"$TMPROOT/skills/alpha.md"
    run "$SCRIPT" --root "$TMPROOT" --allow-flat-coexistence
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK-HYBRID"* ]] || [[ "$output" == *"alpha"* ]]
}

@test "PASS on multiple valid skills" {
    write_skill "alpha" "alpha"
    write_skill "beta-one" "beta-one"
    write_skill "gamma-2" "gamma-2"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
}
