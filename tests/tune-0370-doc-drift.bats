#!/usr/bin/env bats
#
# Regression test for TUNE-0370 (agent/command/skill spec vs actual-behaviour
# drift, surfaced by CONTENT-0003/0004/0005 factcheck).
#
# Two concrete drifts closed by this task:
#   1. commands/dr-doctor.md cited "/dr-init Step 0.6" as its auto-suggest
#      trigger; the actual structural-compliance-check step in
#      commands/dr-init.md is numbered 2.4. Any future dr-init renumbering
#      must keep dr-doctor.md's cross-reference in sync.
#   2. commands/dr-edit.md restated a fact-check source-count threshold
#      ("2+ independent sources") that diverged from the canonical
#      skills/factcheck/SKILL.md table (critical -> 3+ sources). The fix
#      removes the restated number so the two files cannot drift again.

ROOT="${BATS_TEST_DIRNAME}/.."

@test "dr-doctor.md does not cite a stale /dr-init step number" {
    run grep -c 'Step 0\.6' "${ROOT}/commands/dr-doctor.md"
    [ "$status" -ne 0 ]
}

@test "dr-doctor.md cites the actual dr-init structural-compliance step (2.4)" {
    run grep -c "Step 2\.4" "${ROOT}/commands/dr-doctor.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # The cited step must actually exist as a numbered step in dr-init.md.
    run grep -qE '^2\.4\.' "${ROOT}/commands/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "dr-edit.md does not hardcode a fact-check source-count threshold" {
    # The canonical threshold table lives in skills/factcheck/SKILL.md.
    # dr-edit.md must defer to it, not restate a number that can drift.
    run grep -cE '[0-9]\+ (independent )?sources?' "${ROOT}/commands/dr-edit.md"
    [ "$status" -ne 0 ]
}

@test "skills/factcheck/SKILL.md still defines the critical-claim threshold dr-edit.md defers to" {
    run grep -c 'Must verify with 3+ sources' "${ROOT}/skills/factcheck/SKILL.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
