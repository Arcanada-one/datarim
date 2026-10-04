#!/usr/bin/env bats
#
# Anti-decay spec-regression for three Class-A guidance sections:
#   1. skills/network-exposure-baseline/SKILL.md § Consumer Wiring Example
#      (array-form `needs`, parallel-not-sequential job ordering)
#   2. same skill § Local Pre-PR Smoke Recipe (positive control on the live
#      compose config + negative control on a scratch /tmp copy + cleanup)
#   3. skills/datarim-system/backlog-and-routing.md § Pre-merge baseline
#      cleanup spawn (separate cleanup task for baseline-red CI noise)

NEB="${BATS_TEST_DIRNAME}/../skills/network-exposure-baseline/SKILL.md"
ROUTING="${BATS_TEST_DIRNAME}/../skills/datarim-system/backlog-and-routing.md"

@test "both skill files exist" {
    [ -f "$NEB" ]
    [ -f "$ROUTING" ]
}

@test "Consumer Wiring Example section present with array-form needs" {
    run grep -cE "^## Consumer Wiring Example" "$NEB"
    [ "$status" -eq 0 ]
    run grep -cE "needs: \[" "$NEB"
    [ "$status" -eq 0 ]
}

@test "scalar-to-array needs promotion note present" {
    run grep -ciE "scalar" "$NEB"
    [ "$status" -eq 0 ]
    run grep -ciE "array form" "$NEB"
    [ "$status" -eq 0 ]
}

@test "parallel-not-sequential job ordering note present" {
    # "run in / parallel" may wrap across a line boundary — assert the
    # word itself plus the sequential-chain warning on their own lines.
    run grep -ciE "parallel" "$NEB"
    [ "$status" -eq 0 ]
    run grep -ciE "sequential chain" "$NEB"
    [ "$status" -eq 0 ]
}

@test "Local Pre-PR Smoke Recipe with positive and negative cases" {
    run grep -cE "^## Local Pre-PR Smoke Recipe" "$NEB"
    [ "$status" -eq 0 ]
    run grep -cE "^### Positive case" "$NEB"
    [ "$status" -eq 0 ]
    run grep -cE "^### Negative case" "$NEB"
    [ "$status" -eq 0 ]
}

@test "negative case uses a scratch copy and cleans it up" {
    run grep -cE '/tmp/' "$NEB"
    [ "$status" -eq 0 ]
    run grep -cE 'rm -rf "\$NEG_DIR"' "$NEB"
    [ "$status" -eq 0 ]
}

@test "Pre-merge baseline cleanup spawn bullet present in routing fragment" {
    run grep -cE "^### Pre-merge baseline cleanup spawn" "$ROUTING"
    [ "$status" -eq 0 ]
    run grep -ciE "separate.*cleanup task" "$ROUTING"
    [ "$status" -eq 0 ]
    run grep -ciE "baseline-red CI noise" "$ROUTING"
    [ "$status" -eq 0 ]
}
