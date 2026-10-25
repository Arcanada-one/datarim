#!/usr/bin/env bats
load 'helpers/project_install'
setup() { setup_project_fixture; }

register_file() {
    python3 "$PRODUCT_ROOT/scripts/local_overlay.py" add --project "$PROJECT" --source "$PRODUCT_ROOT" "$1"
}

@test "overlay command replaces upstream and appears in Claude Codex and Cursor adapters" {
    mkdir -p "$PROJECT/datarim/local/commands"
    printf '%s\n' '---' 'name: dr-do' 'description: Project workflow' '---' '# Local workflow' > "$PROJECT/datarim/local/commands/dr-do.md"
    register_file commands/dr-do.md
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    grep -F '# Local workflow' "$PROJECT/.datarim-runtime/commands/dr-do.md"
    grep -F '# Local workflow' "$PROJECT/.claude/commands/dr-do.md"
    grep -F '/commands/dr-do.md' "$PROJECT/.agents/skills/dr-do/SKILL.md"
    grep -F '/commands/dr-do.md' "$PROJECT/.cursor/skills/dr-do/SKILL.md"
}

@test "overlay bytes survive update and upstream base drift is reported" {
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    mkdir -p "$PROJECT/datarim/local/commands"
    cp "$PRODUCT_ROOT/commands/dr-do.md" "$PROJECT/datarim/local/commands/dr-do.md"
    printf '\n# Local change\n' >> "$PROJECT/datarim/local/commands/dr-do.md"
    register_file commands/dr-do.md
    cp "$PROJECT/datarim/local/commands/dr-do.md" "$BATS_TEST_TMPDIR/before"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/before" "$PROJECT/datarim/local/commands/dr-do.md"
    grep -F '# Local change' "$PROJECT/.datarim-runtime/commands/dr-do.md"
    run python3 "$PRODUCT_ROOT/scripts/local_overlay.py" status --project "$PROJECT" --source "$PRODUCT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"file_count": 1'* ]]
    python3 - "$PROJECT" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])/'datarim/local/manifest.json'
d=json.loads(p.read_text()); d['files']['commands/dr-do.md']='0'*64; p.write_text(json.dumps(d))
PY
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    [[ "$output" == *'overlay_upstream_base_changed'* ]]
    cmp "$BATS_TEST_TMPDIR/before" "$PROJECT/datarim/local/commands/dr-do.md"
}

@test "direct runtime edit refuses update and preserves edited byte" {
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    printf '\nlocal direct edit\n' >> "$PROJECT/.datarim-runtime/commands/dr-do.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 2 ]
    [[ "$output" == *'Locally modified installed runtime'* ]]
    grep -F 'local direct edit' "$PROJECT/.datarim-runtime/commands/dr-do.md"
}

@test "uninstall preserves project overlay" {
    mkdir -p "$PROJECT/datarim/local/commands"
    printf '# Local new command\n' > "$PROJECT/datarim/local/commands/dr-local.md"
    register_file commands/dr-local.md
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    install_project --uninstall
    [ "$status" -eq 0 ]
    grep -F '# Local new command' "$PROJECT/datarim/local/commands/dr-local.md"
    [ -f "$PROJECT/datarim/local/manifest.json" ]
}

@test "new overlay skill and command are discoverable by every selected client" {
    mkdir -p "$PROJECT/datarim/local/skills/project-skill" "$PROJECT/datarim/local/commands"
    printf '%s\n' '---' 'name: project-skill' 'description: Project-specific skill' '---' '# Project skill' > "$PROJECT/datarim/local/skills/project-skill/SKILL.md"
    printf '%s\n' '---' 'name: dr-project' 'description: Project-specific command' '---' '# Project command' > "$PROJECT/datarim/local/commands/dr-project.md"
    register_file skills/project-skill/SKILL.md
    register_file commands/dr-project.md
    install_answered --client all --permissions ask --without-jev --expose-skills
    [ "$status" -eq 0 ]
    for vendor in .agents .claude .cursor; do
        [ -f "$PROJECT/$vendor/skills/project-skill/SKILL.md" ]
        [ -f "$PROJECT/$vendor/skills/dr-project/SKILL.md" ] || [ -f "$PROJECT/$vendor/commands/dr-project.md" ]
    done
    grep -F '# Project command' "$PROJECT/.datarim-runtime/commands/dr-project.md"
}

@test "failed update rollback preserves overlay bytes and previous runtime" {
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    mkdir -p "$PROJECT/datarim/local/commands"
    printf '# Override\n' > "$PROJECT/datarim/local/commands/dr-do.md"
    register_file commands/dr-do.md
    cp "$PROJECT/datarim/local/commands/dr-do.md" "$BATS_TEST_TMPDIR/overlay-before"
    cp "$PROJECT/.datarim-runtime/commands/dr-do.md" "$BATS_TEST_TMPDIR/runtime-before"
    printf '\nforeign adapter edit\n' >> "$PROJECT/.claude/commands/dr-do.md"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 2 ]
    cmp "$BATS_TEST_TMPDIR/overlay-before" "$PROJECT/datarim/local/commands/dr-do.md"
    cmp "$BATS_TEST_TMPDIR/runtime-before" "$PROJECT/.datarim-runtime/commands/dr-do.md"
}

