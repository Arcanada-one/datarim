#!/usr/bin/env bats
# Project-only replacement for the retired global symlink installer contract.
load 'helpers/project_install'
setup() { setup_project_fixture; }

@test "explicit project installation never writes global agent discovery" {
    install_answered --client all --permissions ask --without-jev
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
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "unchanged"'* ]]
    [ ! -e "$PROJECT/.datarim-runtime-previous" ]
}

@test "the project's AGENTS.md is never modified" {
    printf '# Project\nPreserve operator policy.\n' > "$PROJECT/AGENTS.md"
    cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    install_answered --client all --permissions ask --with-jev --init
    [ "$status" -eq 0 ]
    cmp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    run grep -c 'datarim-project:begin' "$PROJECT/AGENTS.md"
    [ "$output" = 0 ]
}

@test "team-neutral install exposes only scoped configuration and local extensions" {
    git -C "$PROJECT" init -q
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    git -C "$PROJECT" add AGENTS.md
    git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -qm init
    install_answered --client all --permissions ask --without-jev --team-neutral --init
    [ "$status" -eq 0 ]
    [ "$(cat "$PROJECT/AGENTS.md")" = '# Team instructions' ]
    [ -f "$PROJECT/datarim/AGENTS.md" ]
    [ -f "$PROJECT/datarim/config.yaml" ]
    [ -f "$PROJECT/datarim/local/manifest.json" ]
    run git -C "$PROJECT" status --porcelain --untracked-files=all
    [ "$status" -eq 0 ]
    [[ "$output" == *'datarim/AGENTS.md'* ]]
    [[ "$output" == *'datarim/config.yaml'* ]]
    [[ "$output" == *'datarim/local/manifest.json'* ]]
    [[ "$output" != *'datarim/tasks.md'* ]]
    [[ "$output" != *'datarim/backlog.md'* ]]
    [[ "$output" != *'.datarim-runtime/'* ]]
    printf '\ndelivery:\n  reports: reports/{task_id}\n' >> "$PROJECT/datarim/config.yaml"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    run grep -F 'reports: reports/{task_id}' "$PROJECT/datarim/config.yaml"
    [ "$status" -eq 0 ]
}

@test "team-neutral legacy update refuses before editing a managed root AGENTS.md" {
    git -C "$PROJECT" init -q
    printf '/datarim/*\n!/datarim/AGENTS.md\n!/datarim/config.yaml\n!/datarim/local/\n' > "$PROJECT/.gitignore"
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    cp "$PROJECT/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude.before"
    : > "$PROJECT/.git/info/exclude"
    run python3 - "$PROJECT" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
original = (root / 'AGENTS.md').read_text()
managed = original + '\n<!-- datarim-project:begin -->\nLegacy managed instructions\n<!-- datarim-project:end -->\n'
(root / 'AGENTS.md').write_text(managed)
runtime = root / '.datarim-runtime'
manifest = runtime / 'installation.json'
data = json.loads(manifest.read_text())
data['files']['AGENTS.md'] = hashlib.sha256(managed.encode()).hexdigest()
manifest.write_text(json.dumps(data) + '\n')
originals = runtime / 'original-files.json'
data = json.loads(originals.read_text())
data['AGENTS.md'] = original
originals.write_text(json.dumps(data) + '\n')
PY
    [ "$status" -eq 0 ]
    cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    cp "$PROJECT/.datarim-runtime/installation.json" "$BATS_TEST_TMPDIR/installation.before"
    local agents_before_meta
    agents_before_meta="$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$PROJECT/AGENTS.md")"
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    if [ "$status" -ne 2 ]; then
        if cmp -s "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"; then
            echo "legacy update returned $status; root AGENTS.md unchanged" >&3
        else
            echo "legacy update returned $status; root AGENTS.md changed" >&3
        fi
    fi
    [ "$status" -eq 2 ]
    [[ "$output" == *'root AGENTS.md'* ]]
    cmp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    [ "$agents_before_meta" = "$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$PROJECT/AGENTS.md")" ]
    cmp "$PROJECT/.datarim-runtime/installation.json" "$BATS_TEST_TMPDIR/installation.before"
    [ ! -e "$PROJECT/datarim/AGENTS.md" ]
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 2 ]
    cmp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    cp "$BATS_TEST_TMPDIR/exclude.before" "$PROJECT/.git/info/exclude"
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.cleaned"
    agents_before_meta="$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$PROJECT/AGENTS.md")"
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 0 ]
    cmp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.cleaned"
    [ "$agents_before_meta" = "$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$PROJECT/AGENTS.md")" ]
    run python3 - "$PROJECT" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = json.loads((root / '.datarim-runtime/installation.json').read_text())
