#!/usr/bin/env bats
load 'helpers/project_install'
setup() { setup_project_fixture; }

@test "no implicit project or global installation" {
    run sh "$PRODUCT_ROOT/install.sh"
    [ "$status" -eq 2 ]
    [ ! -e "$HOME/.claude" ]
}

@test "retired global installation flags are rejected" {
    for flag in --with-claude --with-codex --with-cursor; do
        install_project "$flag"
        [ "$status" -eq 2 ]
    done
    [ ! -e "$PROJECT/AGENTS.md" ]
}

@test "home and system directories are rejected before mutation" {
    for target in "$HOME" / /etc /usr; do
        run sh "$PRODUCT_ROOT/install.sh" --project "$target" --without-jev --dry-run
        [ "$status" -eq 2 ]
    done
}

@test "dry run through POSIX sh has no project mutations" {
    install_project --dry-run --with-jev --init
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT/.datarim-install.lock" ]
    [ ! -e "$PROJECT/AGENTS.md" ]
    [ ! -e "$PROJECT/config" ]
}

@test "an existing CLAUDE.md is left alone" {
    # Datarim no longer relies on AGENTS.md being loaded, so the client's own
    # instruction files are none of its business.
    printf 'Operator rules' > "$PROJECT/CLAUDE.md"
    install_project --without-jev
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT/AGENTS.md" ]
    run cat "$PROJECT/CLAUDE.md"
    [ "$output" = 'Operator rules' ]
}
