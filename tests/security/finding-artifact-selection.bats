#!/usr/bin/env bats

setup() {
    REPO="${BATS_TEST_DIRNAME}/../.."
    WORK="$(mktemp -d)"
    WORK="$(cd "$WORK" && pwd -P)"
    mkdir -p "$WORK/datarim/tasks" "$WORK/datarim/prd"
    cat > "$WORK/datarim/tasks/TEST-0001-task-description.md" <<'EOF'
---
id: TEST-0001
prd: prd/PRD-TEST-0001-v2.md
---
EOF
    cat > "$WORK/datarim/prd/PRD-TEST-0001-v2.md" <<'EOF'
# Example
#### D-REQ-01: select the correct requirements
- V-AC-1: selection is task-bound
  Covers: D-REQ-01
EOF
}

teardown() { rm -rf -- "$WORK"; }

@test "multiline task input cannot select a path outside the state directory" {
    run "$REPO/dev-tools/dr-trace.sh" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *D-REQ-01* ]]
    task=$'TEST-0001\n/../../../outside'
    for tool in dr-trace dr-spec-lint spec-graph-gate; do
        if [ "$tool" = spec-graph-gate ]; then
            run "$REPO/dev-tools/$tool.sh" --task "$task" --root "$WORK" --stage plan --format json
        else
            run "$REPO/dev-tools/$tool.sh" --task "$task" --root "$WORK" --format json
        fi
        [ "$status" -eq 2 ]
        [[ "$output" == *invalid*task* ]]
    done
    run "$REPO/dev-tools/check-expectations-checklist.sh" --task "$task" --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *invalid*task* ]]
    run "$REPO/dev-tools/dr-verify-floor.sh" --task "$task" --workspace "$WORK" --stage plan
    [ "$status" -eq 2 ]
    [[ "$output" == *invalid*task* ]]
}

@test "escaped last quote cannot make an unclosed descriptor scalar valid" {
    run bash -c 'source "$1/scripts/lib/task-artifact-path.sh"; task_artifact_path "$2" TEST-0001 prd' _ "$REPO" "$WORK/datarim"
    [ "$status" -eq 0 ]
    [ "$output" = "$WORK/datarim/prd/PRD-TEST-0001-v2.md" ]
    cat > "$WORK/datarim/tasks/TEST-0001-task-description.md" <<'EOF'
---
id: TEST-0001
prd: prd/PRD-TEST-0001-v2.md
title: "unterminated\"
---
EOF
    run bash -c 'source "$1/scripts/lib/task-artifact-path.sh"; task_artifact_path "$2" TEST-0001 prd' _ "$REPO" "$WORK/datarim"
    [ "$status" -eq 2 ]
    [[ "$output" == *unclosed*scalar* ]]
}
