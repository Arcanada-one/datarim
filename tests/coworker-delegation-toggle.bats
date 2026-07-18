#!/usr/bin/env bats

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
STATE_SH="$BATS_TEST_DIRNAME/../scripts/coworker-delegation-state.sh"
PLUGIN_DIR="$BATS_TEST_DIRNAME/../plugins/coworker-delegation"

setup() {
    export TEST_HOME="$BATS_TEST_TMPDIR/home"
    export DR_PLUGIN_WORKSPACE="$BATS_TEST_TMPDIR/workspace"
    export DR_PLUGIN_RUNTIME_ROOT="$BATS_TEST_TMPDIR/runtime"
    mkdir -p "$TEST_HOME" "$DR_PLUGIN_WORKSPACE/datarim" \
        "$DR_PLUGIN_RUNTIME_ROOT"/{skills,agents,commands,templates}
}

write_core_manifest() {
    cat > "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'
# Enabled Plugins

## Active

- id: datarim-core
  source: builtin
  version: test
  enabled_at: 2026-07-18T00:00:00Z
  protected: true
  file_inventory:
    skills: []
    agents: []
    commands: []
    templates: []
EOF
}

append_disabled_defaults() {
    printf '\n## Disabled Defaults\n\n%s\n' "$1" \
        >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

run_state() {
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        bash "$STATE_SH"
}

run_plugin() {
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" bash "$PLUGIN_SH" "$@"
}

@test "bundled plugin is trusted metadata-only and default-on" {
    [ -f "$PLUGIN_DIR/plugin.yaml" ] \
        && grep -q '^id: coworker-delegation$' "$PLUGIN_DIR/plugin.yaml" \
        && grep -q '^categories:$' "$PLUGIN_DIR/plugin.yaml" \
        && grep -q '^default_enabled: true$' "$PLUGIN_DIR/plugin.yaml" \
        && [ ! -d "$PLUGIN_DIR/skills" ] \
        && [ ! -d "$PLUGIN_DIR/agents" ] \
        && [ ! -d "$PLUGIN_DIR/commands" ] \
        && [ ! -d "$PLUGIN_DIR/templates" ]
}

@test "missing manifest defaults to enabled" {
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "legacy core-only manifest defaults to enabled" {
    write_core_manifest
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "one exact disabled-default tombstone resolves disabled" {
    write_core_manifest
    append_disabled_defaults "- coworker-delegation"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "resolver re-reads state without a restart" {
    write_core_manifest
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ] || return 1
    append_disabled_defaults "- coworker-delegation"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "duplicate disabled-default heading fails safe to enabled" {
    write_core_manifest
    append_disabled_defaults "- coworker-delegation"
    printf '\n## Disabled Defaults\n\n- coworker-delegation\n' \
        >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "duplicate coworker tombstone fails safe to enabled" {
    write_core_manifest
    append_disabled_defaults $'- coworker-delegation\n- coworker-delegation'
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "indented coworker tombstone fails safe to enabled" {
    write_core_manifest
    append_disabled_defaults "  - coworker-delegation"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "whitespace-altered coworker tombstone fails safe to enabled" {
    write_core_manifest
    append_disabled_defaults "- coworker-delegation "
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "substring and prose cannot disable delegation" {
    write_core_manifest
    append_disabled_defaults $'- coworker-delegation-v2\nunexpected prose'
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "TDD and coworker tombstones coexist independently" {
    write_core_manifest
    append_disabled_defaults $'- tdd-enforcement\n- coworker-delegation'
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ] || return 1
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        bash "$BATS_TEST_DIRNAME/../scripts/tdd-enforcement-state.sh"
    [ "$status" -eq 0 ] && [ "$output" = "optional" ]
}

@test "disable adds one tombstone and touches no runtime files" {
    write_core_manifest
    run_plugin disable coworker-delegation
    [ "$status" -eq 0 ] || return 1
    run_plugin disable coworker-delegation
    local count runtime_count
    count="$(grep -c '^- coworker-delegation$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md")"
    runtime_count="$(find "$DR_PLUGIN_RUNTIME_ROOT" \( -type f -o -type l \) | wc -l | tr -d ' ')"
    [ "$status" -eq 0 ] && [ "$count" = "1" ] && [ "$runtime_count" = "0" ]
}

@test "enable removes only the coworker tombstone and restores enabled state" {
    write_core_manifest
    append_disabled_defaults $'- tdd-enforcement\n- coworker-delegation'
    run_plugin enable coworker-delegation
    [ "$status" -eq 0 ] \
        && grep -q '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" \
        && ! grep -q '^- coworker-delegation$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" \
        || return 1
    run_plugin enable coworker-delegation
    [ "$status" -eq 0 ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "list reports the effective bundled state exactly once" {
    write_core_manifest
    run_plugin list
    [ "$status" -eq 0 ] \
        && [ "$(printf '%s\n' "$output" | grep -c 'coworker-delegation')" = "1" ] \
        && [[ "$output" == *"enabled (default)"* ]] || return 1
    append_disabled_defaults "- coworker-delegation"
    run_plugin list
    [ "$status" -eq 0 ] \
        && [ "$(printf '%s\n' "$output" | grep -c 'coworker-delegation')" = "1" ] \
        && [[ "$output" == *"disabled (default)"* ]]
}

@test "sync preserves a valid coworker tombstone" {
    write_core_manifest
    append_disabled_defaults "- coworker-delegation"
    run_plugin sync
    [ "$status" -eq 0 ] \
        && grep -q '^- coworker-delegation$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "doctor accepts valid coworker state and rejects malformed state" {
    write_core_manifest
    append_disabled_defaults "- coworker-delegation"
    run_plugin doctor
    [ "$status" -eq 0 ] || return 1
    printf '%s\n' '- coworker-delegation' \
        >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_plugin doctor
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"Disabled Defaults"* || "$output" == *"disabled-default"* ]]
}

@test "misplaced coworker tombstone fails safe and doctor diagnoses it" {
    write_core_manifest
    printf '\n## Other Policy\n\n- coworker-delegation\n' \
        >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ] || return 1
    run_plugin doctor
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"Disabled Defaults"* || "$output" == *"disabled-default"* ]]
}

@test "third-party source cannot impersonate coworker-delegation" {
    local source_dir="$BATS_TEST_TMPDIR/coworker-delegation"
    mkdir -p "$source_dir/skills"
    cat > "$source_dir/plugin.yaml" <<'EOF'
schema_version: 1
id: coworker-delegation
title: Impostor
version: 0.1.0
author: Test
license: MIT
description: Must not acquire core trust.
categories:
  - skills
default_enabled: true
EOF
    printf '# impostor\n' > "$source_dir/skills/impostor.md"
    run_plugin enable "$source_dir"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"reserved"* || "$output" == *"trusted"* ]]
}

@test "non-regular manifest is an I/O error with enabled fail-safe output" {
    mkdir "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"not a readable regular file"* ]]
}


@test "invalid workspace reports enabled with a nonzero status" {
    run env HOME="$TEST_HOME" bash "$STATE_SH" \
        --workspace "$BATS_TEST_TMPDIR/missing-workspace"
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"workspace not found"* ]] \
        && printf '%s\n' "$output" | grep -qx 'enabled'
}


@test "unknown resolver argument reports enabled with a nonzero status" {
    run env HOME="$TEST_HOME" bash "$STATE_SH" --unknown
    [ "$status" -eq 2 ] \
        && [[ "$output" == *"unknown argument"* ]] \
        && printf '%s\n' "$output" | grep -qx 'enabled'
}
