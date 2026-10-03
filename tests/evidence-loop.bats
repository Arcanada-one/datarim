#!/usr/bin/env bats

@test "structured evidence acceptance and correction loop" {
    run python3 "${BATS_TEST_DIRNAME}/evidence_loop_cases.py"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}

@test "every active pipeline producer and verdict binds the strict evidence gate" {
    local repo="${BATS_TEST_DIRNAME}/.." command stage
    for command in init plan do write edit publish qa compliance archive quick auto; do
        run grep -F 'check-live-evidence.sh --root' "$repo/commands/dr-$command.md"
        # Wrapped prose can separate the executable from --root.
        if [ "$status" -ne 0 ]; then
            run grep -F 'check-live-evidence.sh' "$repo/commands/dr-$command.md"
            [ "$status" -eq 0 ]
        fi
        for flag in --contract --evidence --stage; do
            run grep -F -- "$flag" "$repo/commands/dr-$command.md"
            [ "$status" -eq 0 ]
        done
    done
    for stage in do write edit publish qa compliance archive quick; do
        run grep -F -- "--stage $stage" "$repo/commands/dr-$stage.md"
        [ "$status" -eq 0 ]
    done
}

@test "content standalone remains uncertified and publish preparation never dispatches" {
    local repo="${BATS_TEST_DIRNAME}/.." command
    for command in write edit publish; do
        run grep -F 'UNCERTIFIED' "$repo/commands/dr-$command.md"
        [ "$status" -eq 0 ]
    done
    run grep -F 'does NOT dispatch' "$repo/commands/dr-publish.md"
    [ "$status" -eq 0 ]
    run grep -F 'only through Publisher' "$repo/commands/dr-publish.md"
    [ "$status" -eq 0 ]
}

@test "templates bind acceptance evidence and missing QA baseline cannot be invented" {
    local repo="${BATS_TEST_DIRNAME}/.." template
    for template in task prd compliance-report; do
        run grep -F 'evidence.json' "$repo/templates/$template-template.md"
        [ "$status" -eq 0 ]
    done
    run grep -F 'record the current clean tip with' "$repo/commands/dr-compliance.md"
    [ "$status" -eq 1 ]
}
