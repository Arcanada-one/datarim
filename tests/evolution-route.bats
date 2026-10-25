#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/evolution-route.py"
    ROOT="$BATS_TEST_TMPDIR/workspace"
    mkdir -p "$ROOT/datarim/config" "$ROOT/scripts" "$ROOT/skills/evolution"
    git -C "$ROOT" init -q
}

@test "consumer workspace defaults to automatic local evolution" {
    run python3 "$SCRIPT" --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"scope": "consumer", "auto_apply": true}' ]
}

@test "framework source requires exact root remote and markers" {
    git -C "$ROOT" remote add origin https://github.com/Arcanada-one/datarim.git
    touch "$ROOT/scripts/project_install.py" "$ROOT/skills/evolution/SKILL.md" "$ROOT/VERSION"
    run python3 "$SCRIPT" --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"scope": "framework", "auto_apply": true}' ]
}

@test "consumer opt-out disables automatic application" {
    printf 'auto_apply: false\n' > "$ROOT/datarim/config/evolution.yaml"
    run python3 "$SCRIPT" --root "$ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"scope": "consumer", "auto_apply": false}' ]
}

@test "malformed opt-out fails closed" {
    printf 'auto_apply: maybe\n' > "$ROOT/datarim/config/evolution.yaml"
    run python3 "$SCRIPT" --root "$ROOT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"EVOLUTION_ROUTE_ERROR"* ]]
}
