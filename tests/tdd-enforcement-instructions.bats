#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

policy_consumers() {
    cat <<'EOF'
commands/dr-do.md
commands/dr-plan.md
agents/developer.md
skills/testing/SKILL.md
skills/testing/tdd-discipline.md
skills/ai-quality/SKILL.md
skills/writing-plans/SKILL.md
skills/systematic-debugging/SKILL.md
skills/verification-before-completion/SKILL.md
skills/datarim-system/SKILL.md
EOF
}

@test "every canonical TDD consumer references the workspace resolver" {
    local file
    while IFS= read -r file; do
        grep -qF 'tdd-enforcement-state.sh' "$REPO/$file" || {
            echo "missing resolver contract: $file" >&2
            return 1
        }
    done < <(policy_consumers)
}

@test "every canonical TDD consumer distinguishes required and optional state" {
    local file
    while IFS= read -r file; do
        grep -qiF 'required' "$REPO/$file" && grep -qiF 'optional' "$REPO/$file" || {
            echo "missing state semantics: $file" >&2
            return 1
        }
    done < <(policy_consumers)
}

@test "core implementation boundaries retain mandatory tests and downstream gates" {
    grep -qF 'Automated tests remain mandatory' "$REPO/commands/dr-do.md" \
        && grep -qF 'Automated tests remain mandatory' "$REPO/agents/developer.md" \
        && grep -qF 'Automated tests remain mandatory' "$REPO/skills/testing/tdd-discipline.md" \
        && grep -qF 'QA and compliance remain mandatory' "$REPO/commands/dr-do.md"
}

@test "optional state never declares automated tests optional" {
    ! grep -R -Eqi 'automated tests (are |become )?optional|optional automated tests|skip automated tests' \
        "$REPO/commands/dr-do.md" \
        "$REPO/commands/dr-plan.md" \
        "$REPO/agents/developer.md" \
        "$REPO/skills/testing" \
        "$REPO/skills/ai-quality/SKILL.md"
}

@test "dr-do action sequencing is explicitly qualified by effective state" {
    grep -qF 'If the effective state is `required`' "$REPO/commands/dr-do.md" \
        && grep -qF 'If the effective state is `optional`' "$REPO/commands/dr-do.md" \
        && ! grep -qF -- '- **TDD Loop**: Write test -> Fail -> Code -> Pass.' "$REPO/commands/dr-do.md" \
        && ! grep -qF 'tests before code.' "$REPO/commands/dr-do.md"
}

@test "Cursor installer copies the resolver and its library" {
    grep -qF 'scripts/tdd-enforcement-state.sh' "$REPO/install.sh" \
        && grep -qF 'scripts/lib/plugin-system.sh' "$REPO/install.sh"
}

@test "plugin documentation states default-on and retained quality floor" {
    grep -qiF 'enabled by default' "$REPO/plugins/tdd-enforcement/README.md" \
        && grep -qF 'Automated tests remain mandatory' "$REPO/plugins/tdd-enforcement/README.md" \
        && grep -qiF 'enabled by default' "$REPO/documentation/how-to/tdd-enforcement-plugin.md"
}
