#!/usr/bin/env bats
# Project-only replacement for the retired global symlink installer contract.
load 'helpers/project_install'
setup() { setup_project_fixture; }

@test "explicit project installation never writes global agent discovery" {
    install_project
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/.datarim-runtime/installation.json" ]
    [ -f "$PROJECT/AGENTS.md" ]
    [ ! -L "$PROJECT/AGENTS.md" ]
    [ ! -e "$PROJECT/CLAUDE.md" ]
    [ ! -e "$HOME/.claude" ]
    [ ! -e "$HOME/.codex" ]
    [ ! -e "$HOME/.cursor" ]
}

@test "unchanged project install is idempotent" {
    install_project
    [ "$status" -eq 0 ]
    install_project
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "unchanged"'* ]]
    [ ! -e "$PROJECT/.datarim-runtime-previous" ]
}

@test "foreign AGENTS instructions survive a single managed block" {
    printf '# Project\nPreserve operator policy.\n' > "$PROJECT/AGENTS.md"
    install_project
    [ "$status" -eq 0 ]
    run grep -c 'datarim-project:begin' "$PROJECT/AGENTS.md"
    [ "$output" = 1 ]
    run grep -F 'Preserve operator policy.' "$PROJECT/AGENTS.md"
    [ "$status" -eq 0 ]
}

@test "project initialization creates only local task state" {
    install_project --init
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/datarim/tasks.md" ]
    [ -f "$PROJECT/datarim/backlog.md" ]
    [ ! -e "$HOME/datarim" ]
}

@test "Jev registers all native vendor schemas and a private empty key" {
    install_project --with-jev
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

@test "foreign discovery collision fails without partial AGENTS installation" {
    mkdir -p "$PROJECT/.agents/skills/testing"
    printf 'foreign skill' > "$PROJECT/.agents/skills/testing/SKILL.md"
    install_project
    [ "$status" -eq 2 ]
    [ ! -e "$PROJECT/AGENTS.md" ]
    [ ! -e "$PROJECT/.datarim-runtime" ]
    run cat "$PROJECT/.agents/skills/testing/SKILL.md"
    [ "$output" = 'foreign skill' ]
}

@test "uninstall restores original instructions and preserves key and task state" {
    printf '# Original rules\n' > "$PROJECT/AGENTS.md"
    install_project --with-jev --init
    [ "$status" -eq 0 ]
    install_project --uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT/.datarim-runtime" ]
    [ -d "$PROJECT/.datarim-uninstalled" ]
    [ -f "$PROJECT/datarim/tasks.md" ]
    [ -f "$PROJECT/config/credentials/jev/api-key" ]
    run cat "$PROJECT/AGENTS.md"
    [ "$output" = '# Original rules' ]
    run grep -F '/config/credentials/' "$PROJECT/.gitignore"
    [ "$status" -eq 0 ]
}

@test "uninstall refuses to overwrite a subsequent operator edit" {
    install_project
    [ "$status" -eq 0 ]
    printf '\nOperator addition\n' >> "$PROJECT/AGENTS.md"
    install_project --uninstall
    [ "$status" -eq 2 ]
    [ -d "$PROJECT/.datarim-runtime" ]
    run grep -F 'Operator addition' "$PROJECT/AGENTS.md"
    [ "$status" -eq 0 ]
}
