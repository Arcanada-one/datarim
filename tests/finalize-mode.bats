#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/resolve-finalize-mode.py"
    ROOT="$BATS_TEST_TMPDIR/project"
    CONFIG="$BATS_TEST_TMPDIR/user/datarim/config.yaml"
    mkdir -p "$ROOT/datarim/tasks" "$(dirname "$CONFIG")"
    TASK="QCK-0001"
    printf '%s\n' '---' 'finalize_requested: true' '---' > "$ROOT/datarim/tasks/$TASK-init-task.md"
}

@test "default off blocks even an explicit task request" {
    run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT" --task-id "$TASK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mode": "off", "source": "default"'* ]]
    [[ "$output" == *'"run": false'* ]]
}

@test "user on_request runs only a recorded task request" {
    printf 'autonomy:\n  finalize: on_request\n' > "$CONFIG"
    run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT" --task-id "$TASK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"source": "user"'* ]]
    [[ "$output" == *'"run": true'* ]]
    run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT"
    [[ "$output" == *'"run": false'* ]]
}

@test "project always overrides user on_request" {
    printf 'autonomy:\n  finalize: on_request\n' > "$CONFIG"
    printf 'autonomy:\n  finalize: always\n' > "$ROOT/datarim/config.yaml"
    run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mode": "always", "source": "project"'* ]]
    [[ "$output" == *'"run": true'* ]]
}

@test "project off overrides user always and task request" {
    printf 'autonomy:\n  finalize: always\n' > "$CONFIG"
    printf 'autonomy:\n  finalize: off\n' > "$ROOT/datarim/config.yaml"
    run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT" --task-id "$TASK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mode": "off", "source": "project"'* ]]
    [[ "$output" == *'"run": false'* ]]
}

@test "invalid project setting refuses to fall through to user setting" {
    printf 'autonomy:\n  finalize: maybe\n' > "$ROOT/datarim/config.yaml"
    printf 'autonomy:\n  finalize: always\n' > "$CONFIG"
    run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT"
    [ "$status" -eq 2 ]
    [[ "$output" == *'FINALIZE_MODE_ERROR'* ]]
}

@test "both autonomous entry points route each effective setting through finalize resolver" {
    for command in dr-auto dr-orchestrate; do
        grep -F 'resolve-finalize-mode.py' "$BATS_TEST_DIRNAME/../commands/$command.md"
        grep -F '/dr-finalize' "$BATS_TEST_DIRNAME/../commands/$command.md"
    done
    for mode in off on_request always; do
        printf 'autonomy:\n  finalize: %s\n' "$mode" > "$ROOT/datarim/config.yaml"
        run env XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/user" python3 "$SCRIPT" --root "$ROOT" --task-id "$TASK"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"mode": '"\"$mode\""* ]]
    done
}