originals = json.loads((root / '.datarim-runtime/original-files.json').read_text())
assert manifest['team_neutral'] is True
assert 'AGENTS.md' not in manifest['files']
assert 'AGENTS.md' not in originals
PY
    [ "$status" -eq 0 ]
    run git -C "$PROJECT" check-ignore --no-index -- datarim/AGENTS.md
    [ "$status" -eq 1 ]
}

@test "team-neutral update preserves a legacy owned root CLAUDE.md link" {
    git -C "$PROJECT" init -q
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    : > "$PROJECT/.git/info/exclude"
    ln -s AGENTS.md "$PROJECT/CLAUDE.md"
    run python3 - "$PROJECT" <<'PY'
import json, sys
from pathlib import Path
manifest = Path(sys.argv[1]) / '.datarim-runtime/installation.json'
data = json.loads(manifest.read_text())
data['claude_md_link'] = True
manifest.write_text(json.dumps(data) + '\n')
PY
    [ "$status" -eq 0 ]
    install_answered --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 2 ]
    [[ "$output" == *'root CLAUDE.md'* ]]
    [ -L "$PROJECT/CLAUDE.md" ]
    [ ! -e "$PROJECT/datarim/AGENTS.md" ]
}

@test "team-neutral update replaces its own legacy Git exclude block without root instruction edits" {
    git -C "$PROJECT" init -q
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    cp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    if [ "$status" -ne 0 ]; then
        echo "legacy update returned $status: $output" >&3
    fi
    [ "$status" -eq 0 ]
    cmp "$PROJECT/AGENTS.md" "$BATS_TEST_TMPDIR/agents.before"
    [ -f "$PROJECT/datarim/AGENTS.md" ]
    run git -C "$PROJECT" check-ignore --no-index -- datarim/AGENTS.md
    [ "$status" -eq 1 ]
}

@test "team-neutral legacy update refuses a modified managed Git exclude block" {
    git -C "$PROJECT" init -q
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    sed -i '/^# datarim-project:end/i /project-private/' "$PROJECT/.git/info/exclude"
    cp "$PROJECT/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude.before"
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 2 ]
    cmp "$PROJECT/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude.before"
    [ ! -e "$PROJECT/datarim/AGENTS.md" ]
}

@test "team-neutral legacy update detects a global ignore masked by its old local rule" {
    git -C "$PROJECT" init -q
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    printf '/datarim/\n' > "$BATS_TEST_TMPDIR/global-ignore"
    git -C "$PROJECT" config core.excludesFile "$BATS_TEST_TMPDIR/global-ignore"
    cp "$PROJECT/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude.before"
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 2 ]
    [[ "$output" == *'Git ignore rules hide team-neutral path'* ]]
    cmp "$PROJECT/.git/info/exclude" "$BATS_TEST_TMPDIR/exclude.before"
    [ ! -e "$PROJECT/datarim/AGENTS.md" ]
}

