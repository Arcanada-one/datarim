#!/usr/bin/env bats
# Project-only replacement for the retired global symlink installer contract.
load 'helpers/project_install'
setup() { setup_project_fixture; }

@test "explicit project installation never writes global agent discovery" {
    install_project --client all --without-jev
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/.datarim-runtime/installation.json" ]
    # Datarim writes nothing into files a project shares: no AGENTS.md is created.
    [ ! -e "$PROJECT/AGENTS.md" ]
    [ ! -e "$PROJECT/CLAUDE.md" ]
    [ ! -e "$HOME/.claude" ]
    [ ! -e "$HOME/.codex" ]
    [ ! -e "$HOME/.cursor" ]
}

@test "unchanged project install is idempotent" {
    install_project --client all --without-jev
    [ "$status" -eq 0 ]
    install_project --client all --without-jev
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "unchanged"'* ]]
    [ ! -e "$PROJECT/.datarim-runtime-previous" ]
}

@test "the project's AGENTS.md is never modified" {
    printf '# Project\nPreserve operator policy.\n' > "$PROJECT/AGENTS.md"
    cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    install_project --client all --with-jev --init
    [ "$status" -eq 0 ]
    cmp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    run grep -c 'datarim-project:begin' "$PROJECT/AGENTS.md"
    [ "$output" = 0 ]
}

@test "project initialization creates only local task state" {
    install_project --client all --without-jev --init
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/datarim/tasks.md" ]
    [ -f "$PROJECT/datarim/backlog.md" ]
    [ ! -e "$HOME/datarim" ]
}

@test "Jev registers all native vendor schemas and a private empty key" {
    install_project --client all --with-jev
    [ "$status" -eq 0 ]
    run python3 - "$PROJECT" <<'CHECK'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
assert 'PreToolUse' in json.loads((p/'.claude/settings.local.json').read_text())['hooks']
assert 'PreToolUse' in json.loads((p/'.codex/hooks.json').read_text())['hooks']
assert 'beforeShellExecution' in json.loads((p/'.cursor/hooks.json').read_text())['hooks']
k=p/'config/credentials/jev/api-key'
assert k.read_bytes()==b'' and k.stat().st_mode & 0o777 == 0o600
CHECK
    [ "$status" -eq 0 ]
}

@test "foreign discovery collision fails without partial installation" {
    mkdir -p "$PROJECT/.agents/skills/dr-do"
    printf 'foreign skill' > "$PROJECT/.agents/skills/dr-do/SKILL.md"
    install_project --client all --without-jev
    [ "$status" -eq 2 ]
    [ ! -e "$PROJECT/.claude/commands/dr-do.md" ]
    [ ! -e "$PROJECT/.datarim-runtime" ]
    run cat "$PROJECT/.agents/skills/dr-do/SKILL.md"
    [ "$output" = 'foreign skill' ]
}

@test "uninstall restores original instructions and preserves key and task state" {
    printf '# Original rules\n' > "$PROJECT/AGENTS.md"
    install_project --client all --with-jev --init
    [ "$status" -eq 0 ]
    install_project --uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT/.datarim-runtime" ]
    [ -d "$PROJECT/.datarim-uninstalled" ]
    [ -f "$PROJECT/datarim/tasks.md" ]
    [ -f "$PROJECT/config/credentials/jev/api-key" ]
    run cat "$PROJECT/AGENTS.md"
    [ "$output" = '# Original rules' ]
    [ ! -e "$PROJECT/.claude/commands/dr-do.md" ]
}

@test "uninstall refuses to overwrite a subsequent operator edit" {
    install_project --client all --without-jev
    [ "$status" -eq 0 ]
    printf '\nOperator addition\n' >> "$PROJECT/.claude/commands/dr-do.md"
    install_project --uninstall
    [ "$status" -eq 2 ]
    [ -d "$PROJECT/.datarim-runtime" ]
    run grep -F 'Operator addition' "$PROJECT/.claude/commands/dr-do.md"
    [ "$status" -eq 0 ]
}

