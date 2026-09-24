#!/usr/bin/env bats
load 'helpers/project_install'
setup() { setup_project_fixture; }

@test "update requires explicit project scope" {
    run sh "$PRODUCT_ROOT/update.sh"
    [ "$status" -eq 2 ]
    [ ! -e "$HOME/.claude" ]
}

@test "unchanged update preserves the pinned runtime" {
    install_project --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "unchanged"'* ]]
}

@test "enabling then disabling project Jev (--without-jev) retires only owned hooks" {
    mkdir -p "$PROJECT/.cursor"
    printf '%s\n' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"foreign-guard"}]}}' > "$PROJECT/.cursor/hooks.json"
    install_project --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --with-jev
    [ "$status" -eq 0 ]
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --without-jev
    [ "$status" -eq 0 ]
    run python3 - "$PROJECT/.cursor/hooks.json" <<'CHECK'
import json,sys
h=json.load(open(sys.argv[1]))['hooks']
assert h['beforeShellExecution']==[{'command':'foreign-guard'}]
assert not any('jev_hook.py' in json.dumps(v) for v in h.values())
CHECK
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/config/credentials/jev/api-key" ]
    [ -d "$PROJECT/.datarim-runtime-backups" ]
}

@test "an update without --with-jev keeps the project's Jev hooks" {
    install_project --client all --permissions ask --with-jev
    [ "$status" -eq 0 ]
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT"
    [ "$status" -eq 0 ]
    run python3 - "$PROJECT" <<'CHECK'
import json,sys,pathlib
root=pathlib.Path(sys.argv[1])
assert json.loads((root/'.datarim-runtime/installation.json').read_text())['with_jev'] is True
for name in ('.claude/settings.local.json','.codex/hooks.json','.cursor/hooks.json'):
    assert 'jev_hook.py' in (root/name).read_text(), name
CHECK
    [ "$status" -eq 0 ]
}
