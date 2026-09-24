#!/usr/bin/env bats
load 'helpers/project_install'
setup() { setup_project_fixture; }

@test "Cursor discovers only the commands by default" {
    install_project --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/.cursor/skills/dr-do/SKILL.md" ]
    [ ! -e "$PROJECT/.cursor/skills/testing" ]
}

@test "Cursor discovers directory skills with original frontmatter when exposed" {
    install_project --client all --permissions ask --without-jev --expose-skills
    [ "$status" -eq 0 ]
    [ -f "$PROJECT/.cursor/skills/testing/SKILL.md" ]
    [ -f "$PROJECT/.cursor/skills/fleet-l1-basic/SKILL.md" ]
    run grep -F 'name: testing' "$PROJECT/.cursor/skills/testing/SKILL.md"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.cursor/skills" ]
}

@test "Cursor foreign skills are preserved" {
    mkdir -p "$PROJECT/.cursor/skills/foreign"
    printf 'Keep foreign skill' > "$PROJECT/.cursor/skills/foreign/SKILL.md"
    install_project --client all --permissions ask --without-jev
    [ "$status" -eq 0 ]
    run cat "$PROJECT/.cursor/skills/foreign/SKILL.md"
    [ "$output" = 'Keep foreign skill' ]
}

@test "Cursor hook installation retains unrelated native registrations" {
    mkdir -p "$PROJECT/.cursor"
    printf '%s\n' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"foreign-guard"}]}}' > "$PROJECT/.cursor/hooks.json"
    install_project --client all --permissions ask --with-jev
    [ "$status" -eq 0 ]
    run python3 - "$PROJECT/.cursor/hooks.json" <<'CHECK'
import json,sys
h=json.load(open(sys.argv[1]))['hooks']['beforeShellExecution']
assert len(h)==2 and h[0]['command']=='foreign-guard'
assert h[1]['failClosed'] is True and 'jev_hook.py' in h[1]['command']
CHECK
    [ "$status" -eq 0 ]
}