@test "autonomous consumer writer changes overlay only and leaves source clone bytes unchanged" {
    mkdir -p "$PROJECT/datarim" "$BATS_TEST_TMPDIR/source/commands"
    printf 'upstream\n' > "$BATS_TEST_TMPDIR/source/commands/dr-example.md"
    cp "$BATS_TEST_TMPDIR/source/commands/dr-example.md" "$BATS_TEST_TMPDIR/source-before"
    printf 'consumer proposal\n' > "$BATS_TEST_TMPDIR/proposal"
    run python3 "$PRODUCT_ROOT/dev-tools/evolution-write.py" --root "$PROJECT" \
        --source "$BATS_TEST_TMPDIR/source" --relative commands/dr-example.md \
        --input "$BATS_TEST_TMPDIR/proposal"
    [ "$status" -eq 0 ]
    cmp "$BATS_TEST_TMPDIR/source-before" "$BATS_TEST_TMPDIR/source/commands/dr-example.md"
    cmp "$BATS_TEST_TMPDIR/proposal" "$PROJECT/datarim/local/commands/dr-example.md"
    [ -f "$PROJECT/datarim/local/manifest.json" ]
}

@test "shared source install keeps per-project overrides isolated" {
    OTHER="$BATS_TEST_TMPDIR/other-project"
    mkdir -p "$OTHER" "$PROJECT/datarim/local/commands"
    printf '# Only this project\n' > "$PROJECT/datarim/local/commands/dr-do.md"
    register_file commands/dr-do.md
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    run sh "$PRODUCT_ROOT/install.sh" --project "$OTHER" --client all --permissions ask --without-jev
    if [ "$status" -eq 2 ]; then
        token="$(answers_token "$output")"
        run sh "$PRODUCT_ROOT/install.sh" --project "$OTHER" --answers "$token" --client all --permissions ask --without-jev
    fi
    [ "$status" -eq 0 ]
    grep -F '# Only this project' "$PROJECT/.datarim-runtime/commands/dr-do.md"
    ! grep -F '# Only this project' "$OTHER/.datarim-runtime/commands/dr-do.md"
    ! grep -F '# Only this project' "$OTHER/.claude/commands/dr-do.md"
}

@test "consumer writer refuses symlinked overlay directory before writing" {
    mkdir -p "$PROJECT/datarim" "$BATS_TEST_TMPDIR/outside"
    ln -s "$BATS_TEST_TMPDIR/outside" "$PROJECT/datarim/local"
    printf 'proposal\n' > "$BATS_TEST_TMPDIR/proposal"
    run python3 "$PRODUCT_ROOT/dev-tools/evolution-write.py" --root "$PROJECT" \
        --source "$PRODUCT_ROOT" --relative commands/dr-do.md --input "$BATS_TEST_TMPDIR/proposal"
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/outside/commands/dr-do.md" ]
}

@test "newer source update reports drift and keeps every overlay byte" {
    SOURCE_FIX="$BATS_TEST_TMPDIR/source"
    mkdir -p "$SOURCE_FIX/scripts"
    cp "$PRODUCT_ROOT/install.sh" "$PRODUCT_ROOT/update.sh" "$PRODUCT_ROOT/AGENTS.md" "$PRODUCT_ROOT/VERSION" "$SOURCE_FIX/"
    cp "$PRODUCT_ROOT/scripts/project_install.py" "$PRODUCT_ROOT/scripts/local_overlay.py" "$SOURCE_FIX/scripts/"
    for scope in agents skills commands templates dev-tools plugins config cli; do
        cp -R "$PRODUCT_ROOT/$scope" "$SOURCE_FIX/"
    done
    mkdir -p "$PROJECT/datarim/local/commands"
    printf '# Project override\n' > "$PROJECT/datarim/local/commands/dr-do.md"
    python3 "$SOURCE_FIX/scripts/local_overlay.py" add --project "$PROJECT" --source "$SOURCE_FIX" commands/dr-do.md
    cp "$PROJECT/datarim/local/commands/dr-do.md" "$BATS_TEST_TMPDIR/overlay-before"
    run sh "$SOURCE_FIX/install.sh" --project "$PROJECT" --client all --permissions ask --without-jev
    if [ "$status" -eq 2 ]; then
        token="$(answers_token "$output")"
        run sh "$SOURCE_FIX/install.sh" --project "$PROJECT" --answers "$token" --client all --permissions ask --without-jev
    fi
    [ "$status" -eq 0 ]
    printf '\n# New upstream release\n' >> "$SOURCE_FIX/commands/dr-do.md"
    run sh "$SOURCE_FIX/update.sh" --project "$PROJECT" --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    [[ "$output" == *'overlay_upstream_base_changed'* ]]
    cmp "$BATS_TEST_TMPDIR/overlay-before" "$PROJECT/datarim/local/commands/dr-do.md"
    cmp "$BATS_TEST_TMPDIR/overlay-before" "$PROJECT/.datarim-runtime/commands/dr-do.md"
}

@test "symlinked installed runtime subdirectory refuses update" {
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    mv "$PROJECT/.datarim-runtime/commands" "$PROJECT/runtime-commands-original"
    ln -s "$PROJECT/runtime-commands-original" "$PROJECT/.datarim-runtime/commands"
    install_answered --client all --permissions ask --without-jev
    [ "$status" -eq 2 ]
    [[ "$output" == *'Locally modified installed runtime'* ]]
    [ -L "$PROJECT/.datarim-runtime/commands" ]
}
