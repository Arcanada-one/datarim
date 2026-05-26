#!/usr/bin/env bats
#
# Contract test for dev-tools/append-init-task-qa.sh
# --decided-by process-rule-artefact (TUNE-0319).
#
# Verifies:
#   1. process-rule-artefact without --rationale-file → exit 1
#   2. process-rule-artefact with empty/path-less rationale → exit 1
#   3. happy path → exit 0 + ## Process-rule artefacts: heading in append-log
#   4. legacy operator/agent dispositions still work

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/append-init-task-qa.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/tasks"
    INIT="$WORK/datarim/tasks/TUNE-9999-init-task.md"
    cat > "$INIT" <<'EOF'
---
task_id: TUNE-9999
artifact: init-task
schema_version: 1
---

## Operator brief (verbatim)

> dummy brief

## Append-log

_(empty)_
EOF
    Q="$WORK/q.txt"
    A="$WORK/a.txt"
    R="$WORK/r.txt"
    echo "Why does X work this way?" > "$Q"
    echo "Because of Y." > "$A"
}

teardown() {
    rm -rf "$WORK"
}

@test "process-rule-artefact without --rationale-file fails" {
    run "$SCRIPT" --root "$WORK" --task TUNE-9999 --stage compliance --round 1 \
        --question-file "$Q" --answer-file "$A" \
        --decided-by process-rule-artefact --summary "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"process-rule-artefact requires --rationale-file"* ]]
}

@test "process-rule-artefact with path-less rationale fails" {
    echo "no path tokens here" > "$R"
    run "$SCRIPT" --root "$WORK" --task TUNE-9999 --stage compliance --round 1 \
        --question-file "$Q" --answer-file "$A" \
        --decided-by process-rule-artefact --rationale-file "$R" --summary "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must contain at least one artefact path"* ]]
}

@test "process-rule-artefact happy path appends Process-rule artefacts heading" {
    cat > "$R" <<'EOF'
- ~/.claude/CLAUDE.md § English-Only Shipped Instruction Surface
- memory/feedback_english_only_shipped_instruction_surface.md
EOF
    run "$SCRIPT" --root "$WORK" --task TUNE-9999 --stage compliance --round 1 \
        --question-file "$Q" --answer-file "$A" \
        --decided-by process-rule-artefact --rationale-file "$R" --summary "test"
    [ "$status" -eq 0 ]
    grep -q "Decided by:.*process-rule-artefact" "$INIT"
    grep -q "Process-rule artefacts:" "$INIT"
}

@test "legacy --decided-by operator still works" {
    run "$SCRIPT" --root "$WORK" --task TUNE-9999 --stage qa --round 1 \
        --question-file "$Q" --answer-file "$A" \
        --decided-by operator --summary "operator answered"
    [ "$status" -eq 0 ]
    grep -q "Decided by:.*operator" "$INIT"
}

@test "legacy --decided-by agent still requires rationale" {
    run "$SCRIPT" --root "$WORK" --task TUNE-9999 --stage do --round 1 \
        --question-file "$Q" --answer-file "$A" \
        --decided-by agent --summary "agent decided"
    [ "$status" -eq 1 ]
    [[ "$output" == *"agent requires --rationale-file"* ]]
}

@test "unknown --decided-by value still rejected" {
    run "$SCRIPT" --root "$WORK" --task TUNE-9999 --stage prd --round 1 \
        --question-file "$Q" --answer-file "$A" \
        --decided-by bogus --summary "test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be 'operator', 'agent', or 'process-rule-artefact'"* ]]
}
