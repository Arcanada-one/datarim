#!/usr/bin/env bats
# test_context_builder.bats — minimal context injection + token-budget guard (3c).

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    # Repo root = framework root (two levels up from plugins/dr-orchestrate).
    REPO="$(cd "$PLUGIN_ROOT/../.." && pwd)"
    export DR_FLEET_REPO="$REPO"
    BUILDER="$PLUGIN_ROOT/scripts/context_builder.sh"
    BRIEF="$BATS_TEST_TMPDIR/brief.txt"
    printf 'Do one small thing.\n' > "$BRIEF"
}

@test "context_builder.sh exists and is executable" {
    [ -x "$BUILDER" ]
}

@test "build_context emits exactly the five allowed component markers" {
    run bash "$BUILDER" build_context 1 "$BRIEF" "proj-a proj-b" "env-x"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "=== SKILL ==="
    echo "$output" | grep -q "=== ENV ==="
    echo "$output" | grep -q "=== PROJECTS ==="
    echo "$output" | grep -q "=== KB-REF ==="
    echo "$output" | grep -q "=== BRIEF ==="
}

@test "build_context does NOT inject full project context or task history" {
    run bash "$BUILDER" build_context 1 "$BRIEF" "proj-a" "env-x"
    [ "$status" -eq 0 ]
    # KB is a reference, not a dump: no full CLAUDE.md body, no history transcript.
    ! echo "$output" | grep -q "=== HISTORY ==="
    ! echo "$output" | grep -q "=== FULL-PROJECT ==="
}

@test "_read_budget extracts integer budget from fleet skill frontmatter (not yq-on-full-file)" {
    run bash "$BUILDER" _read_budget 3
    [ "$status" -eq 0 ]
    [ "$output" = "1500" ]
}

@test "_read_budget rejects unknown level" {
    run bash "$BUILDER" _read_budget 9
    [ "$status" -ne 0 ]
}

@test "build_context fails closed (exit 3) when assembled context exceeds level budget" {
    # L1 budget = 200 tokens. A large brief blows past it; guard must fire BEFORE
    # returning the context, not after.
    BIG="$BATS_TEST_TMPDIR/big.txt"
    head -c 20000 /dev/zero | tr '\0' 'x' > "$BIG"
    run bash "$BUILDER" build_context 1 "$BIG" "proj-a" "env-x"
    [ "$status" -eq 3 ]
}

@test "build_context succeeds when context fits the level budget" {
    run bash "$BUILDER" build_context 4 "$BRIEF" "proj-a" "env-x"
    [ "$status" -eq 0 ]
}

@test "build_context rejects missing brief file (usage error exit 2)" {
    run bash "$BUILDER" build_context 1 "/no/such/brief" "proj-a" "env-x"
    [ "$status" -eq 2 ]
}
