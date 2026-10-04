#!/usr/bin/env bats
# output-envelope.bats — V-AC верификация foundation output contract.
# Source: creative-TUNE-0268-architecture-subcommand-output-shape.md § IP-7
#         + foundation IP-3 exit code registry.

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LIB="$DATARIM_CLI_DIR/lib/output.sh"
    [[ -f "$LIB" ]] || skip "lib/output.sh not yet implemented"
}

@test "1: output_emit_json produces valid JSON parseable by jq -e" {
    export DATARIM_CLI_CMD='tasks list' OUTPUT_MODE=json
    run bash -c "source '$LIB' && output_emit_json '{\"tasks\":[]}'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
}

@test "2: envelope contains version, command, ts, data, error fields" {
    export DATARIM_CLI_CMD='status' OUTPUT_MODE=json
    run bash -c "source '$LIB' && output_emit_json '{\"hello\":\"world\"}'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.version == "1"' >/dev/null
    echo "$output" | jq -e '.command == "status"' >/dev/null
    echo "$output" | jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' >/dev/null
    echo "$output" | jq -e '.data.hello == "world"' >/dev/null
    echo "$output" | jq -e '.error == null' >/dev/null
}

@test "3: output_emit_error in JSON mode → envelope with non-null error.code/exit/message" {
    export DATARIM_CLI_CMD='config set' OUTPUT_MODE=json
    run bash -c "source '$LIB' && output_emit_error 20 AAL_LOCKED_KEY 'cannot set aal_class on AAL-3-locked workspace'"
    [ "$status" -eq 20 ]
    echo "$output" | jq -e '.error.code == "AAL_LOCKED_KEY"' >/dev/null
    echo "$output" | jq -e '.error.exit == 20' >/dev/null
    echo "$output" | jq -e '.error.message | test("AAL-3-locked")' >/dev/null
    echo "$output" | jq -e '.data == null' >/dev/null
}

@test "4: output_emit_error in plain mode → stderr text + exit code; stdout empty" {
    export DATARIM_CLI_CMD='backlog add' OUTPUT_MODE=plain
    tmp_out="$BATS_TMPDIR/o4_stdout"
    tmp_err="$BATS_TMPDIR/o4_stderr"
    set +e
    bash -c "source '$LIB' && output_emit_error 28 ID_COLLISION_DETECTED 'TUNE-0268 already exists in archive'" \
        >"$tmp_out" 2>"$tmp_err"
    rc=$?
    set -e
    [ "$rc" -eq 28 ]
    [ ! -s "$tmp_out" ]
    grep -q "ID_COLLISION_DETECTED" "$tmp_err"
    grep -q "TUNE-0268 already exists" "$tmp_err"
}

@test "5: output_emit_warn always writes to stderr regardless of mode (stdout untouched)" {
    export DATARIM_CLI_CMD='status' OUTPUT_MODE=json
    tmp_out="$BATS_TMPDIR/o5_stdout"
    tmp_err="$BATS_TMPDIR/o5_stderr"
    bash -c "source '$LIB' && output_emit_warn 'fixture timestamp out of date'" \
        >"$tmp_out" 2>"$tmp_err"
    [ ! -s "$tmp_out" ]
    grep -q "fixture timestamp out of date" "$tmp_err"
}

@test "6: ANSI strip + UTF-8: input with embedded ANSI → clean string" {
    export DATARIM_CLI_CMD='status' OUTPUT_MODE=json
    run bash -c "
        source '$LIB'
        text=\$(printf '\x1b[31mRED\x1b[0m  ПРИВЕТ  \x1b[32mGREEN\x1b[0m')
        clean=\$(output_strip_ansi \"\$text\")
        printf '%s' \"\$clean\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"RED  ПРИВЕТ  GREEN"* ]]
    [[ "$output" != *$'\x1b'* ]]
}

@test "7: exit-codes.sh sourced transitively; exit_code_of resolves symbolic names" {
    export DATARIM_CLI_CMD='x' OUTPUT_MODE=plain
    run bash -c "source '$LIB' && exit_code_of NOT_FOUND"
    [ "$status" -eq 0 ]
    [ "$output" = "31" ]
}
