#!/usr/bin/env bats
# check-gate-token-registry-sync.sh — cross-check corpus type:/priority: values
# against the network-exposure gate's recognised value-sets.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/check-gate-token-registry-sync.sh"
    GATE="$REPO_ROOT/dev-tools/network-exposure-gate.sh"
    F="$REPO_ROOT/tests/fixtures/gate-token-registry-sync"
}

# --- Clean corpus: every type: in set/allowlist, every priority: handled ---

@test "checker: clean corpus -> exit 0" {
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/clean" --quiet
    [ "$status" -eq 0 ]
}

# --- Unhandled type: value flagged ---

@test "checker: short-form sibling type (sec) -> exit 1 naming it" {
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/type-gap"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sec"* ]]
}

@test "checker: unrelated free-form type is NOT flagged -> exit 0" {
    # a free-form type with no prefix relation to any gating token must be ignored
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/unrelated" --quiet
    [ "$status" -eq 0 ]
}

# --- Unhandled priority: value flagged ---

@test "checker: unhandled priority -> exit 1 naming it" {
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/prio-gap"
    [ "$status" -eq 1 ]
    [[ "$output" == *"P9"* ]]
}

# --- Empty corpus is clean ---

@test "checker: empty corpus -> exit 0" {
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/empty" --quiet
    [ "$status" -eq 0 ]
}

# --- Real gate parses: P0..P4 all handled, infra in type set ---

@test "checker: real gate recognises P4 and infra (post-fix)" {
    # clean corpus uses P4 + infrastructure/feature; must pass against the real gate
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/clean" --quiet
    [ "$status" -eq 0 ]
}

# --- Usage / IO errors ---

@test "checker: unreadable --gate -> exit 2" {
    run "$SCRIPT" --gate "/nonexistent/gate-${RANDOM}.sh" --corpus-dir "$F/clean" --quiet
    [ "$status" -eq 2 ]
}

@test "checker: unknown flag -> exit 2" {
    run "$SCRIPT" --gate "$GATE" --corpus-dir "$F/clean" --bogus
    [ "$status" -eq 2 ]
}

@test "checker: --version emits version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"check-gate-token-registry-sync.sh"* ]]
}
