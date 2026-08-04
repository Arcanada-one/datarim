#!/usr/bin/env bats
#
# Anti-decay spec-regression: skills/testing/concurrency-patterns.md must
# document the provider-race pattern (bounded fan-out over multiple
# provider/endpoint alternatives) and stay wired into the testing entry
# skill's Fragment Routing section. Stack-specific literals are allowed
# only inside a gate:example-only fence.

FRAGMENT="${BATS_TEST_DIRNAME}/../skills/testing/concurrency-patterns.md"
ENTRY="${BATS_TEST_DIRNAME}/../skills/testing/SKILL.md"

@test "fragment file exists" {
    [ -f "$FRAGMENT" ]
}

@test "fragment carries the Provider Race section header" {
    run grep -cE "^## Provider Race" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "all five pattern components are named" {
    run grep -ciE "bounded worker pool" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "completion-ordered" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "first-success short-circuit" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "alert only when ALL fail" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "barrier" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "one-cap latency caveat present (correctness, not speed)" {
    run grep -ciE "slowest" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "NOT speed" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "budget sizing rule present (one cap, not the sum)" {
    run grep -ciE "not the sum" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "stack-specific pool literal appears only inside gate:example-only fence" {
    # Every line mentioning ThreadPoolExecutor must sit between the
    # example-only fence markers.
    run awk '
        /<!-- gate:example-only -->/  { fenced = 1 }
        /<!-- \/gate:example-only -->/ { fenced = 0 }
        /ThreadPoolExecutor/ && !fenced { bad++ }
        END { exit (bad > 0 ? 1 : 0) }
    ' "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "entry SKILL.md routes to the fragment in Fragment Routing" {
    run grep -cE '`concurrency-patterns\.md`' "$ENTRY"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" -ge 2 ]   # routing bullet + quick-heuristic line
}
