#!/usr/bin/env bats
# Regression coverage for dev-tools/reflection-freshness.sh (TUNE-0373 WS4).
# Four-branch freshness decision + emit-basis + determinism + mandatory-gate.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/reflection-freshness.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/datarim/reflection" "$TMP/datarim/reports"
    TASK="QCK-0001"
    REPORT="$TMP/datarim/reports/compliance-report-$TASK.md"
    REFLECTION="$TMP/datarim/reflection/reflection-$TASK.md"
    printf 'verdict: COMPLIANT\nbody of the compliance report\n' > "$REPORT"
}

teardown() { rm -rf "$TMP"; }

# Helper: write a reflection file with a given basis value (empty = no field).
write_reflection() {
    local basis="$1"
    {
        echo "---"
        echo "task_id: $TASK"
        [ -n "$basis" ] && echo "reflection_basis: \"$basis\""
        echo "---"
        echo "# Reflection body"
    } > "$REFLECTION"
}

@test "emit-basis prints a 16-hex prefix and exits 0" {
    run "$SCRIPT" --emit-basis "$REPORT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{16}$ ]]
}

@test "branch 1: reflection file absent -> regenerate (exit 1)" {
    run "$SCRIPT" --task "$TASK" --root "$TMP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"reflection file absent"* ]]
}

@test "branch 2: reflection present but reflection_basis field absent -> regenerate (exit 1)" {
    write_reflection ""
    run "$SCRIPT" --task "$TASK" --root "$TMP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"reflection_basis field absent"* ]]
}

@test "branch 2 is a distinct path from branch 1 (mandatory-gate guarantee)" {
    # Both regenerate, but the messages differ — proving distinct code paths.
    run "$SCRIPT" --task "$TASK" --root "$TMP"          # branch 1
    msg1="$output"
    write_reflection ""
    run "$SCRIPT" --task "$TASK" --root "$TMP"          # branch 2
    [ "$msg1" != "$output" ]
}

@test "branch 3: basis matches current report -> reuse (exit 0)" {
    basis="$("$SCRIPT" --emit-basis "$REPORT")"
    write_reflection "$basis"
    run "$SCRIPT" --task "$TASK" --root "$TMP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reuse"* ]]
}

@test "branch 4: basis mismatches current report -> regenerate (exit 1)" {
    write_reflection "deadbeefdeadbeef"
    run "$SCRIPT" --task "$TASK" --root "$TMP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"stale"* ]]
}

@test "stale on subsequent compliance edit: basis stamped, then report changes -> regenerate" {
    basis="$("$SCRIPT" --emit-basis "$REPORT")"
    write_reflection "$basis"
    # Simulate a later plan/do/qa cycle that produced a NEW compliance report.
    printf 'verdict: COMPLIANT\nDIFFERENT body after a re-run\n' > "$REPORT"
    run "$SCRIPT" --task "$TASK" --root "$TMP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"stale"* ]]
}

@test "determinism: same report content yields identical basis across invocations" {
    a="$("$SCRIPT" --emit-basis "$REPORT")"
    b="$("$SCRIPT" --emit-basis "$REPORT")"
    [ "$a" = "$b" ]
}

@test "missing compliance report -> regenerate (cannot confirm freshness)" {
    write_reflection "deadbeefdeadbeef"
    rm -f "$REPORT"
    run "$SCRIPT" --task "$TASK" --root "$TMP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"compliance report absent"* ]]
}

@test "invalid task id is rejected (exit 2, Security S1)" {
    run "$SCRIPT" --task "../etc/passwd" --root "$TMP"
    [ "$status" -eq 2 ]
}

@test "missing required args -> usage error (exit 2)" {
    run "$SCRIPT" --task "$TASK"
    [ "$status" -eq 2 ]
}
