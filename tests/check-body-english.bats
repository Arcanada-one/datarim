#!/usr/bin/env bats
#
# Contract test for dev-tools/check-body-english.sh.
#
# Verifies that body content (everything outside YAML frontmatter and
# fenced code blocks) of commands/*.md, skills/<n>/SKILL.md, agents/*.md,
# and plugins/*/commands/*.md is English-only (Datarim OSS framework
# contract — TUNE-0308 / TUNE-0309 Wave 1).

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-body-english.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/commands" \
             "$TMPROOT/skills/alpha" \
             "$TMPROOT/skills/beta" \
             "$TMPROOT/agents" \
             "$TMPROOT/plugins/gamma/commands"
    # Initialise a git repo so the toplevel guard accepts $TMPROOT as a valid root.
    git -C "$TMPROOT" init --quiet --initial-branch=main >/dev/null 2>&1
}

teardown() {
    rm -rf "$TMPROOT"
}

write_file() {
    local path="$1"
    shift
    mkdir -p "$(dirname "$TMPROOT/$path")"
    printf '%s\n' "$@" >"$TMPROOT/$path"
}

@test "01 script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "02 PASS when all bodies are English-only" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Foo command." "---" "" "Plain English body."
    write_file "skills/alpha/SKILL.md" \
        "---" "name: alpha" "description: Alpha skill." "---" "" "Another English line."
    write_file "agents/bar.md" \
        "---" "name: bar" "description: Bar agent." "---" "" "Agent role one-liner."
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "03 FAIL when commands/*.md body has Cyrillic" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Foo command." "---" "" "Эта строка содержит кириллицу."
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "04 FAIL when skills/<n>/SKILL.md body has Cyrillic" {
    write_file "skills/alpha/SKILL.md" \
        "---" "name: alpha" "description: Alpha skill." "---" "" "English line." "Русская строка тут."
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "05 PASS when Cyrillic appears only in YAML frontmatter" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Команда — это нормально во frontmatter (frontmatter checker covers it)." "---" "" "English-only body here."
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "06 PASS when Cyrillic appears only inside fenced code block" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Foo." "---" "" \
        "Plain English prose." \
        '```bash' \
        "echo 'Привет, мир' # cyrillic inside fence is allowed" \
        '```' \
        "More English after fence."
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "07 PASS when Cyrillic line carries valid allow-non-ascii marker" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Foo." "---" "" \
        "English prose." \
        "Слово рекомендуется — CTA marker. <!-- allow-non-ascii: canonical-cta-marker-required-by-cta-format -->"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "08 FAIL when allow-non-ascii marker reason is too short" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Foo." "---" "" \
        "English." \
        "Русский текст. <!-- allow-non-ascii: short -->"
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "09 --scope plugins includes plugins/*/commands/*.md" {
    write_file "plugins/gamma/commands/dr-gamma.md" \
        "---" "name: dr-gamma" "description: Gamma." "---" "" "Текст в плагине ловится."
    run "$SCRIPT" --root "$TMPROOT" --scope plugins
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"dr-gamma.md"* ]]
}

@test "10 --root outside any git toplevel exits 2" {
    BARE="$(mktemp -d)"
    run "$SCRIPT" --root "$BARE"
    rm -rf "$BARE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"toplevel"* ]] || [[ "$output" == *"git"* ]]
}

@test "11 PASS when em-dash and curly quotes appear in body (non-Cyrillic UTF-8)" {
    write_file "commands/dr-foo.md" \
        "---" "name: dr-foo" "description: Foo." "---" "" \
        "English prose — with em-dash and \"curly quotes\" and «guillemets»." \
        "All non-Cyrillic UTF-8 is fine."
    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "12 unknown --scope token exits 2" {
    run "$SCRIPT" --root "$TMPROOT" --scope nonsense
    [ "$status" -eq 2 ]
}
