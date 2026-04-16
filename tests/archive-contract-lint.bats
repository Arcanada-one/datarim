#!/usr/bin/env bats
#
# Spec-regression tests for commands/dr-archive.md.
#
# AC-2.4 (TUNE-0007): each of the 3 prompt branches — Commit / Accept / Abort —
# must remain documented in the `/dr-archive` step-0 gate. These tests guard
# against silent weakening of the contract introduced by TUNE-0003 Proposal 1.
#
# Note: the prompt itself runs inside Claude Code (prose, not executable), so
# we verify the SPEC carries the required language. If the spec is edited to
# remove an option, these tests fail and force re-ratification (Operating-Model
# Gate — TUNE-0012).

SPEC="${BATS_TEST_DIRNAME}/../commands/dr-archive.md"

@test "spec file exists" {
    [ -f "$SPEC" ]
}

@test "step 0 'PRE-ARCHIVE CLEAN-GIT CHECK' section is present" {
    run grep -F "PRE-ARCHIVE CLEAN-GIT CHECK" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec mandates running 'git status --porcelain' per touched repo" {
    run grep -F "git status --porcelain" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec explicitly covers multi-repo case ('every git repository touched')" {
    run grep -iE "every git repository (touched|involved)" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec requires STOP on dirty tree" {
    run grep -F "STOP" "$SPEC"
    [ "$status" -eq 0 ]
}

# ---------- AC-2.4: 3 prompt branches ----------

@test "branch 1/3: 'Commit now' option is documented" {
    run grep -F "Commit now" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "branch 2/3: 'Accept pending state' option is documented" {
    run grep -iE "accept.*pending state|explicitly accept" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "branch 3/3: 'Abort' option is documented" {
    run grep -E "Abort( archive)?" "$SPEC"
    [ "$status" -eq 0 ]
}

# ---------- governance language ----------

@test "spec references 'Known Outstanding State' section for accept-path" {
    run grep -F "Known Outstanding State" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec rejects silent archive over dirty tree" {
    run grep -iE "do not archive.*dirty|dirty working tree silently" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec cites TUNE-0003 for governance rationale" {
    run grep -F "TUNE-0003" "$SPEC"
    [ "$status" -eq 0 ]
}
