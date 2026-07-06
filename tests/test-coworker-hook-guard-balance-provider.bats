#!/usr/bin/env bats
#
# TUNE-0469: SessionStart balance canary is provider-specific.
#
# Spec-regression tests for the SessionStart branch of coworker-hook-guard.
# The balance canary probes the ACTIVE coworker provider, resolved the way
# coworker itself resolves it:
#     profile.recommended_provider -> COWORKER_DEFAULT_PROVIDER -> "moonshot".
# It MUST NOT emit a "Moonshot balance low" warning when Moonshot is not the
# resolved provider — even if MOONSHOT_API_KEY is exported (both keys are
# commonly exported at once). It MUST still warn when Moonshot IS resolved and
# the live balance is below the threshold.
#
# The mock curl returns a low Moonshot balance ($0.5 < $3 default) so the only
# variable under test is the provider-resolution gate, not the balance math.

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
    command -v yq >/dev/null || skip "yq required for provider resolution"

    TESTTMP="$(mktemp -d)"
    # Mock curl on PATH: always returns a LOW Moonshot balance ($0.5).
    mkdir -p "$TESTTMP/bin"
    cat > "$TESTTMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"data":{"available_balance":0.5}}'
EOF
    chmod +x "$TESTTMP/bin/curl"
    mkdir -p "$TESTTMP/config/coworker"
    PATH="$TESTTMP/bin:$PATH"
}

teardown() {
    [ -n "${TESTTMP:-}" ] && rm -rf "$TESTTMP"
}

# Write the datarim profile with a given recommended_provider.
write_profile() {
    cat > "$TESTTMP/config/coworker/profiles.yaml" <<EOF
datarim:
  recommended_provider: $1
EOF
}

# Invoke the SessionStart branch with the mock config + given env.
run_sessionstart() {
    printf '%s' '{"hook_event_name":"SessionStart"}' \
        | env PATH="$TESTTMP/bin:$PATH" \
              XDG_CONFIG_HOME="$TESTTMP/config" \
              "$@" \
              "$HOOK"
}

@test "active-provider=deepseek + MOONSHOT_API_KEY set → NO Moonshot warning (AC-1)" {
    write_profile deepseek
    # Env default is moonshot; if resolution read the env FIRST (the bug) this
    # would wrongly warn. Profile (deepseek) must win.
    run run_sessionstart MOONSHOT_API_KEY=sk-test COWORKER_DEFAULT_PROVIDER=moonshot
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "active-provider=moonshot (profile) + low balance → warning fires (AC-2)" {
    write_profile moonshot
    run run_sessionstart MOONSHOT_API_KEY=sk-test
    [ "$status" -eq 0 ]
    msg=$(printf '%s' "$output" | jq -r '.systemMessage')
    case "$msg" in
        *"Moonshot balance low"*) : ;;
        *) printf 'expected Moonshot balance warning, got: %s\n' "$msg" >&2; return 1 ;;
    esac
}

@test "active-provider=moonshot via env fallback (no profile match) + low balance → warning fires (AC-3)" {
    # No datarim profile → resolution falls through to COWORKER_DEFAULT_PROVIDER.
    cat > "$TESTTMP/config/coworker/profiles.yaml" <<'EOF'
code:
  recommended_provider: deepseek
EOF
    run run_sessionstart MOONSHOT_API_KEY=sk-test COWORKER_DEFAULT_PROVIDER=moonshot
    [ "$status" -eq 0 ]
    msg=$(printf '%s' "$output" | jq -r '.systemMessage')
    case "$msg" in
        *"Moonshot balance low"*) : ;;
        *) printf 'expected Moonshot balance warning via env fallback, got: %s\n' "$msg" >&2; return 1 ;;
    esac
}

@test "no config + no env default → literal moonshot fallback + low balance → warning fires (AC-4)" {
    # No profiles.yaml at all, no COWORKER_DEFAULT_PROVIDER → literal "moonshot".
    # Preserves the pre-change behaviour on a yq-less / config-less host.
    rm -f "$TESTTMP/config/coworker/profiles.yaml"
    run run_sessionstart MOONSHOT_API_KEY=sk-test
    [ "$status" -eq 0 ]
    msg=$(printf '%s' "$output" | jq -r '.systemMessage')
    case "$msg" in
        *"Moonshot balance low"*) : ;;
        *) printf 'expected Moonshot balance warning via literal fallback, got: %s\n' "$msg" >&2; return 1 ;;
    esac
}

@test "active-provider=Moonshot (mixed case) → warning still fires (case-insensitive, AC-5)" {
    write_profile Moonshot
    run run_sessionstart MOONSHOT_API_KEY=sk-test
    [ "$status" -eq 0 ]
    msg=$(printf '%s' "$output" | jq -r '.systemMessage')
    case "$msg" in
        *"Moonshot balance low"*) : ;;
        *) printf 'expected warning for mixed-case Moonshot, got: %s\n' "$msg" >&2; return 1 ;;
    esac
}
