#!/usr/bin/env bats
# tdd-enforcement-toggle.bats — TDD enforcement workspace toggle.
#
# Coverage:
#   - disabled_defaults_state fail-safe parsing (exact tombstone only)
#   - scripts/tdd-enforcement-state.sh stateless resolver
#   - /dr-plugin enable|disable tdd-enforcement idempotent lifecycle
#   - core-only trust boundary (default_enabled is not a third-party primitive)
#   - list / sync / doctor coherence for the metadata-only default plugin

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
LIB_SH="$BATS_TEST_DIRNAME/../scripts/lib/plugin-system.sh"
STATE_SH="$BATS_TEST_DIRNAME/../scripts/tdd-enforcement-state.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
    mkdir -p "$TMPROOT/code/datarim"

    cp -r "$BATS_TEST_DIRNAME/../templates" "$TMPROOT/code/datarim/templates"
    cp "$BATS_TEST_DIRNAME/../VERSION" "$TMPROOT/code/datarim/VERSION"

    export DR_PLUGIN_WORKSPACE="$TMPROOT"
    export DR_PLUGIN_RUNTIME_ROOT="$TMPROOT/local-claude"
    mkdir -p "$DR_PLUGIN_RUNTIME_ROOT"/{skills,agents,commands,templates}

    MANIFEST="$TMPROOT/datarim/enabled-plugins.md"

    # shellcheck source=../scripts/lib/plugin-system.sh
    . "$LIB_SH"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_core_manifest() {
    cat > "$MANIFEST" <<'EOF'
# Enabled Plugins

## Active

- id: datarim-core
  source: builtin
  version: 1.0.0
  enabled_at: 2026-01-01T00:00:00Z
  protected: true
  file_inventory:
    skills: []
    agents: []
    commands: []
    templates: []
EOF
}

append_tombstone_section() {
    cat >> "$MANIFEST" <<'EOF'

## Disabled Defaults

- tdd-enforcement
EOF
}

# --- state parsing: fail-safe default ----------------------------------------

@test "S1 missing manifest resolves to required" {
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$status" -eq 0 ]
    [ "$output" = "required" ]
}

@test "S2 legacy core-only manifest (no section) resolves to required" {
    write_core_manifest
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$status" -eq 0 ]
    [ "$output" = "required" ]
}

@test "S3 exact tombstone resolves to optional" {
    write_core_manifest
    append_tombstone_section
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$status" -eq 0 ]
    [ "$output" = "optional" ]
}

@test "S4 indented tombstone resolves to required" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n  - tdd-enforcement\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S5 trailing whitespace on tombstone resolves to required" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n- tdd-enforcement \n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S6 substring id does not disable enforcement" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n- tdd-enforcement-strict\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S7 duplicate section heading resolves to required" {
    write_core_manifest
    append_tombstone_section
    printf '\n## Disabled Defaults\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S8 duplicate tombstone entry resolves to required" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n- tdd-enforcement\n- tdd-enforcement\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S9 unsupported content in section resolves to required" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n- tdd-enforcement\nfree prose here\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S10 heading with trailing space is not a valid section" {
    write_core_manifest
    printf '\n## Disabled Defaults \n\n- tdd-enforcement\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "S11 other well-formed ids alongside the tombstone still resolve optional" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n- some-other-default\n- tdd-enforcement\n' >> "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "optional" ]
}

# --- stateless resolver script -----------------------------------------------

@test "R1 resolver prints required for default workspace" {
    write_core_manifest
    run "$STATE_SH"
    [ "$status" -eq 0 ]
    [ "$output" = "required" ]
}

@test "R2 resolver prints optional for exact tombstone" {
    write_core_manifest
    append_tombstone_section
    run "$STATE_SH"
    [ "$status" -eq 0 ]
    [ "$output" = "optional" ]
}

@test "R3 resolver fails closed to required without a workspace" {
    unset DR_PLUGIN_WORKSPACE
    cd "$(mktemp -d)"
    run "$STATE_SH"
    [ "$status" -eq 0 ]
    [ "$output" = "required" ]
}

@test "R4 resolver re-reads state on every invocation (stateless)" {
    write_core_manifest
    run "$STATE_SH"
    [ "$output" = "required" ]
    append_tombstone_section
    run "$STATE_SH"
    [ "$output" = "optional" ]
}

@test "R5 resolver rejects unknown flags with usage error" {
    run "$STATE_SH" --bogus
    [ "$status" -eq 64 ]
}

# --- lifecycle: disable adds, enable removes, both idempotent ----------------

@test "L1 disable tdd-enforcement adds the tombstone" {
    write_core_manifest
    run "$PLUGIN_SH" disable tdd-enforcement
    [ "$status" -eq 0 ]
    grep -qx -- "- tdd-enforcement" "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "optional" ]
}

@test "L2 disable is idempotent (single tombstone after two runs)" {
    write_core_manifest
    "$PLUGIN_SH" disable tdd-enforcement
    run "$PLUGIN_SH" disable tdd-enforcement
    [ "$status" -eq 0 ]
    [ "$(grep -cx -- '- tdd-enforcement' "$MANIFEST")" -eq 1 ]
}