@test "an operator's AGENTS.md edits survive install and uninstall" {
    printf '# Rules\n' > "$PROJECT/AGENTS.md"
    install_project --client all --without-jev
    [ "$status" -eq 0 ]
    printf 'Operator addition\n' >> "$PROJECT/AGENTS.md"
    install_project --uninstall
    [ "$status" -eq 0 ]
    run cat "$PROJECT/AGENTS.md"
    [ "$output" = $'# Rules\nOperator addition' ]
}

@test "in a git repository nothing the install writes appears in git status" {
    git -C "$PROJECT" init -q
    printf '# Team rules\n' > "$PROJECT/AGENTS.md"
    printf '/build/\n' > "$PROJECT/.gitignore"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -qm init
    install_project --client all --with-jev --init
    [ "$status" -eq 0 ]
    run git -C "$PROJECT" status --porcelain
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -f "$PROJECT/.codex/hooks.json" ]
    install_project --uninstall
    [ "$status" -eq 0 ]
    run git -C "$PROJECT" status --porcelain
    [ -z "$output" ]
}

@test "project runtime ships the receipt heartbeat helper and it runs from there" {
    # Ported intent of 96a350f: the 2.x copy installer filtered by extension
    # and dropped heartbeat-receipts.py. The project installer copies whole
    # scopes; this pins that the helper arrives intact and works in place.
    install_project --client all --without-jev
    [ "$status" -eq 0 ]
    local runtime="$PROJECT/.datarim-runtime" receipts task
    cmp "$PRODUCT_ROOT/dev-tools/lib/heartbeat-receipts.py" "$runtime/dev-tools/lib/heartbeat-receipts.py"
    # The helper refuses symlinked ancestors (macOS /var -> /private/var).
    mkdir -p "$BATS_TEST_TMPDIR/receipts" "$BATS_TEST_TMPDIR/task"
    receipts="$(cd "$BATS_TEST_TMPDIR/receipts" && pwd -P)"
    task="$(cd "$BATS_TEST_TMPDIR/task" && pwd -P)"
    run env DATARIM_INTERACTION_RUN_ID=11111111-1111-4111-8111-111111111111 \
        DATARIM_INTERACTION_RECEIPTS_DIR="$receipts" \
        bash "$runtime/dev-tools/lib/heartbeat-status.sh" write \
        --root "$task" --task-id EXA-0001 --state done
    [ "$status" -eq 0 ]
    run jq -e '.interaction_run_id == "11111111-1111-4111-8111-111111111111" and .interaction_receipts == []' \
        "$task/datarim/runtime/EXA-0001.status"
    [ "$status" -eq 0 ]
}

@test "a fresh install without a Jev choice refuses and names the questions" {
    install_project --init
    [ "$status" -eq 2 ]
    [[ "$output" == 'STOP. Nothing was installed.'* ]]
    [[ "$output" == *'Do not choose for them.'* ]]
    [[ "$output" == *'works WITHOUT any key'* ]]
    [[ "$output" == *'--client claude,codex,cursor'* ]]
    [[ "$output" == *'jev permissions full'* ]]
    [ -z "$(ls -A "$PROJECT")" ]
}

@test "a dry run without a Jev choice is refused too and prints no plan" {
    run sh -c 'sh "$1" --project "$2" --init --dry-run 2>/dev/null' _ "$PRODUCT_ROOT/install.sh" "$PROJECT"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" --init --dry-run
    [[ "$output" == *'Rerun: ./install.sh --project <path> <flags from the answers>'* ]]
    [[ "$output" == *'--expose-skills'* ]]
    [ ! -e "$PROJECT/.datarim-runtime" ]
}

@test "a Jev install prints where the key goes and how to write it" {
    run sh -c 'sh "$1" --project "$2" --client all --with-jev 2>&1 >/dev/null' _ "$PRODUCT_ROOT/install.sh" "$PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Jev key file: $PROJECT/config/credentials/jev/api-key"* || "$output" == *'config/credentials/jev/api-key'* ]]
    [[ "$output" == *'paste the key on one line'* ]]
    [[ "$output" == *'Do not echo/printf the key'* ]]
}

@test "a Jev answer without a client list is refused and writes nothing" {
    install_project --without-jev
    [ "$status" -eq 2 ]
    [[ "$output" == 'STOP. Nothing was installed.'* ]]
    [ -z "$(ls -A "$PROJECT")" ]
}
