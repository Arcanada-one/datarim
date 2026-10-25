#!/usr/bin/env bats

@test "locally applied consumer rule remains a promotion candidate" {
    root="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$root/datarim/history"
    printf '| Date | Task | Category | Target | Change |\n|------|------|----------|--------|--------|\n| 2026-10-25 | local | promotion-candidate | AGENTS.md | Locally applied reusable rule |\n' > "$root/datarim/history/evolution-log.md"
    run bash "$BATS_TEST_DIRNAME/../dev-tools/cross-kb-evolution-digest.sh" --kb "$root" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"promotion"'* ]]
    [[ "$output" == *'Locally applied reusable rule'* ]]
}
