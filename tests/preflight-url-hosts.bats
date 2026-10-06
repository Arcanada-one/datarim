#!/usr/bin/env bats

setup() {
    VALIDATOR="$BATS_TEST_DIRNAME/../dev-tools/preflight-validate-url.sh"
}

@test "explicit caller host accepts an exact HTTPS events URL in every context" {
    for context in true false; do
        run env PREFLIGHT_ALLOWED_HOSTS=ops.caller.invalid PREFLIGHT_OPS_BOT_URL=https://ops.caller.invalid/events PREFLIGHT_IS_PROD_CONTEXT="$context" bash "$VALIDATOR"
        [ "$status" -eq 0 ]
    done
}

@test "multiple exact newline hosts accept a declared host" {
    run env PREFLIGHT_ALLOWED_HOSTS=$'ops.first.invalid\nops.second.invalid' PREFLIGHT_OPS_BOT_URL=https://ops.second.invalid/events bash "$VALIDATOR"
    [ "$status" -eq 0 ]
}

@test "missing allowlist fails closed including the historical example URL" {
    for context in true false; do
        run env PREFLIGHT_ALLOWED_HOSTS='' PREFLIGHT_OPS_BOT_URL=https://ops.example.invalid/events PREFLIGHT_IS_PROD_CONTEXT="$context" bash "$VALIDATOR"
        [ "$status" -eq 1 ]
    done
}

@test "malformed hostname anywhere in list refuses even if another entry matches" {
    for host in '*.caller.invalid' 'ops.caller.invalid:443' 'https://ops.caller.invalid' 'user@ops.caller.invalid' 'ops..invalid' '-ops.invalid' 'ops-.invalid' 'ops.invalid/' ' ops.invalid' '127.0.0.1' '[::1]' 'ops.invalid,evil.invalid'; do
        run env PREFLIGHT_ALLOWED_HOSTS="ops.caller.invalid
$host" PREFLIGHT_OPS_BOT_URL=https://ops.caller.invalid/events bash "$VALIDATOR"
        [ "$status" -eq 1 ]
    done
}

@test "undeclared host and authority suffix bypasses refuse in every context" {
    for context in true false; do
        for url in https://evil.invalid/events https://ops.caller.invalid.evil.invalid/events https://evilops.caller.invalid/events; do
            run env PREFLIGHT_ALLOWED_HOSTS=ops.caller.invalid PREFLIGHT_OPS_BOT_URL="$url" PREFLIGHT_IS_PROD_CONTEXT="$context" bash "$VALIDATOR"
            [ "$status" -eq 1 ]
        done
    done
}

@test "URL scheme userinfo port fragments queries and encoded path refuse" {
    for url in http://ops.caller.invalid/events https://ops.caller.invalid:443/events https://user@ops.caller.invalid/events https://ops.caller.invalid/events?key=x https://ops.caller.invalid/events#x https://ops.caller.invalid/%65vents https://ops.caller.invalid/events/ https://ops.caller.invalid./events ''; do
        run env PREFLIGHT_ALLOWED_HOSTS=ops.caller.invalid PREFLIGHT_OPS_BOT_URL="$url" bash "$VALIDATOR"
        [ "$status" -eq 1 ]
    done
}

@test "invalid URL diagnostics never echo URL or embedded credentials" {
    run env PREFLIGHT_ALLOWED_HOSTS=ops.caller.invalid PREFLIGHT_OPS_BOT_URL=https://SENTINEL_PRIVATE@ops.caller.invalid/events bash "$VALIDATOR"
    [ "$status" -eq 1 ]
    [[ "$output" != *SENTINEL_PRIVATE* ]]
}

@test "oversized hostname and overlong labels refuse" {
    printf -v label '%064d' 0
    run env PREFLIGHT_ALLOWED_HOSTS="$label.invalid" PREFLIGHT_OPS_BOT_URL=https://ops.caller.invalid/events bash "$VALIDATOR"
    [ "$status" -eq 1 ]
}

@test "blank entries carriage returns and executable-looking host input refuse" {
    for hosts in $'ops.caller.invalid\n\nevil.invalid' $'ops.caller.invalid\r' 'OPS.CALLER.INVALID' '$(touch sentinel.invalid)' 'ops.caller.invalid;true'; do
        run env PREFLIGHT_ALLOWED_HOSTS="$hosts" PREFLIGHT_OPS_BOT_URL=https://ops.caller.invalid/events bash "$VALIDATOR"
        [ "$status" -eq 1 ]
    done
}

@test "ordinary final newline is accepted" {
    run env PREFLIGHT_ALLOWED_HOSTS=$'ops.caller.invalid\n' PREFLIGHT_OPS_BOT_URL=https://ops.caller.invalid/events bash "$VALIDATOR"
    [ "$status" -eq 0 ]
}

@test "host count limit fails even after an early exact match" {
    hosts=ops.caller.invalid
    for i in {1..64}; do hosts+=$'\n'"host$i.caller.invalid"; done
    run env PREFLIGHT_ALLOWED_HOSTS="$hosts" PREFLIGHT_OPS_BOT_URL=https://ops.caller.invalid/events bash "$VALIDATOR"
    [ "$status" -eq 1 ]
}

@test "composite passes allowed_hosts through env with empty default before host checks" {
    run python3 -B - "$BATS_TEST_DIRNAME/../.github/actions/preflight-check/action.yml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    action = yaml.safe_load(f)
assert action['inputs']['allowed_hosts']['default'] == ''
steps = action['runs']['steps']
validator = next(s for s in steps if s.get('id') == 'validate-url')
assert validator['env']['PREFLIGHT_ALLOWED_HOSTS'] == '${{ inputs.allowed_hosts }}'
assert validator['env']['PREFLIGHT_OPS_BOT_URL'] == '${{ inputs.ops-bot-url }}'
assert validator['if'] == "inputs.ops-bot-emit == 'true'"
assert 'inputs.allowed_hosts' not in validator['run']
assert steps.index(validator) < next(i for i,s in enumerate(steps) if s.get('id') == 'run')
PY
    [ "$status" -eq 0 ]
}