@test "L3 enable tdd-enforcement removes the tombstone" {
    write_core_manifest
    "$PLUGIN_SH" disable tdd-enforcement
    run "$PLUGIN_SH" enable tdd-enforcement
    [ "$status" -eq 0 ]
    ! grep -qx -- "- tdd-enforcement" "$MANIFEST"
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "L4 enable is idempotent on an already-required workspace" {
    write_core_manifest
    run "$PLUGIN_SH" enable tdd-enforcement
    [ "$status" -eq 0 ]
    run disabled_defaults_state "$MANIFEST" tdd-enforcement
    [ "$output" = "required" ]
}

@test "L5 lifecycle never touches runtime symlinks" {
    write_core_manifest
    mkdir -p "$DR_PLUGIN_RUNTIME_ROOT/skills/sentinel"
    ln -s "$TMPROOT/somewhere" "$DR_PLUGIN_RUNTIME_ROOT/skills/sentinel/link.md"
    local before after
    before="$(find "$DR_PLUGIN_RUNTIME_ROOT" | sort)"
    "$PLUGIN_SH" disable tdd-enforcement
    "$PLUGIN_SH" enable tdd-enforcement
    after="$(find "$DR_PLUGIN_RUNTIME_ROOT" | sort)"
    [ "$before" = "$after" ]
}

@test "L6 lifecycle preserves the Active section byte-for-byte" {
    write_core_manifest
    local before
    before="$(cat "$MANIFEST")"
    "$PLUGIN_SH" disable tdd-enforcement
    "$PLUGIN_SH" enable tdd-enforcement
    [ "$(cat "$MANIFEST")" = "$before" ]
}

# --- core-only trust boundary -------------------------------------------------

@test "T1 third-party manifest cannot claim default-on trust" {
    write_core_manifest
    mkdir -p "$TMPROOT/ext-plugin/skills"
    cat > "$TMPROOT/ext-plugin/plugin.yaml" <<'EOF'
schema_version: 1
id: ext-plugin
title: External
version: 0.1.0
default_enabled: true
EOF
    echo "x" > "$TMPROOT/ext-plugin/skills/x.md"
    "$PLUGIN_SH" enable "$TMPROOT/ext-plugin" || true
    run "$PLUGIN_SH" list
    # The specific line reporting ext-plugin must not mark it as a default
    # policy, regardless of its default_enabled claim.
    ! printf '%s\n' "$output" | grep "ext-plugin" | grep -q "(default)"
    # And the default-policies block lists only the core-owned id.
    printf '%s\n' "$output" | grep "(default)" | grep -qv "ext-plugin"
}

@test "T2 path-based plugin claiming the reserved id is refused" {
    write_core_manifest
    mkdir -p "$TMPROOT/fake/skills"
    cat > "$TMPROOT/fake/plugin.yaml" <<'EOF'
schema_version: 1
id: tdd-enforcement
title: Impersonator
version: 0.1.0
EOF
    run "$PLUGIN_SH" enable "$TMPROOT/fake"
    [ "$status" -ne 0 ]
    [[ "$output" == *"reserved"* ]]
    ! manifest_has_entry "$MANIFEST" tdd-enforcement
}

@test "T3 ordinary disable of an absent plugin still errors" {
    write_core_manifest
    run "$PLUGIN_SH" disable no-such-plugin
    [ "$status" -ne 0 ]
    ! grep -qx -- "- no-such-plugin" "$MANIFEST"
}

# --- plugin-manager coherence -------------------------------------------------

@test "C1 list reports enabled (default) out of the box" {
    write_core_manifest
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"tdd-enforcement"* ]]
    [[ "$output" == *"enabled (default)"* ]]
}

@test "C2 list reports disabled (default) after disable" {
    write_core_manifest
    "$PLUGIN_SH" disable tdd-enforcement
    run "$PLUGIN_SH" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled (default)"* ]]
}

@test "C3 sync preserves the tombstone" {
    write_core_manifest
    "$PLUGIN_SH" disable tdd-enforcement
    run "$PLUGIN_SH" sync
    [ "$status" -eq 0 ]
    grep -qx -- "- tdd-enforcement" "$MANIFEST"
}

@test "C4 doctor is clean on a valid tombstone" {
    write_core_manifest
    append_tombstone_section
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 0 ]
}

@test "C5 doctor diagnoses a malformed disabled-defaults section" {
    write_core_manifest
    printf '\n## Disabled Defaults\n\n  - tdd-enforcement\n' >> "$MANIFEST"
    run "$PLUGIN_SH" doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"disabled-defaults"* ]]
}

# --- bundled metadata-only plugin manifest ------------------------------------

@test "M1 bundled plugin.yaml is schema 1, metadata-only" {
    local yaml="$BATS_TEST_DIRNAME/../plugins/tdd-enforcement/plugin.yaml"
    [ -f "$yaml" ]
    [ "$(parse_plugin_yaml "$yaml" schema_version)" = "1" ]
    [ "$(parse_plugin_yaml "$yaml" id)" = "tdd-enforcement" ]
    [ "$(parse_plugin_yaml "$yaml" default_enabled)" = "true" ]
    # metadata-only: no projected category directories
    [ ! -d "$BATS_TEST_DIRNAME/../plugins/tdd-enforcement/skills" ]
    [ ! -d "$BATS_TEST_DIRNAME/../plugins/tdd-enforcement/agents" ]
    [ ! -d "$BATS_TEST_DIRNAME/../plugins/tdd-enforcement/commands" ]
}
