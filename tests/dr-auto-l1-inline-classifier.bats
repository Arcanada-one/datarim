#!/usr/bin/env bats

# Test contract: dev-tools/classify-inline-gap.sh implements L1 Inline Resolution Rule
# decision tree from skills/autonomous-mode.md.
#
# Inputs: --files <int> --loc <int> --contract <true|false> --hard-gated <true|false>
# Outputs: L1-A | L2+/B | HARD

CLASSIFY="$BATS_TEST_DIRNAME/../dev-tools/classify-inline-gap.sh"

setup() {
    [ -x "$CLASSIFY" ] || skip "classifier script not executable: $CLASSIFY"
}

@test "L1-A: single file, 10 LoC, no contract change" {
    run "$CLASSIFY" --files 1 --loc 10 --contract false --hard-gated false
    [ "$status" -eq 0 ]
    [ "$output" = "L1-A" ]
}

@test "L1-A: single file, 49 LoC, no contract change (below boundary)" {
    run "$CLASSIFY" --files 1 --loc 49 --contract false --hard-gated false
    [ "$status" -eq 0 ]
    [ "$output" = "L1-A" ]
}

@test "L1-A: single file, exactly 50 LoC (boundary inclusive)" {
    run "$CLASSIFY" --files 1 --loc 50 --contract false --hard-gated false
    [ "$status" -eq 0 ]
    [ "$output" = "L1-A" ]
}

@test "L2+/B: single file, 51 LoC (boundary exceeded)" {
    run "$CLASSIFY" --files 1 --loc 51 --contract false --hard-gated false
    [ "$status" -eq 0 ]
    [ "$output" = "L2+/B" ]
}

@test "L2+/B: multi-file edit (2 files, small LoC)" {
    run "$CLASSIFY" --files 2 --loc 5 --contract false --hard-gated false
    [ "$status" -eq 0 ]
    [ "$output" = "L2+/B" ]
}

@test "L2+/B: contract change (API schema)" {
    run "$CLASSIFY" --files 1 --loc 5 --contract true --hard-gated false
    [ "$status" -eq 0 ]
    [ "$output" = "L2+/B" ]
}

@test "HARD: hard-gated action overrides scope check (would-be L1)" {
    run "$CLASSIFY" --files 1 --loc 5 --contract false --hard-gated true
    [ "$status" -eq 0 ]
    [ "$output" = "HARD" ]
}

@test "HARD: hard-gated overrides even when L2+/B by scope" {
    run "$CLASSIFY" --files 5 --loc 200 --contract true --hard-gated true
    [ "$status" -eq 0 ]
    [ "$output" = "HARD" ]
}

@test "usage error: missing --files flag" {
    run "$CLASSIFY" --loc 10 --contract false --hard-gated false
    [ "$status" -eq 2 ]
}

@test "usage error: non-numeric --loc value" {
    run "$CLASSIFY" --files 1 --loc abc --contract false --hard-gated false
    [ "$status" -eq 2 ]
}

@test "usage error: invalid --contract value" {
    run "$CLASSIFY" --files 1 --loc 10 --contract maybe --hard-gated false
    [ "$status" -eq 2 ]
}