@test "team-neutral legacy update preserves a preceding nested Git exclude block" {
    git -C "$PROJECT" init -q
    printf '# Team instructions\n' > "$PROJECT/AGENTS.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    cp "$PROJECT/.git/info/exclude" "$BATS_TEST_TMPDIR/root-exclude"
    printf '# datarim-project:begin /nested/\n/nested/private/\n# datarim-project:end /nested/\n' > "$PROJECT/.git/info/exclude"
    cat "$BATS_TEST_TMPDIR/root-exclude" >> "$PROJECT/.git/info/exclude"
    run sh "$PRODUCT_ROOT/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev --team-neutral
    if [ "$status" -ne 0 ]; then echo "nested legacy update returned $status: $output" >&3; fi
    [ "$status" -eq 0 ]
    run grep -Fx '# datarim-project:begin /nested/' "$PROJECT/.git/info/exclude"
    [ "$status" -eq 0 ]
    run grep -Fx '/nested/private/' "$PROJECT/.git/info/exclude"
    [ "$status" -eq 0 ]
    run grep -Fx '# datarim-project:end /nested/' "$PROJECT/.git/info/exclude"
    [ "$status" -eq 0 ]
}

@test "team-neutral install refuses project ignore rules and tracked private state" {
    git -C "$PROJECT" init -q
    printf '/datarim/\n' > "$PROJECT/.gitignore"
    git -C "$PROJECT" add .gitignore
    git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -qm init
    install_answered --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 2 ]
    [[ "$output" == *'Git ignore rules hide team-neutral path'* ]]
    [ ! -e "$PROJECT/.datarim-runtime" ]
    printf '' > "$PROJECT/.gitignore"
    mkdir -p "$PROJECT/datarim"
    printf 'private task\n' > "$PROJECT/datarim/tasks.md"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -qm tracked
    install_answered --client all --permissions ask --without-jev --team-neutral
    [ "$status" -eq 2 ]
    [[ "$output" == *'Tracked private Datarim paths'* ]]
    [ ! -e "$PROJECT/.datarim-runtime" ]
}

@test "team-neutral install accepts explicit project unignore rules" {
    git -C "$PROJECT" init -q
    printf '/datarim/*\n!/datarim/AGENTS.md\n!/datarim/config.yaml\n!/datarim/local/\n' > "$PROJECT/.gitignore"
    git -C "$PROJECT" add .gitignore
    git -C "$PROJECT" -c user.email=t@t -c user.name=t commit -qm init
    install_answered --client all --permissions ask --without-jev --team-neutral --init
    [ "$status" -eq 0 ]
    run git -C "$PROJECT" status --porcelain --untracked-files=all
    [[ "$output" == *'datarim/AGENTS.md'* ]]
    [[ "$output" == *'datarim/config.yaml'* ]]
    [[ "$output" == *'datarim/local/manifest.json'* ]]
}

@test "project initialization creates only local task state" {
    install_answered --client all --permissions ask --without-jev --init
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/datarim/tasks.md" ]
    [ -f "$PROJECT/datarim/backlog.md" ]
    [ ! -e "$HOME/datarim" ]
}

@test "Jev registers all native vendor schemas and a private empty key" {
    install_answered --client all --permissions ask --with-jev
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
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 2 ]
    [ ! -e "$PROJECT/.claude/commands/dr-do.md" ]
    [ ! -e "$PROJECT/.datarim-runtime" ]
    run cat "$PROJECT/.agents/skills/dr-do/SKILL.md"
    [ "$output" = 'foreign skill' ]
}

@test "uninstall restores original instructions and preserves key and task state" {
    printf '# Original rules\n' > "$PROJECT/AGENTS.md"
    install_answered --client all --permissions ask --with-jev --init
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
    install_answered --client all --permissions ask --without-jev
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
    install_answered --client all --permissions ask --without-jev
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
    install_answered --client all --permissions ask --with-jev --init
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
    install_answered --client all --permissions ask --without-jev
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
    [[ "$output" == *'--permissions full'* ]]
    [ -z "$(ls -A "$PROJECT")" ]
}

