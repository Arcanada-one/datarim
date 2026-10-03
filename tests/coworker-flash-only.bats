#!/usr/bin/env bats
# Originally: the Coworker fan-out templates had to declare every enabled
# profile Flash-only. Those templates were removed when Coworker delegation was
# retired in favour of native fleet backends, so the original assertion now
# guards files that do not exist — and `grep` on a missing file reports the same
# status as "pattern absent", which would have let this test pass for the wrong
# reason.
#
# The test is kept, inverted: the retirement is the thing worth guarding. A
# template that reappears brings back the delegation path, and this is where
# that shows up.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FRAGMENT="$REPO_ROOT/templates/coworker-delegation-fragment.md"
    CURSOR="$REPO_ROOT/templates/coworker-delegation.mdc"
}

@test "retired coworker fan-out templates have not returned" {
    [ ! -e "$FRAGMENT" ]
    [ ! -e "$CURSOR" ]
}

@test "no template ships an invocable coworker delegation" {
    # Prose that forbids coworker is legitimate and must stay — datarim-config.yaml
    # documents exactly which external providers are refused. What must not return
    # is an invocable delegation: a coworker command line or a config key that
    # routes work to it. Templates are inherited by every consumer project, so a
    # reintroduction here propagates ecosystem-wide.
    # Comment lines are excluded: a comment cannot route work, and the prose that
    # forbids coworker necessarily names it.
    run bash -c "grep -rnE '(^|[^a-zA-Z_-])coworker([[:space:]]+[a-z-]|(_[a-z]+)*:)' '$REPO_ROOT/templates' \
        | grep -vE ':[[:space:]]*#' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//|<!--)'"
    [ "$status" -ne 0 ] || {
        printf 'invocable coworker reference in a template:\n%s\n' "$output"
        return 1
    }
}
