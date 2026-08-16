#!/usr/bin/env bats
# exec-guard-wiring.bats — the framework ships execution-host MECHANISM, not
# enforcement POLICY.
#
# History this file encodes. An earlier revision asserted the opposite: that a
# PreToolUse guard shipped here and that seven command docs referenced it. That
# arrangement put two writable copies of one ENFORCEMENT artefact in two repos
# with no sync mechanism. They drifted. The stale shipped copy then shadowed the
# good private one on a consumer host and denied every task ON ITS OWN declared
# execution host, while a second host had no protection at all -- a control that
# was wrong in both directions at once.
#
# So the assertions are inverted on purpose: the guard MUST NOT be here, and the
# docs MUST NOT promise it. What stays is the mechanism any consumer can use --
# the resolver, the drift validator, their tests.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# --- the enforcement artefact must be absent ---------------------------------

@test "guard script is NOT shipped by the framework (class-b)" {
    [ ! -e "$REPO_ROOT/dev-tools/datarim-exec-guard.sh" ]
}

@test "guard tests are NOT shipped either (they follow their subject)" {
    [ ! -e "$REPO_ROOT/dev-tools/tests/datarim-exec-guard.bats" ]
}

@test "the class-b gate exists and is executable" {
    [ -x "$REPO_ROOT/dev-tools/check-class-b-not-shipped.sh" ]
}

@test "class-b gate passes on the current tree" {
    run bash "$REPO_ROOT/dev-tools/check-class-b-not-shipped.sh" --root "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "class-b gate FAILS when a class-b script reappears (positive control)" {
    # A gate that has never gone red proves nothing. Seed the exact violation
    # and assert it is caught, in a scratch tree so the real repo is untouched.
    local tmp; tmp="$(mktemp -d)"
    mkdir -p "$tmp/dev-tools"
    touch "$tmp/dev-tools/datarim-exec-guard.sh"
    run bash "$REPO_ROOT/dev-tools/check-class-b-not-shipped.sh" --root "$tmp"
    rm -rf "$tmp"
    [ "$status" -eq 1 ]
}

# --- shipped docs must not promise the guard ---------------------------------

@test "no command doc claims the framework ships the guard" {
    run grep -rl "ships the PreToolUse guard" "$REPO_ROOT/commands/"
    [ "$status" -ne 0 ]
}

@test "no shipped surface references the removed guard script" {
    run grep -rl "datarim-exec-guard" \
        "$REPO_ROOT/commands/" "$REPO_ROOT/skills/" "$REPO_ROOT/agents/" "$REPO_ROOT/CLAUDE.md"
    [ "$status" -ne 0 ]
}

@test "no shipped surface points at the unshipped dispatch script" {
    # The deny message used to tell users to run dev-tools/datarim-dispatch.sh,
    # which is not in this repo -- a documented path to a nonexistent file.
    run grep -rl "datarim-dispatch.sh" \
        "$REPO_ROOT/commands/" "$REPO_ROOT/skills/" "$REPO_ROOT/CLAUDE.md"
    [ "$status" -ne 0 ]
}

# --- the generic mechanism must stay ------------------------------------------

@test "execution-host.sh resolver library still ships" {
    [ -f "$REPO_ROOT/dev-tools/lib/execution-host.sh" ]
}

@test "drift validator still ships and is executable" {
    [ -x "$REPO_ROOT/dev-tools/check-execution-host-drift.sh" ]
}

@test "resolver tests still ship" {
    [ -f "$REPO_ROOT/dev-tools/tests/execution-host.bats" ]
}

@test "command docs still carry the cooperative EXECUTION HOST step" {
    # Removing the guard must not remove the soft layer: the commands still
    # resolve the declared host, they just no longer promise enforcement.
    run grep -rl "EXECUTION HOST" "$REPO_ROOT/commands/"
    [ "$status" -eq 0 ]
}

@test "S10-bis records that enforcement is site policy, not shipped" {
    run grep -q "NOT shipped" "$REPO_ROOT/CLAUDE.md"
    [ "$status" -eq 0 ]
}

@test "S10-bis warns that on-host and unconfigured share exit code 0" {
    # The trap that made a missing guard look healthy. Anyone writing their own
    # hook must read this, so assert the warning survives future edits.
    run grep -q "never infer health from silence" "$REPO_ROOT/CLAUDE.md"
    [ "$status" -eq 0 ]
}
