#!/usr/bin/env bats
#
# PRD template "Runtime-script citation root requirement" regression guard.
#
# Stage-rule contract: templates/prd-template.md MUST keep the rule requiring
# an explicit root (${DATARIM_RUNTIME:-$HOME/.claude}/... or the framework
# repo's full canonical path) on every runtime-script/skill citation in a
# PRD body — a bare-relative form like plugins/<name>/scripts/<script>.sh
# resolves against the reading agent's cwd and misleads about location.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
PRD_TEMPLATE="$REPO_ROOT/templates/prd-template.md"

@test "T1: prd-template.md contains the runtime-script citation root requirement" {
    [ -f "$PRD_TEMPLATE" ]
    run grep -F "Runtime-script citation root requirement" "$PRD_TEMPLATE"
    [ "$status" -eq 0 ]
}

@test "T2: rule forbids the bare-relative plugins/.../scripts form" {
    run grep -F 'plugins/<name>/scripts/<script>.sh' "$PRD_TEMPLATE"
    [ "$status" -eq 0 ]
}

@test "T3: rule cites the DATARIM_RUNTIME fallback form as the required root" {
    run grep -F '${DATARIM_RUNTIME:-$HOME/.claude}/...' "$PRD_TEMPLATE"
    [ "$status" -eq 0 ]
}
