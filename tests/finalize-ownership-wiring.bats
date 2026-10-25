#!/usr/bin/env bats

assert_registration_contract() {
    local file="$BATS_TEST_DIRNAME/../$1"
    grep -Fq 'finalize-safety.py' "$file"
    grep -Fq 'add --ledger' "$file"
    grep -Eq -- '--kind (KIND|worktree)' "$file"
    grep -iq 'must' "$file"
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
    grep -Fq -- '--kind branch --value "$BRANCH_NAME"' "$BATS_TEST_DIRNAME/../skills/using-git-worktrees/SKILL.md"
}
