#!/usr/bin/env bats

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
STATE_SH="$BATS_TEST_DIRNAME/../scripts/tdd-enforcement-state.sh"

setup() {
    export TEST_HOME="$BATS_TEST_TMPDIR/home"
    export DR_PLUGIN_WORKSPACE="$BATS_TEST_TMPDIR/workspace"
    export DR_PLUGIN_RUNTIME_ROOT="$BATS_TEST_TMPDIR/runtime"
    mkdir -p "$TEST_HOME" "$DR_PLUGIN_WORKSPACE/datarim" "$DR_PLUGIN_RUNTIME_ROOT"/{skills,agents,commands,templates}
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
    printf '\n## Disabled Defaults\n\n%s\n' "$1" >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

run_state() {
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        bash "$STATE_SH"
}

run_plugin() {
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" bash "$PLUGIN_SH" "$@"
}

write_test_plugin() {
    local source_dir="$1" plugin_id="$2"
    mkdir -p "$source_dir/skills"
    cat > "$source_dir/plugin.yaml" <<EOF
schema_version: 1
id: $plugin_id
title: Test plugin
version: 0.1.0
author: Test
license: MIT
description: Ordinary opt-in plugin fixture.
categories:
  - skills
default_enabled: true
EOF
    printf '# test plugin\n' > "$source_dir/skills/test-plugin.md"
}

@test "missing manifest defaults to required" {
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "legacy core-only manifest defaults to required" {
    write_core_manifest
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "one exact disabled-default tombstone resolves optional" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "optional" ]
}

@test "resolver re-reads state without a restart" {
    write_core_manifest
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ] || return 1
    append_disabled_defaults "- tdd-enforcement"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "optional" ]
}

@test "duplicate disabled-default heading fails safe" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement"
    printf '\n## Disabled Defaults\n\n- tdd-enforcement\n' >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "duplicate tombstone fails safe" {
    write_core_manifest
    append_disabled_defaults $'- tdd-enforcement\n- tdd-enforcement'
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "indented tombstone fails safe" {
    write_core_manifest
    append_disabled_defaults "  - tdd-enforcement"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "trailing whitespace on tombstone fails safe" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement "
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "substring id does not disable enforcement" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement-legacy"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "prose inside disabled-default section fails safe" {
    write_core_manifest
    append_disabled_defaults $'- tdd-enforcement\nunexpected prose'
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "disable adds tombstone idempotently and touches no runtime files" {
    write_core_manifest
    run_plugin disable tdd-enforcement
    [ "$status" -eq 0 ] || return 1
    run_plugin disable tdd-enforcement
    local count runtime_count
    count="$(grep -c '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md")"
    runtime_count="$(find "$DR_PLUGIN_RUNTIME_ROOT" -type f -o -type l | wc -l | tr -d ' ')"
    [ "$status" -eq 0 ] && [ "$count" = "1" ] && [ "$runtime_count" = "0" ]
}

@test "enable removes tombstone idempotently and restores required state" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement"
    run_plugin enable tdd-enforcement
    [ "$status" -eq 0 ] && ! grep -q '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" || return 1
    run_plugin enable tdd-enforcement
    [ "$status" -eq 0 ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "ordinary plugin lifecycle preserves a trailing disabled-default tombstone" {
    local source_dir="$BATS_TEST_TMPDIR/ordinary-plugin"
    write_test_plugin "$source_dir" ordinary-plugin
    write_core_manifest

    run_plugin disable tdd-enforcement
    [ "$status" -eq 0 ] || return 1
    run_plugin enable "$source_dir"
    [ "$status" -eq 0 ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "optional" ] || return 1
    run_plugin disable ordinary-plugin
    [ "$status" -eq 0 ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "optional" ]
}

@test "removing the last ordinary plugin does not consume a following policy section" {
    local source_dir="$BATS_TEST_TMPDIR/ordinary-first"
    write_test_plugin "$source_dir" ordinary-first
    write_core_manifest

    run_plugin enable "$source_dir"
    [ "$status" -eq 0 ] || return 1
    run_plugin disable tdd-enforcement
    [ "$status" -eq 0 ] || return 1
    run_plugin disable ordinary-first
    [ "$status" -eq 0 ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "optional" ]
}

@test "list reports effective default plugin state" {
    write_core_manifest
    run_plugin list
    [ "$status" -eq 0 ] && [[ "$output" == *"tdd-enforcement"* ]] && [[ "$output" == *"enabled (default)"* ]] || return 1
    append_disabled_defaults "- tdd-enforcement"
    run_plugin list
    [ "$status" -eq 0 ] && [[ "$output" == *"disabled (default)"* ]]
}

@test "sync preserves a valid metadata-only tombstone" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement"
    run_plugin sync
    [ "$status" -eq 0 ] && grep -q '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "doctor accepts valid state and diagnoses malformed state" {
    write_core_manifest
    append_disabled_defaults "- tdd-enforcement"
    run_plugin doctor
    [ "$status" -eq 0 ] || return 1
    printf '%s\n' '- tdd-enforcement' >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_plugin doctor
    [ "$status" -ne 0 ] && [[ "$output" == *"Disabled Defaults"* || "$output" == *"disabled-default"* ]]
}

@test "doctor diagnoses a whitespace-altered disabled-default heading" {
    write_core_manifest
    printf '\n## Disabled Defaults \n\n- tdd-enforcement\n' >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_plugin doctor
    [ "$status" -ne 0 ] && [[ "$output" == *"Disabled Defaults"* || "$output" == *"disabled-default"* ]]
}

@test "third-party source cannot impersonate trusted default plugin" {
    local source_dir="$BATS_TEST_TMPDIR/tdd-enforcement"
    mkdir -p "$source_dir/skills"
    cat > "$source_dir/plugin.yaml" <<'EOF'
schema_version: 1
id: tdd-enforcement
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
    [ "$status" -ne 0 ] && [[ "$output" == *"reserved"* || "$output" == *"trusted"* ]]
}


@test "external default_enabled metadata remains ordinary opt-in state" {
    local source_dir="$BATS_TEST_TMPDIR/external-default"
    write_test_plugin "$source_dir" external-default
    write_core_manifest
    run_plugin enable "$source_dir"
    [ "$status" -eq 0 ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "required" ] \
        && ! grep -q '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "control characters in an ordinary plugin source are rejected before mutation" {
    local source_dir="$BATS_TEST_TMPDIR/linebreak"$'\n'"## Disabled Defaults"
    write_test_plugin "$source_dir" newline-source
    write_core_manifest
    cp "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" "$BATS_TEST_TMPDIR/manifest.before"
    run_plugin enable "$source_dir"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"control"* ]] \
        && cmp -s "$BATS_TEST_TMPDIR/manifest.before" "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "non-regular manifest is an I/O error, not valid required state" {
    mkdir "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 2 ] && [[ "$output" == *"not a readable regular file"* ]]
}

