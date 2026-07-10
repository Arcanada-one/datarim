#!/usr/bin/env bats
# TUNE-0343 — Auto-derive `--extra-repo` in /dr-qa Layer 3b for dual-repo
# topologies. Convenience-only: the `--extra-repo` flag on
# check-deferral-prose.sh already works when passed explicitly (per
# /dr-compliance Step 5c); this closes the gap where /dr-qa's advisory
# self-scan silently covered a smaller touched-set than the compliance-time
# hard gate because nothing derived the flag automatically.

DR_QA="$BATS_TEST_DIRNAME/../commands/dr-qa.md"

# Fixed-window extraction of the Anti-deferral prose scan bullet: header +
# next 6 lines covers the prose, the check-deferral-prose.sh invocation, and
# the exit-code bullets, without needing a fragile end-of-block boundary
# match (the enclosing markdown has no clean sibling-bullet delimiter here).
bullet_block() {
    grep -A 6 '\*\*Anti-deferral prose scan' "$DR_QA"
}

@test "Anti-deferral prose scan bullet exists in Layer 3b" {
    run grep -c 'Anti-deferral prose scan' "$DR_QA"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "bullet auto-derives --extra-repo (no longer relies on the agent noticing)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"--extra-repo"* ]]
    [[ "$block" == *"uto-deriv"* ]] || [[ "$block" == *"uto derive"* ]]
}

@test "bullet reuses the nested-.git discovery mechanism from /dr-archive Step 0.1" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"find"* ]]
    [[ "$block" == *".git"* ]]
}

@test "bullet cites /dr-compliance Step 5c as the topology this mirrors" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"/dr-compliance"* ]]
}

@test "the check-deferral-prose.sh invocation shows a repeatable --extra-repo slot" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"--extra-repo"* ]]
}
