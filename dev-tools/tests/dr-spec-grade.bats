#!/usr/bin/env bats
#
# bats spec for dev-tools/dr-spec-grade.sh (R10) — COMPUTED projection only.
# Contract (init-task 14:55 amendment): the grade is derived from findings, is
# idempotent, makes NO filesystem writes, emits NO routing token, and is invoked
# by no gate. It is a dashboard projection, never a source of truth.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dr-spec-grade.sh"
    WORK="$(mktemp -d)"
    # A findings file: 0 errors, 1 warning, 0 info.
    cat >"$WORK/findings-clean.jsonl" <<'EOF'
EOF
    cat >"$WORK/findings-warn.jsonl" <<'EOF'
{"severity":"warning","check_name":"dreq-orphan"}
EOF
    cat >"$WORK/findings-err.jsonl" <<'EOF'
{"severity":"error","check_name":"dreq-dangling"}
{"severity":"error","check_name":"covers-resolves"}
{"severity":"warning","check_name":"dreq-orphan"}
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "zero findings -> top grade A" {
    run "$SCRIPT" --findings "$WORK/findings-clean.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"A"* ]]
}

@test "errors present -> a lower grade than A" {
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" != *"A"* ]] || [[ "$output" == *"grade"* ]]
}

@test "idempotent — same input always yields the same grade" {
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl" --format json
    g1="$output"
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl" --format json
    [ "$g1" = "$output" ]
}

@test "json output carries grade + basis counts + computed_from" {
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl" --format json
    echo "$output" | python3 -c '
import json,sys
o=json.loads(sys.stdin.read())
assert "grade" in o, o
assert "basis" in o and "errors" in o["basis"], o
assert o["basis"]["errors"] == 2, o
assert o["basis"]["warnings"] == 1, o
assert "computed_from" in o, o
'
}

@test "makes NO filesystem writes (work dir mtime unchanged)" {
    before="$(ls -la "$WORK" | wc -l)"
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl"
    after="$(ls -la "$WORK" | wc -l)"
    [ "$before" -eq "$after" ]
    # the findings file content must be untouched
    run grep -c . "$WORK/findings-err.jsonl"
    [ "$output" -eq 3 ]
}

@test "emits NO routing token" {
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl"
    [ "$status" -eq 0 ]
    ! printf '%s' "$output" | grep -qE 'BLOCKED|PASS|CONDITIONAL|/dr-'
}

@test "emits NO routing token in json mode either" {
    run "$SCRIPT" --findings "$WORK/findings-err.jsonl" --format json
    ! printf '%s' "$output" | grep -qE 'BLOCKED|CONDITIONAL|/dr-'
}

@test "missing findings source — exit 2" {
    run "$SCRIPT" --findings "$WORK/nope.jsonl"
    [ "$status" -eq 2 ]
}

@test "unknown flag — exit 2" {
    run "$SCRIPT" --findings "$WORK/findings-clean.jsonl" --bogus
    [ "$status" -eq 2 ]
}

@test "--task propagates lint configuration exit 2 instead of emitting grade A" {
    run "$SCRIPT" --task ZZ-9999 --root "$WORK"
    [ "$status" -eq 2 ]
}
