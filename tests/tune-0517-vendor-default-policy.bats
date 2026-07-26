#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RESOLVER="$REPO_ROOT/plugins/dr-orchestrate/scripts/subagent_resolver.sh"
    TMP_BIN="$(mktemp -d)"
    STATE_DIR="$(mktemp -d)"
    export STATE_DIR
}

teardown() {
    rm -rf "$TMP_BIN" "$STATE_DIR"
}

@test "canonical policy follows vendor-default model and effort" {
    run grep -F "Prefer vendor-default model and effort" \
        "$REPO_ROOT/skills/datarim-system/model-assignment.md"
    [ "$status" -eq 0 ] || return 1
    grep -Fq "skills/tech-stack/SKILL.md" \
        "$REPO_ROOT/skills/datarim-system/model-assignment.md"
}

@test "CLI version policy is permission-aware and advisory" {
    policy="$REPO_ROOT/skills/datarim-system/model-assignment.md"
    grep -Fq "newest stable CLI-agent version" "$policy" || return 1
    grep -Fiq "where installation or upgrade is permitted" "$policy" || return 1
    grep -Fq "must not block" "$policy"
}

@test "model tiers use vendor-default semantics and preserve inheritance" {
    config="$REPO_ROOT/config/model-tiers.yaml"
    [ "$(grep -c 'selection: vendor-default$' "$config")" -eq 4 ] || return 1
    [ "$(grep -c 'adapter_behavior: omit-model-override$' "$config")" -eq 4 ] \
        || return 1
    grep -Fq "runtime_default: inherit" "$config" || return 1
    run grep -Fq "feedback_latest_deps_rule.md" "$config"
    [ "$status" -ne 0 ]
}

@test "consumer surfaces cross-link the canonical policy" {
    grep -Fq "skills/datarim-system/model-assignment.md" "$REPO_ROOT/CLAUDE.md" \
        || return 1
    grep -Fq "skills/datarim-system/model-assignment.md" \
        "$REPO_ROOT/commands/dr-orchestrate.md"
}

@test "auto-mode pre-resolves model and effort selection" {
    auto="$REPO_ROOT/skills/autonomous-mode/SKILL.md"
    grep -Fq "Which model or effort should be used" "$auto" || return 1
    grep -Fq "vendor-default" "$auto"
}

@test "fleet version hint is opt-in and selection remains successful" {
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'if [ "${1:-}" = "--version" ]; then echo "fake-cli 9.9.9"; fi' \
        'exit 0' > "$TMP_BIN/claude"
    chmod +x "$TMP_BIN/claude"
    run env PATH="$TMP_BIN:$PATH" DR_FLEET_VERSION_HINTS=1 \
        DR_FLEET_BACKEND_CHAIN=claude bash "$RESOLVER" select_fleet_backend
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"ADVISORY: CLI claude fake-cli 9.9.9 detected"* ]] \
        || return 1
    [[ "$output" == *"claude"* ]]
}

@test "fleet version probe failure is silent and fail-open" {
    printf '%s\n' '#!/usr/bin/env bash' 'exit 7' > "$TMP_BIN/claude"
    chmod +x "$TMP_BIN/claude"
    run env PATH="$TMP_BIN:$PATH" DR_FLEET_VERSION_HINTS=1 \
        DR_FLEET_BACKEND_CHAIN=claude bash "$RESOLVER" select_fleet_backend
    [ "$status" -eq 0 ] || return 1
    [ "$output" = "claude" ]
}

@test "hung fleet version probe times out and selection remains successful" {
    printf '%s\n' '#!/usr/bin/env bash' 'sleep 10' > "$TMP_BIN/claude"
    chmod +x "$TMP_BIN/claude"
    start="$SECONDS"
    run env PATH="$TMP_BIN:$PATH" DR_FLEET_VERSION_HINTS=1 \
        DR_FLEET_VERSION_TIMEOUT_S=1 DR_FLEET_BACKEND_CHAIN=claude \
        bash "$RESOLVER" select_fleet_backend
    elapsed=$((SECONDS - start))
    [ "$status" -eq 0 ] || return 1
    [ "$output" = "claude" ] || return 1
    [ "$elapsed" -lt 5 ]
}