@test "a dry run without a Jev choice is refused too and prints no plan" {
    run sh -c 'sh "$1" --project "$2" --init --dry-run 2>/dev/null' _ "$PRODUCT_ROOT/install.sh" "$PROJECT"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" --init --dry-run
    [[ "$output" == *"Rerun with the user's answers: ./install.sh --project"*'--answers '* ]]
    [[ "$output" == *'--expose-skills'* ]]
    [ ! -e "$PROJECT/.datarim-runtime" ]
}

@test "a Jev install prints where the key goes and how to write it" {
    install_project --client all --permissions ask --with-jev
    token="$(answers_token "$output")"
    [ -n "$token" ]
    run sh -c 'sh "$1" --project "$2" --answers "$3" --client all --permissions ask --with-jev 2>&1 >/dev/null' \
        _ "$PRODUCT_ROOT/install.sh" "$PROJECT" "$token"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Copy the block below into your reply to the user unchanged (you may add your own text after it):'* ]]
    [[ "$output" == *'key (optional): '*'config/credentials/jev/api-key; the Jev floor works without it; paste it with an editor, never with echo/printf'* ]]
    [[ "$output" == *'never in .zshrc/.bashrc: JEV_* or DATARIM_* variables (e.g. JEV_PERMISSIONS) or the key; set them per shell or per launch'* ]]
    [[ "$output" == *'permission mode: ask — '*'/.datarim-runtime/state/jev/FULL_PERMISSIONS (present = full, absent = ask;'* ]]
    [[ "$output" == *'.agents/skills/dr-* and .cursor/skills/dr-* are the /dr-* commands packaged for Codex/Cursor, not extra framework skills'* ]]
    [[ "$output" == *'Codex: open `codex` once in this project and accept the hooks, or run `jev trust`'* ]]
}

@test "a Jev answer without a client list is refused and writes nothing" {
    install_project --without-jev
    [ "$status" -eq 2 ]
    [[ "$output" == 'STOP. Nothing was installed.'* ]]
    [ -z "$(ls -A "$PROJECT")" ]
}

@test "full answer flags still need the printed answers token, and no switch skips it" {
    git init -q "$PROJECT"
    DATARIM_INSTALL_NONINTERACTIVE=1 install_project --without-jev --client codex --permissions ask
    [ "$status" -eq 2 ]
    [[ "$output" == 'STOP. Nothing was installed.'* ]]
    [[ "$output" == *"Ignored (not yet the user's answers): --client codex --without-jev --permissions ask"* ]]
    [[ "$output" == *'a new token replaces any earlier one'* ]]
    token="$(answers_token "$output")"
    [ -n "$token" ]
    [ "$(ls -A "$PROJECT")" = ".git" ]
    install_project --answers "$token" --without-jev --client codex --permissions ask
    [ "$status" -eq 0 ]
    [[ "$output" == *'permission mode: ask — '*'change with `jev permissions full|ask`)'* ]]
    [[ "$output" != *'Codex: open'* ]]
    [ -f "$PROJECT/.datarim-runtime/installation.json" ]
    [ ! -e "$PROJECT/.git/datarim-install-answers" ]
}

@test "the refusal never offers a CLAUDE.md link, with or without an AGENTS.md" {
    install_project --without-jev --client claude --permissions ask
    [ "$status" -eq 2 ]
    [[ "$output" != *'CLAUDE.md'* ]]
    [[ "$output" != *'claude-import'* ]]
    printf '# Rules\n' > "$PROJECT/AGENTS.md"
    install_project --without-jev --client claude --permissions ask
    [[ "$output" != *'CLAUDE.md'* ]]
    [[ "$output" != *'claude-import'* ]]
}

@test "the retired --claude-import flag is accepted with a notice and never creates CLAUDE.md" {
    printf '# Rules\n' > "$PROJECT/AGENTS.md"
    install_answered --client claude --permissions ask --without-jev --claude-import
    [ "$status" -eq 0 ]
    [[ "$output" == *'Deprecated: --claude-import'* ]]
    [ ! -e "$PROJECT/CLAUDE.md" ]
    [ ! -L "$PROJECT/CLAUDE.md" ]
}
