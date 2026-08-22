#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FRAGMENT="$REPO_ROOT/templates/coworker-delegation-fragment.md"
    CURSOR="$REPO_ROOT/templates/coworker-delegation.mdc"
}

@test "coworker fanout templates declare all enabled profiles Flash-only" {
    for file in "$FRAGMENT" "$CURSOR"; do
        run grep -F "DeepSeek v4-pro" "$file"
        [ "$status" -eq 1 ]

        run grep -F "automatic profiles have no cross-provider fallback" "$file"
        [ "$status" -eq 0 ]

        run grep -F "manual operator overrides" "$file"
        [ "$status" -eq 0 ]
    done
}
