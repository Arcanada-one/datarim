#!/usr/bin/env bats
# Instruction-surface regression: no LLM execution is simulated by these checks.

setup() {
    QUICK_SPEC="$BATS_TEST_DIRNAME/../commands/dr-quick.md"
}

@test "fresh read-only lookup selects conversational evidence before task-file resolution" {
    local lookup="$BATS_TEST_TMPDIR/fresh-lookup"
    mkdir -p "$lookup"
    cd "$lookup"
    [ ! -e datarim ]
    [ ! -e .git ]
    run sed -n '/^## Intent and evidence routing/,/^## Usage/p' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"before resolving task files or allocating an ID"* ]]
    [[ "$output" == *"No Git repository or existing task files are required"* ]]
    [[ "$output" == *"falsifiable acceptance cases in the conversation before searching"* ]]
    [[ "$output" == *"dated source references, exact read-only commands and observed results"* ]]
    [[ "$output" == *"failed attempts and recheck disposition"* ]]
    [[ "$output" == *"informational / UNCERTIFIED"* ]]
    [[ "$output" == *"not structured gate PASS or an archived task"* ]]
    [[ "$output" == *"Do not create metadata, archives, snapshots, or branch changes"* ]]
    [[ "$output" == *"Skip Steps 1–3 and 6–7"* ]]
    [ ! -e datarim ]
    [ ! -e .git ]
}

@test "lookup-to-edit transition restores persisted preflight and host routing before mutation" {
    run sed -n '/^## Intent and evidence routing/,/^## Usage/p' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"re-evaluate execution-host routing before any mutation"* ]]
    [[ "$output" == *"capture the persisted preflight before editing"* ]]
    run grep -F -- '--evidence <evidence.json> --stage quick' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
    run grep -F 'Any nonzero result blocks closure' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
}

@test "lookup completion bypasses snapshot and archive ledger writes explicitly" {
    run grep -F 'Read-only lookups terminate with their informational evidence response; do not emit a task CTA or snapshot.' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
    run grep -F 'Mutating QCK only: after the CTA block' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
    run grep -F 'Remove the task row and Active Tasks mirror per Step 3; do not write a done row.' "$QUICK_SPEC"
    [ "$status" -eq 0 ]
    run grep -F 'Flip the `tasks.md` one-liner to status `done`' "$QUICK_SPEC"
    [ "$status" -eq 1 ]
}