@test "concurrent first-run TDD disables serialize bootstrap and mutation" {
    local out1="$BATS_TEST_TMPDIR/disable-1.out" out2="$BATS_TEST_TMPDIR/disable-2.out"
    env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" DR_PLUGIN_LOCK_TIMEOUT=5 \
        bash "$PLUGIN_SH" disable tdd-enforcement >"$out1" 2>&1 &
    local pid1=$!
    env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" DR_PLUGIN_LOCK_TIMEOUT=5 \
        bash "$PLUGIN_SH" disable tdd-enforcement >"$out2" 2>&1 &
    local pid2=$!
    wait "$pid1"; local status1=$?
    wait "$pid2"; local status2=$?
    local count
    count="$(grep -c '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md")"
    [ "$status1" -eq 0 ] && [ "$status2" -eq 0 ] && [ "$count" = "1" ]
}


@test "first-run list respects the plugin lock before bootstrap" {
    mkdir -p "$DR_PLUGIN_WORKSPACE/datarim/.locks/plugin.lock"
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" DR_PLUGIN_LOCK_TIMEOUT=0 \
        bash "$PLUGIN_SH" list
    [ "$status" -eq 3 ] \
        && [ ! -e "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" ]
}

@test "workspace punctuation cannot inject commands through lock cleanup" {
    local canary="$BATS_TEST_TMPDIR/trap-canary"
    export DR_PLUGIN_WORKSPACE="$BATS_TEST_TMPDIR/workspace'; touch $canary; #"
    mkdir -p "$DR_PLUGIN_WORKSPACE/datarim"
    run_plugin disable tdd-enforcement
    [ "$status" -eq 0 ] && [ ! -e "$canary" ]
}
