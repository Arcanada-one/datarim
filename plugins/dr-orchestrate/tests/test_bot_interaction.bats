#!/usr/bin/env bats
# test_bot_interaction.bats — bot_interaction_load dispatcher tests.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    TMP="$(mktemp -d)"
    export TMP
    # Source the dispatcher into the current shell so bot_interaction_load is
    # available; bats @test bodies run in the sourced env.
    # shellcheck source=/dev/null
    source "$PLUGIN_ROOT/scripts/bot_interaction_dispatcher.sh"

    # Reset any env mutations before each test.
    unset DR_ORCH_ESCALATION_BACKEND DR_ORCH_ESCALATION_DEVBOT_URL
    unset DR_ORCH_OUTBOUND_BACKEND DR_ORCH_OUTBOUND_REDIS_URL
}

teardown() {
    rm -rf "$TMP"
    unset DR_ORCH_ESCALATION_BACKEND DR_ORCH_ESCALATION_DEVBOT_URL
    unset DR_ORCH_OUTBOUND_BACKEND DR_ORCH_OUTBOUND_REDIS_URL
}

_write_config() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

# T1: provider=terminal → no env mutations.
@test "T1: provider=terminal leaves DR_ORCH_* env vars unset" {
    local cfg="$TMP/config-terminal.yaml"
    _write_config "$cfg" \
        "bot_interaction:" \
        "  provider: terminal"

    bot_interaction_load "$cfg"

    [ -z "${DR_ORCH_ESCALATION_BACKEND:-}" ]
    [ -z "${DR_ORCH_ESCALATION_DEVBOT_URL:-}" ]
}

# T2: provider=agent0017 → DR_ORCH_ESCALATION_BACKEND=dev-bot.
@test "T2: provider=agent0017 exports DR_ORCH_ESCALATION_BACKEND=dev-bot" {
    local cfg="$TMP/config-agent0017.yaml"
    _write_config "$cfg" \
        "bot_interaction:" \
        "  provider: agent0017"

    bot_interaction_load "$cfg"

    [ "${DR_ORCH_ESCALATION_BACKEND:-}" = "dev-bot" ]
}

# T3: provider=agent0017 + endpoint → DR_ORCH_ESCALATION_DEVBOT_URL exported.
@test "T3: provider=agent0017 with endpoint exports DR_ORCH_ESCALATION_DEVBOT_URL" {
    local cfg="$TMP/config-endpoint.yaml"
    _write_config "$cfg" \
        "bot_interaction:" \
        "  provider: agent0017" \
        "  endpoint: http://localhost:3010/prompts"

    bot_interaction_load "$cfg"

    [ "${DR_ORCH_ESCALATION_BACKEND:-}" = "dev-bot" ]
    [ "${DR_ORCH_ESCALATION_DEVBOT_URL:-}" = "http://localhost:3010/prompts" ]
}

# T4: outbound_backend=redis → exports DR_ORCH_OUTBOUND_BACKEND + DR_ORCH_OUTBOUND_REDIS_URL.
@test "T4: outbound_backend=redis exports redis env vars" {
    local cfg="$TMP/config-redis.yaml"
    _write_config "$cfg" \
        "bot_interaction:" \
        "  provider: agent0017" \
        "  outbound_backend: redis" \
        "  redis_url: redis://arcana-db:6379/0"

    bot_interaction_load "$cfg"

    [ "${DR_ORCH_OUTBOUND_BACKEND:-}" = "redis" ]
    [ "${DR_ORCH_OUTBOUND_REDIS_URL:-}" = "redis://arcana-db:6379/0" ]
}

# T5: missing bot_interaction block → exit 0, no mutations.
@test "T5: missing bot_interaction block exits 0 with no env mutations" {
    local cfg="$TMP/config-no-block.yaml"
    _write_config "$cfg" \
        "key_injection: false" \
        "session_name: datarim"

    bot_interaction_load "$cfg"

    [ -z "${DR_ORCH_ESCALATION_BACKEND:-}" ]
    [ -z "${DR_ORCH_ESCALATION_DEVBOT_URL:-}" ]
}

# T6: unknown provider → exit 2 + ERR on stderr.
@test "T6: unknown provider exits 2 with ERR on stderr" {
    local cfg="$TMP/config-bad-provider.yaml"
    _write_config "$cfg" \
        "bot_interaction:" \
        "  provider: foobar"

    run bash "$DR_ORCH_DIR/scripts/bot_interaction_dispatcher.sh" load "$cfg"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERR: unknown bot_interaction.provider"* ]]
}
