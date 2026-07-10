#!/usr/bin/env bats
# TUNE-0408 — subagent path-resolution NOTE regression guard.
# Prevents recurrence of the VERD-0031 false BLOCKED ("expectations file
# missing"), caused by a subagent probing `Projects/<name>/code/datarim/`
# for a code-project task instead of the project's git-toplevel `datarim/`.
# Source: reflection-VERD-0031 Class B (discovered-during-auto-VERD-0031).

SKILL_DOC="$BATS_TEST_DIRNAME/../skills/datarim-system/path-and-storage.md"
DR_QA="$BATS_TEST_DIRNAME/../commands/dr-qa.md"
DR_COMPLIANCE="$BATS_TEST_DIRNAME/../commands/dr-compliance.md"

@test "path-and-storage.md documents the code/datarim/ anti-pattern for code-projects" {
    run grep -c 'code/datarim/. is NOT a general convention' "$SKILL_DOC"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "path-and-storage.md cites the VERD-0031 precedent" {
    run grep -c 'VERD-0031' "$SKILL_DOC"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-qa.md Step 2 warns against probing code/datarim/ for code-projects" {
    run grep -c 'NEVER probe .Projects/<name>/code/datarim/.' "$DR_QA"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-compliance.md Step 2 warns against probing code/datarim/ for code-projects" {
    run grep -c 'NEVER probe .Projects/<name>/code/datarim/.' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
