#!/usr/bin/env bats

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
STATE_SH="$BATS_TEST_DIRNAME/../scripts/ltm-graph-memory-state.sh"

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

append_ltm_record() {
    local source="${1:-builtin}"
    local version="${2:-1.0.0}"
    local enabled_at="${3:-2026-07-18T00:00:00Z}"
    local protected="${4:-false}"
    local skills="${5:-}"
    cat >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<EOF

- id: ltm-graph-memory
  source: $source
  version: $version
  enabled_at: $enabled_at
  protected: $protected
  file_inventory:
    skills: [$skills]
    agents: []
    commands: []
    templates: []
EOF
}

append_tdd_tombstone() {
    cat >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'

## Disabled Defaults

- tdd-enforcement
EOF
}

run_state() {
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        bash "$STATE_SH"
}

run_plugin() {
    run env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" bash "$PLUGIN_SH" "$@"
}

@test "missing manifest defaults to disabled" {
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "core-only manifest defaults to disabled" {
    write_core_manifest
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "one exact built-in metadata record resolves enabled" {
    write_core_manifest
    append_ltm_record
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "resolver re-reads graph-memory state on every invocation" {
    write_core_manifest
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ] || return 1
    append_ltm_record
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "incomplete metadata record fails safe to disabled" {
    write_core_manifest
    cat >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'

- id: ltm-graph-memory
  source: builtin
  version: 1.0.0
EOF
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "duplicate metadata records fail safe to disabled" {
    write_core_manifest
    append_ltm_record
    append_ltm_record
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "wrong source fails safe to disabled" {
    write_core_manifest
    append_ltm_record "/tmp/impersonator"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "wrong version fails safe to disabled" {
    write_core_manifest
    append_ltm_record "builtin" "9.9.9"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "malformed timestamp fails safe to disabled" {
    write_core_manifest
    append_ltm_record "builtin" "1.0.0" "today"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "protected metadata record fails safe to disabled" {
    write_core_manifest
    append_ltm_record "builtin" "1.0.0" "2026-07-18T00:00:00Z" "true"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "non-empty metadata inventory fails safe to disabled" {
    write_core_manifest
    append_ltm_record "builtin" "1.0.0" "2026-07-18T00:00:00Z" "false" "memory.md"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "trailing fields after a blank separator fail safe to disabled" {
    write_core_manifest
    append_ltm_record
    cat >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'

  unexpected: true
EOF
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "enable refuses a manifest without an Active section" {
    cat > "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'
# Enabled Plugins

## Disabled Defaults
EOF
    cp "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" "$BATS_TEST_TMPDIR/no-active-before"
    run_plugin enable ltm-graph-memory
    [ "$status" -ne 0 ] \
        && cmp -s "$BATS_TEST_TMPDIR/no-active-before" "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "duplicate Active headings fail safe to disabled" {
    write_core_manifest
    cat >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'

## Active
EOF
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "doctor rejects an LTM record outside the Active section" {
    write_core_manifest
    cat >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" <<'EOF'

## Disabled Defaults

- id: ltm-graph-memory
  source: builtin
  version: 1.0.0
  enabled_at: 2026-07-18T00:00:00Z
  protected: false
  file_inventory:
    skills: []
    agents: []
    commands: []
    templates: []
EOF
    run_plugin doctor
    [ "$status" -ne 0 ] && [[ "$output" == *"ltm-graph-memory"* ]] \
        && [[ "$output" == *"invalid"* ]]
}

@test "indented id does not enable graph memory" {
    write_core_manifest
    sed 's/^- id: ltm/  - id: ltm/' < <(printf '%s\n' '- id: ltm-graph-memory') \
        >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "substring id does not enable graph memory" {
    write_core_manifest
    sed 's/ltm-graph-memory/ltm-graph-memory-v2/' < <(cat <<'EOF'
- id: ltm-graph-memory
  source: builtin
  version: 1.0.0
  enabled_at: 2026-07-18T00:00:00Z
  protected: false
  file_inventory:
    skills: []
    agents: []
    commands: []
    templates: []
EOF
) >> "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "non-regular manifest returns disabled with an I/O error" {
    rmdir "$DR_PLUGIN_WORKSPACE/datarim"
    mkdir -p "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_state
    [ "$status" -eq 2 ] && [[ "$output" == disabled* ]] \
        && [[ "$output" == *"not a readable regular file"* ]]
}

@test "enable is idempotent and creates one complete record without runtime files" {
    write_core_manifest
    run_plugin enable ltm-graph-memory
    [ "$status" -eq 0 ] || return 1
    run_plugin enable ltm-graph-memory
    local count runtime_count
    count="$(grep -c '^- id: ltm-graph-memory$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md")"
    runtime_count="$(find "$DR_PLUGIN_RUNTIME_ROOT" \( -type f -o -type l \) | wc -l | tr -d ' ')"
    [ "$status" -eq 0 ] && [ "$count" = "1" ] && [ "$runtime_count" = "0" ] \
        && grep -q '^  source: builtin$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" \
        && grep -q '^  protected: false$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "disable is idempotent and repairs duplicate exact records" {
    write_core_manifest
    append_ltm_record
    append_ltm_record
    run_plugin disable ltm-graph-memory
    [ "$status" -eq 0 ] || return 1
    run_plugin disable ltm-graph-memory
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ] \
        && ! grep -q '^- id: ltm-graph-memory$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "enable refuses an invalid persisted record without mutation" {
    write_core_manifest
    append_ltm_record "/tmp/impersonator"
    cp "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" "$BATS_TEST_TMPDIR/before"
    run_plugin enable ltm-graph-memory
    [ "$status" -ne 0 ] && [[ "$output" == *"invalid"* ]] \
        && cmp -s "$BATS_TEST_TMPDIR/before" "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "TDD tombstone and LTM record coexist in both mutation orders" {
    write_core_manifest
    run_plugin disable tdd-enforcement
    [ "$status" -eq 0 ] || return 1
    run_plugin enable ltm-graph-memory
    [ "$status" -eq 0 ] || return 1
    grep -q '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md" || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ] || return 1

    run_plugin disable ltm-graph-memory
    [ "$status" -eq 0 ] || return 1
    run_plugin enable ltm-graph-memory
    [ "$status" -eq 0 ] && grep -q '^- tdd-enforcement$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "list reports bundled disabled and enabled states exactly once" {
    write_core_manifest
    run_plugin list
    [ "$status" -eq 0 ] \
        && [ "$(printf '%s\n' "$output" | grep -c 'ltm-graph-memory')" = "1" ] \
        && [[ "$output" == *"installed (disabled)"* ]] || return 1
    run_plugin enable ltm-graph-memory
    [ "$status" -eq 0 ] || return 1
    run_plugin list
    [ "$status" -eq 0 ] \
        && [ "$(printf '%s\n' "$output" | grep -c 'ltm-graph-memory')" = "1" ] \
        && [[ "$output" == *"installed (enabled)"* ]]
}

@test "sync preserves valid metadata state and creates no symlink" {
    write_core_manifest
    run_plugin enable ltm-graph-memory
    [ "$status" -eq 0 ] || return 1
    run_plugin sync
    local runtime_count
    runtime_count="$(find "$DR_PLUGIN_RUNTIME_ROOT" \( -type f -o -type l \) | wc -l | tr -d ' ')"
    [ "$status" -eq 0 ] && [ "$runtime_count" = "0" ] || return 1
    run_state
    [ "$status" -eq 0 ] && [ "$output" = "enabled" ]
}

@test "doctor accepts absent and exact states and rejects invalid state" {
    write_core_manifest
    run_plugin doctor
    [ "$status" -eq 0 ] || return 1
    append_ltm_record
    run_plugin doctor
    [ "$status" -eq 0 ] || return 1
    sed -i.bak 's/^  source: builtin$/  source: \/tmp\/impersonator/' \
        "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
    run_plugin doctor
    [ "$status" -ne 0 ] && [[ "$output" == *"ltm-graph-memory"* ]] \
        && [[ "$output" == *"invalid"* ]]
}

@test "path-based external plugin cannot claim the reserved LTM id" {
    local source_dir="$BATS_TEST_TMPDIR/ltm-graph-memory"
    mkdir -p "$source_dir/skills"
    cat > "$source_dir/plugin.yaml" <<'EOF'
schema_version: 1
id: ltm-graph-memory
title: Impostor
version: 0.1.0
author: Test
license: MIT
description: Must not acquire core trust.
categories:
  - skills
EOF
    printf '# impostor\n' > "$source_dir/skills/impostor.md"
    run_plugin enable "$source_dir"
    [ "$status" -ne 0 ] && [[ "$output" == *"reserved"* ]]
}

@test "control characters in an external source cannot inject LTM state" {
    local canary="$BATS_TEST_TMPDIR/canary"
    local source_dir="$BATS_TEST_TMPDIR/source"$'\n'"- id: ltm-graph-memory"
    mkdir -p "$source_dir/skills"
    cat > "$source_dir/plugin.yaml" <<'EOF'
schema_version: 1
id: ordinary-plugin
title: Ordinary
version: 0.1.0
author: Test
license: MIT
description: Injection fixture.
categories:
  - skills
EOF
    printf '# ordinary\n' > "$source_dir/skills/ordinary.md"
    write_core_manifest
    run_plugin enable "$source_dir"
    [ "$status" -ne 0 ] && [[ "$output" == *"control"* ]] \
        && [ ! -e "$canary" ] \
        && ! grep -q '^- id: ltm-graph-memory$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md"
}

@test "concurrent first-run enables serialize to one LTM record" {
    local out1="$BATS_TEST_TMPDIR/enable-1.out" out2="$BATS_TEST_TMPDIR/enable-2.out"
    env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" DR_PLUGIN_LOCK_TIMEOUT=5 \
        bash "$PLUGIN_SH" enable ltm-graph-memory >"$out1" 2>&1 &
    local pid1=$!
    env HOME="$TEST_HOME" DR_PLUGIN_WORKSPACE="$DR_PLUGIN_WORKSPACE" \
        DR_PLUGIN_RUNTIME_ROOT="$DR_PLUGIN_RUNTIME_ROOT" DR_PLUGIN_LOCK_TIMEOUT=5 \
        bash "$PLUGIN_SH" enable ltm-graph-memory >"$out2" 2>&1 &
    local pid2=$!
    wait "$pid1"; local status1=$?
    wait "$pid2"; local status2=$?
    local count
    count="$(grep -c '^- id: ltm-graph-memory$' "$DR_PLUGIN_WORKSPACE/datarim/enabled-plugins.md")"
    [ "$status1" -eq 0 ] && [ "$status2" -eq 0 ] && [ "$count" = "1" ]
}
