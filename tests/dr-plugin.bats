#!/usr/bin/env bats
# dr-plugin.bats — TUNE-0101 Plugin System Core (Phase A scaffold).
#
# Coverage in this slice:
#   - validate_plugin_id helper (regex + boundary)
#   - parse_plugin_yaml helper (field extraction, list parsing)
#   - validate_source helper (path traversal, abs path, git URL)
#   - dr-plugin list (first-run bootstrap, active entries rendering)
#
# Out of scope (later phases):
#   - enable / disable / sync / doctor — Phase A3-D (next /dr-do)
#
# Source: plans/TUNE-0101-plan.md § Phase A.

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
LIB_SH="$BATS_TEST_DIRNAME/../scripts/lib/plugin-system.sh"
TEMPLATE_DIR="$BATS_TEST_DIRNAME/../templates"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
    mkdir -p "$TMPROOT/code/datarim"

    # Mirror the layout `dr-plugin.sh` expects to find via DR_PLUGIN_ROOT.
    cp -r "$BATS_TEST_DIRNAME/../templates" "$TMPROOT/code/datarim/templates"
    cp "$BATS_TEST_DIRNAME/../VERSION" "$TMPROOT/code/datarim/VERSION"

    export DR_PLUGIN_WORKSPACE="$TMPROOT"
    export DR_PLUGIN_RUNTIME_ROOT="$TMPROOT/local-claude"
    mkdir -p "$DR_PLUGIN_RUNTIME_ROOT"/{skills,agents,commands,templates}

    # shellcheck source=../scripts/lib/plugin-system.sh
    . "$LIB_SH"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- validate_plugin_id ------------------------------------------------------

@test "T1 validate_plugin_id accepts kebab-case id" {
    run validate_plugin_id "my-plugin"
    [ "$status" -eq 0 ]
}

@test "T2 validate_plugin_id accepts single-letter id" {
    run validate_plugin_id "a"
    [ "$status" -eq 0 ]
}

@test "T3 validate_plugin_id rejects uppercase" {
    run validate_plugin_id "MyPlugin"
    [ "$status" -ne 0 ]
}

@test "T4 validate_plugin_id rejects leading digit" {
    run validate_plugin_id "1plugin"
    [ "$status" -ne 0 ]
}

@test "T5 validate_plugin_id rejects empty id" {
    run validate_plugin_id ""
    [ "$status" -ne 0 ]
}

@test "T6 validate_plugin_id rejects path traversal" {
    run validate_plugin_id "../evil"
    [ "$status" -ne 0 ]
}

@test "T7 validate_plugin_id rejects id over 32 chars" {
    run validate_plugin_id "$(printf 'a%.0s' {1..33})"
    [ "$status" -ne 0 ]
}

@test "T8 validate_plugin_id accepts id at 32-char boundary" {
    run validate_plugin_id "$(printf 'a%.0s' {1..32})"
    [ "$status" -eq 0 ]
}

# --- parse_plugin_yaml -------------------------------------------------------

@test "T10 parse_plugin_yaml extracts id" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" id
    [ "$status" -eq 0 ]
    [ "$output" = "my-plugin" ]
}

@test "T11 parse_plugin_yaml extracts schema_version" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" schema_version
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "T12 parse_plugin_yaml extracts title with spaces" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" title
    [ "$status" -eq 0 ]
    [ "$output" = "My Plugin Title" ]
}

@test "T13 parse_plugin_yaml returns empty for missing field" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" nonexistent
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T14 parse_plugin_yaml rejects CRLF input (security)" {
    printf 'schema_version: 1\r\nid: bad\r\n' > "$TMPROOT/plugin.yaml"
    run parse_plugin_yaml "$TMPROOT/plugin.yaml" id
    [ "$status" -ne 0 ]
    [[ "$output" == *"CRLF"* ]] || [[ "$output" == *"line ending"* ]]
}

@test "T15 parse_plugin_yaml rejects missing file" {
    run parse_plugin_yaml "$TMPROOT/no-such.yaml" id
    [ "$status" -ne 0 ]
}

# --- parse_yaml_list ---------------------------------------------------------

@test "T20 parse_yaml_list extracts categories" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_yaml_list "$TMPROOT/plugin.yaml" categories
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills"* ]]
    [[ "$output" == *"commands"* ]]
}

@test "T21 parse_yaml_list returns empty for absent key" {
    cp "$TEMPLATE_DIR/plugin.yaml.template" "$TMPROOT/plugin.yaml"
    run parse_yaml_list "$TMPROOT/plugin.yaml" overrides
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- validate_source ---------------------------------------------------------

@test "T30 validate_source accepts builtin keyword" {
    run validate_source "builtin"
    [ "$status" -eq 0 ]
}

@test "T31 validate_source accepts absolute path under HOME" {
    run validate_source "$HOME/some/path"
    [ "$status" -eq 0 ]
}

@test "T32 validate_source accepts https git URL" {
    run validate_source "https://github.com/Arcanada-one/example-plugin.git"
    [ "$status" -eq 0 ]
}

@test "T33 validate_source rejects path traversal" {
    run validate_source "../evil"
    [ "$status" -ne 0 ]
}

@test "T34 validate_source rejects relative path" {
    run validate_source "some/rel/path"
    [ "$status" -ne 0 ]
}

@test "T35 validate_source rejects URL with embedded credentials" {
    run validate_source "https://user:token@github.com/foo/bar.git"
    [ "$status" -ne 0 ]
    [[ "$output" == *"credential"* ]] || [[ "$output" == *"token"* ]]
}

# --- dr-plugin list (first-run + render) ------------------------------------

@test "T40 dr-plugin list bootstraps datarim-core on first run" {
    [ ! -f "$TMPROOT/datarim/enabled-plugins.md" ]
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/enabled-plugins.md" ]
    grep -q "id: datarim-core" "$TMPROOT/datarim/enabled-plugins.md"
    grep -q "protected: true" "$TMPROOT/datarim/enabled-plugins.md"
}

@test "T41 dr-plugin list renders datarim-core entry" {
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"datarim-core"* ]]
    [[ "$output" == *"protected"* ]] || [[ "$output" == *"builtin"* ]]
}

@test "T42 dr-plugin list is idempotent — second run does not duplicate core" {
    run "$PLUGIN_SH" list
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    local count
    count="$(grep -c "id: datarim-core" "$TMPROOT/datarim/enabled-plugins.md")"
    [ "$count" = "1" ]
}

@test "T43 dr-plugin --help exits 0 with usage" {
    run "$PLUGIN_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"dr-plugin"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"enable"* ]]
}

@test "T44 dr-plugin with no args prints usage and exits 64" {
    run "$PLUGIN_SH"
    [ "$status" -eq 64 ]
}

@test "T45 dr-plugin unknown subcommand exits 64" {
    run "$PLUGIN_SH" unknown-cmd
    [ "$status" -eq 64 ]
}
