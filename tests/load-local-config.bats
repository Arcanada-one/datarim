#!/usr/bin/env bats
# load-local-config.bats — contract tests for cli/lib/load-local-config.sh.
# Four contracts: missing file, injection guard, bad key skip, valid export.

setup() {
    LOADER="${BATS_TEST_DIRNAME}/../cli/lib/load-local-config.sh"
    TMP_DIR="$(mktemp -d)"
    export DATARIM_LOCAL="$TMP_DIR"
}

teardown() {
    rm -rf "$TMP_DIR"
    rm -f /tmp/pwned
}

@test "no env file present → exit 0 silently" {
    # config dir does not exist yet
    run bash -c "source '$LOADER'; load_local_config 2>&1; echo exit:\$?"
    [ "$status" -eq 0 ]
    [[ "$output" == *"exit:0"* ]]
}

@test "injection attempt X=\$(touch /tmp/pwned) → treated as literal, not executed" {
    mkdir -p "$TMP_DIR/config"
    printf 'X=$(touch /tmp/pwned)\n' > "$TMP_DIR/config/personal.env"
    run bash -c "source '$LOADER'; load_local_config; echo VAR:\"\$X\""
    [ "$status" -eq 0 ]
    # The variable should be the literal string, NOT the result of command
    [[ "$output" == *'VAR:$(touch /tmp/pwned)'* ]]
    # The file must NOT have been created
    [ ! -f /tmp/pwned ]
}

@test "bad key (starts with digit: 1bad=x) → skipped, not exported" {
    mkdir -p "$TMP_DIR/config"
    printf '1bad=val\n' > "$TMP_DIR/config/personal.env"
    run bash -c "source '$LOADER'; load_local_config; env | grep -c '^1bad=' || echo 0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]]
}

@test "valid key MY_KEY=my_val → exported into environment" {
    mkdir -p "$TMP_DIR/config"
    printf 'MY_KEY=my_val\n' > "$TMP_DIR/config/personal.env"
    run bash -c "source '$LOADER'; load_local_config; echo \"RESULT:\$MY_KEY\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT:my_val"* ]]
}
