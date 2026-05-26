#!/usr/bin/env bats
#
# Contract test for dev-tools/check-frontmatter-english.sh.
#
# Verifies that `description:` field across commands/, skills/<n>/SKILL.md,
# and agents/ is English-only (Datarim OSS framework contract).

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-frontmatter-english.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/commands" "$TMPROOT/skills/alpha" "$TMPROOT/agents"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_artefact() {
    local path="$1" desc="$2"
    cat >"$TMPROOT/$path" <<EOF
---
name: alpha
description: $desc
---

body
EOF
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "PASS when all description: fields are English" {
    write_artefact "commands/dr-foo.md" "Plain English description."
    write_artefact "skills/alpha/SKILL.md" "Another English line."
    write_artefact "agents/bar.md" "Agent role one-liner."
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "FAIL when commands/*.md description has Cyrillic" {
    write_artefact "commands/dr-foo.md" "Меta-команда — ломает контракт"
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "FAIL when skills/<name>/SKILL.md description has Cyrillic" {
    write_artefact "skills/alpha/SKILL.md" "Skill активируется через флаг"
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 1 ]
}

@test "FAIL when agents/<name>.md description has Cyrillic" {
    write_artefact "agents/bar.md" "Агент для каких-то задач"
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 1 ]
}

@test "PASS on mixed-content body but English description" {
    cat >"$TMPROOT/skills/alpha/SKILL.md" <<EOF
---
name: alpha
description: English description only.
---

Тело может быть на русском пока что — это вне scope этого validator'а.
EOF
    run "$SCRIPT" "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "live framework repo currently PASSES" {
    REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run "$SCRIPT" "$REAL_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
