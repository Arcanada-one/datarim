#!/usr/bin/env bats
# Synthetic route fixtures for the persisted, enabled-and-selected profile gate.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    GATE="$REPO_ROOT/dev-tools/read-product-profile.sh"
    FIXTURE="$(mktemp -d)"
    ROOT="$FIXTURE/workspace"
    RUNTIME="$FIXTURE/runtime"
    TASK=TASK-1234
    mkdir -p "$ROOT/datarim/tasks" "$RUNTIME/skills/product-discovery/product-framing"
    printf 'synthetic fixture\n' >"$RUNTIME/skills/product-discovery/product-framing/SKILL.md"
    cat >"$ROOT/datarim/tasks/$TASK-task-description.md" <<'EOF'
## Profile
profile: product-discovery
EOF
}

teardown() {
    rm -rf "$FIXTURE"
}

run_gate() {
    run "$GATE" --root "$ROOT" --task "$TASK" --runtime "$RUNTIME"
}

enable_plugin() {
    cat >"$ROOT/datarim/enabled-plugins.md" <<'EOF'
## Active
- id: product-discovery
EOF
}

@test "no selector keeps the default route and emits only profile_not_selected" {
    cat >"$ROOT/datarim/tasks/$TASK-task-description.md" <<'EOF'
## Requirements
profile: product-discovery
EOF
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_not_selected ]
}

@test "selected profile stays unavailable while plugin is disabled" {
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_unavailable ]
}

@test "enabled and selected profile activates" {
    enable_plugin
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_active ]
}

@test "missing installed entry skill remains unavailable" {
    enable_plugin
    rm "$RUNTIME/skills/product-discovery/product-framing/SKILL.md"
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_unavailable ]
}

@test "unknown selector does not activate the plugin" {
    cat >"$ROOT/datarim/tasks/$TASK-task-description.md" <<'EOF'
## Profile
profile: another-profile
EOF
    enable_plugin
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_unknown ]
}

@test "duplicate selectors are ambiguous" {
    printf 'profile: product-discovery\n' >>"$ROOT/datarim/tasks/$TASK-task-description.md"
    enable_plugin
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_ambiguous ]
}

@test "disabled plugin is not activated by task text elsewhere" {
    cat >"$ROOT/datarim/tasks/$TASK-task-description.md" <<'EOF'
Product discovery would be useful: profile: product-discovery
## Notes
profile: product-discovery
EOF
    run_gate
    [ "$status" -eq 0 ]
    [ "$output" = profile_not_selected ]
}

@test "invalid invocation is rejected" {
    run "$GATE" --root "$ROOT" --task ../escape --runtime "$RUNTIME"
    [ "$status" -eq 64 ]
}
