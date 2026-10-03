#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../check-github-actions-execution.sh"
    WORK="$(mktemp -d -t github-ci-evidence-XXXXXX)"
    INPUT="${WORK}/evidence.json"
    SHA="0123456789abcdef0123456789abcdef01234567"
    BIN="${WORK}/bin"
    mkdir -p "$BIN"
    cat >"${BIN}/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
endpoint="${*: -1}"
if [[ "$endpoint" == *'/jobs?'* ]]; then
    jq '[{total_count:(.jobs | length),jobs:.jobs}]' "$MOCK_GH_INPUT"
else
    jq '{id:.run.id,run_attempt:.run.run_attempt,head_sha:.run.head_sha,status:.run.status,conclusion:.run.conclusion,event:(.run.event // "push"),updated_at:(.run.updated_at // "2026-07-22T00:00:00Z"),workflow_id:.workflow.id,name:.workflow.name,path:(.workflow.path // "")}' "$MOCK_GH_INPUT"
fi
MOCK
    chmod +x "${BIN}/gh"
    export PATH="${BIN}:${PATH}"
    export MOCK_GH_INPUT="$INPUT"
}

teardown() {
    rm -rf "$WORK"
}

write_bundle() {
    local status="$1" conclusion="$2" runner_id="$3" steps_json="$4"
    cat >"$INPUT" <<EOF
{"schema_version":1,"repository":"owner/repo","workflow":{"id":77,"name":"CI"},"run":{"id":123,"run_attempt":1,"head_sha":"${SHA}","status":"${status}","conclusion":${conclusion}},"jobs":[{"id":456,"name":"Test","runner_id":${runner_id},"status":"${status}","conclusion":${conclusion},"steps":${steps_json}}]}
EOF
}

run_classifier() {
    run "$SCRIPT" --repo owner/repo --run-id 123 --workflow CI \
        --required-job Test --expected-sha "$SHA" --required-conclusion success --format json
}

@test "exact-SHA target workflow with executed successful step passes" {
    write_bundle completed '"success"' 12 '[{"name":"test","status":"completed","conclusion":"success"}]'
    run_classifier
    [ "$status" -eq 0 ]
    [[ "$output" == *'"classification":"executed-success"'* ]]
    [[ "$output" == *'"executed_steps":1'* ]]
}

@test "executed target workflow failure is product evidence and fails" {
    write_bundle completed '"failure"' 12 '[{"name":"test","status":"completed","conclusion":"failure"}]'
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"executed-failed"'* ]]
}

@test "completed run with zero jobs is no-execution" {
    write_bundle completed '"failure"' 0 '[]'
    jq '.jobs=[]' "$INPUT" >"${INPUT}.new" && mv "${INPUT}.new" "$INPUT"
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"no-execution"'* ]]
}

@test "runner zero and no steps is no-execution" {
    write_bundle completed '"failure"' 0 '[]'
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"no-execution"'* ]]
}

@test "queued run is pending and fails closed" {
    write_bundle queued 'null' 0 '[]'
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"pending"'* ]]
}

@test "in-progress run is pending even after a step started" {
    write_bundle in_progress 'null' 12 '[{"name":"test","status":"in_progress","conclusion":null}]'
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"pending"'* ]]
}

@test "successful run on the wrong SHA fails" {
    write_bundle completed '"success"' 12 '[{"name":"test","status":"completed","conclusion":"success"}]'
    jq '.run.head_sha="ffffffffffffffffffffffffffffffffffffffff"' "$INPUT" >"${INPUT}.new" && mv "${INPUT}.new" "$INPUT"
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"sha-mismatch"'* ]]
}

@test "wrong workflow identity fails" {
    write_bundle completed '"success"' 12 '[{"name":"test","status":"completed","conclusion":"success"}]'
    jq '.workflow.name="Deploy"' "$INPUT" >"${INPUT}.new" && mv "${INPUT}.new" "$INPUT"
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"workflow-mismatch"'* ]]
}

@test "completed success with no execution evidence is indeterminate" {
    write_bundle completed '"success"' 0 '[]'
    run_classifier
    [ "$status" -eq 2 ]
    [[ "$output" == *'"classification":"indeterminate"'* ]]
}

@test "malformed JSON is an invocation error" {
    printf '{not-json\n' >"$INPUT"
    run_classifier
    [ "$status" -eq 2 ]
    [[ "$output" == *'"classification":"indeterminate"'* ]]
}

@test "missing required schema field is an invocation error" {
    printf '{"schema_version":1}\n' >"$INPUT"
    run_classifier
    [ "$status" -eq 2 ]
    [[ "$output" == *'"classification":"indeterminate"'* ]]
}

@test "no-execution followed by same-SHA executed success only passes second evidence" {
    write_bundle completed '"failure"' 0 '[]'
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" == *'"classification":"no-execution"'* ]]

    write_bundle completed '"success"' 12 '[{"name":"test","status":"completed","conclusion":"success"}]'
    run_classifier
    [ "$status" -eq 0 ]
    [[ "$output" == *'"classification":"executed-success"'* ]]
}

@test "token-like annotation content is never copied to output" {
    write_bundle completed '"failure"' 0 '[]'
    jq '.annotations=[{"message":"token=do-not-print"}]' "$INPUT" >"${INPUT}.new" && mv "${INPUT}.new" "$INPUT"
    run_classifier
    [ "$status" -eq 1 ]
    [[ "$output" != *'do-not-print'* ]]
}

@test "unrelated executed job cannot satisfy an unallocated required job" {
    write_bundle completed '"success"' 0 '[]'
    jq '.jobs += [{"id":999,"name":"Lint","runner_id":12,"status":"completed","conclusion":"success","steps":[{"name":"lint","status":"completed","conclusion":"success"}]}]' "$INPUT" >"${INPUT}.new" && mv "${INPUT}.new" "$INPUT"
    run_classifier
    [ "$status" -eq 2 ]
    [[ "$output" == *'"classification":"indeterminate"'* ]]
}

@test "caller cannot redefine success as failure" {
    write_bundle completed '"failure"' 12 '[{"name":"test","status":"completed","conclusion":"failure"}]'
    run "$SCRIPT" --repo owner/repo --run-id 123 --workflow CI --required-job Test \
        --expected-sha "$SHA" --required-conclusion failure --format json
    [ "$status" -eq 2 ]
    [[ "$output" == *'"classification":"indeterminate"'* ]]
}

@test "missing live run id is an invocation error" {
    write_bundle completed '"success"' 12 '[{"name":"test","status":"completed","conclusion":"success"}]'
    run "$SCRIPT" --repo owner/repo --workflow CI \
        --required-job Test --expected-sha "$SHA"
    [ "$status" -eq 2 ]
    [[ "$output" == *'indeterminate'* ]]
}
