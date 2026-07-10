#!/usr/bin/env bats
# check-component-counts.bats — V-AC matrix for the framework component
# counts-drift enforcer (TUNE-0174). Each test builds a throwaway fixture
# root (CLAUDE.md + README.md + commands/agents/skills/templates dirs) and
# asserts detector behaviour. Repo-self-consistency only — no registry, no
# cross-repo dependency (contrast with check-repo-site-sync.bats).

setup() {
    DETECTOR="${BATS_TEST_DIRNAME}/../dev-tools/check-component-counts.sh"
    KB="$(mktemp -d)"
    mkdir -p "$KB/commands" "$KB/agents" "$KB/skills/skill-a" "$KB/skills/skill-b" "$KB/templates"
    : > "$KB/commands/a.md"; : > "$KB/commands/b.md"                       # 2 commands
    : > "$KB/agents/x.md"                                                 # 1 agent
    : > "$KB/skills/skill-a/SKILL.md"; : > "$KB/skills/skill-b/SKILL.md"  # 2 skills (one dir each)
    : > "$KB/templates/t1.md"                                             # 1 template
    write_docs 2 1 2 1   # default: fully-consistent claims (commands agents skills templates)
}

teardown() { rm -rf "$KB"; }

# Helper: write CLAUDE.md + README.md with parenthesized count claims.
write_docs() {  # $1=commands $2=agents $3=skills $4=templates
    cat > "$KB/CLAUDE.md" <<EOF
# CLAUDE.md fixture
Agent files: \`\$HOME/.claude/agents/{name}.md\` ($2 agents)
Skill files: \`\$HOME/.claude/skills/{name}/SKILL.md\` ($3 skills, fixture)
Command files: \`\$HOME/.claude/commands/{name}.md\` ($1 commands, fixture)
EOF
    cat > "$KB/README.md" <<EOF
# README fixture
\`\`\`
datarim/
  agents/            # Agent personas ($2 agents)
  skills/            # Knowledge modules ($3 skills)
  commands/          # Slash commands ($1 commands)
  templates/         # Task and document templates ($4 templates)
\`\`\`
EOF
}

@test "help exits 0" {
    run bash "$DETECTOR" --help
    [ "$status" -eq 0 ]
}

@test "unknown flag exits 2" {
    run bash "$DETECTOR" --bogus --root "$KB"
    [ "$status" -eq 2 ]
}

@test "missing root (no CLAUDE.md) exits 3" {
    rm -f "$KB/CLAUDE.md"
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 3 ]
}

@test "fully consistent fixture: --check exits 0 (V-AC-1)" {
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 0 ]
}

@test "corrupted templates claim: --check exits 1, --report names category+claim+actual (V-AC-2)" {
    write_docs 2 1 2 19   # templates claim corrupted to 19, actual is still 1
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *templates* ]]
    [[ "$output" == *"claims 19"* ]]
    [[ "$output" == *"actual 1"* ]]
}

@test "corrupted skills claim: --check exits 1 (V-AC-2)" {
    write_docs 2 1 99 1   # skills claim corrupted, actual dirs still 2
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *skills* ]]
    [[ "$output" == *"claims 99"* ]]
    [[ "$output" == *"actual 2"* ]]
}

@test "corrupted commands claim: --check exits 1 (V-AC-2)" {
    write_docs 5 1 2 1   # commands claim corrupted, actual still 2
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
}

@test "corrupted agents claim: --check exits 1 (V-AC-2)" {
    write_docs 2 7 2 1   # agents claim corrupted, actual still 1
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
}

@test "no parenthesized claim present: not a drift (skip), exits 0" {
    cat > "$KB/CLAUDE.md" <<EOF
# CLAUDE.md fixture with no count claims at all
Nothing to see here.
EOF
    cat > "$KB/README.md" <<EOF
# README fixture with no count claims
EOF
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 0 ]
}

@test "--root defaults to walking up from cwd to find CLAUDE.md" {
    mkdir -p "$KB/nested/deeper"
    run bash -c "cd '$KB/nested/deeper' && bash '$DETECTOR' --check"
    [ "$status" -eq 0 ]
}
