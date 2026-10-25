#!/usr/bin/env bats

assert_registration_contract() {
    local file="$BATS_TEST_DIRNAME/../$1"
    rg -Fq 'finalize-safety.py' "$file"
    rg -Fq 'add --ledger' "$file"
    rg -q -- '--kind (KIND|worktree)' "$file"
    rg -iq 'must' "$file"
}

@test "dr-do registers task-owned resources at creation time" {
    assert_registration_contract commands/dr-do.md
}

@test "dr-qa registers task-owned resources at creation time" {
    assert_registration_contract commands/dr-qa.md
}

@test "dr-compliance registers task-owned resources at creation time" {
    assert_registration_contract commands/dr-compliance.md
}

@test "dr-auto registers task-owned resources at creation time" {
    assert_registration_contract commands/dr-auto.md
}

@test "dr-orchestrate registers task-owned resources at creation time" {
    assert_registration_contract commands/dr-orchestrate.md
}

@test "worktree skill registers created worktree and branch" {
    assert_registration_contract skills/using-git-worktrees/SKILL.md
    rg -Fq -- '--kind branch --value "$BRANCH_NAME"' "$BATS_TEST_DIRNAME/../skills/using-git-worktrees/SKILL.md"
}
