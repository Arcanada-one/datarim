#!/usr/bin/env bats
#
# Regression test for TUNE-0506 (execution-host routing FAST-TASKS).
#
# commands/dr-quick.md § EXECUTION HOST step 3 previously treated EVERY
# off-host (exit 10) QCK as observational: it ALWAYS proceeded LOCALLY
# read-only and NEVER dispatched. A MUTATING /dr-quick (edits files, switches
# branches, writes the archive) then ran on the operator's Mac, violating the
# dev-server-first mandate. TUNE-0506 splits the off-host verdict into a
# read-only branch (stays local, correct) and a mutating branch (auto-dispatch
# to required_host, mirroring the dr-do.md AUTO-DISPATCH contract), with a
# deferred/intent-flip guard so a lookup-turned-mutation cannot slip through
# locally.
#
# These are shipped-doc grep assertions (same style as
# tests/tune-0370-doc-drift.bats): they pin the CONTRACT TEXT so the two
# branches and their fail-closed guards cannot silently regress.

ROOT="${BATS_TEST_DIRNAME}/.."
DRQUICK="${ROOT}/commands/dr-quick.md"

@test "dr-quick.md § EXECUTION HOST has a MUTATING auto-dispatch branch" {
    run grep -c 'MUTATING QCK' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c 'AUTO-DISPATCH to `required_host`' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-quick.md mutating branch references the dr-do.md AUTO-DISPATCH contract" {
    run grep -c 'dr-do.md` § EXECUTION HOST AUTO-DISPATCH contract' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # The referenced contract must actually exist in dr-do.md.
    run grep -c 'EXECUTION HOST' "${ROOT}/commands/dr-do.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'AUTO-DISPATCH' "${ROOT}/commands/dr-do.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-quick.md mutating branch preserves the fail-closed guards (not weakened)" {
    # Target integrity: host-key pin + operator-local map + STOP-and-report.
    run grep -c 'pinned `known_hosts` entry' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Exit 10 has exactly two outcomes; local execution is never one of them.
    run grep -c 'exactly two outcomes' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'fail-CLOSED' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Bare-task-id payload only.
    run grep -c 'bare task-id only' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Read-only monitor after dispatch.
    run grep -c 'READ-ONLY MONITOR' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-quick.md § EXECUTION HOST preserves the read-only-stays-local rationale" {
    run grep -c 'READ-ONLY QCK' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # The verbatim-in-spirit rationale MUST survive.
    run grep -c 'buys nothing' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # A read-only QCK surfaces the directive as information, never as a gate.
    run grep -c 'information only, never as a blocking question' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-quick.md defers the dispatch decision and closes the intent-flip hole" {
    run grep -c 'deferred and re-evaluated' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c 'Intent-flip guard' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Dispatch BEFORE any local mutation, else STOP and report.
    run grep -c 'before' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'rather than mutate locally' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-quick.md § EXECUTION HOST leaves steps 4 (fail-open) and 5 (on-host) unchanged" {
    run grep -c 'On \*\*unconfigured\*\* (exit code 0, binding absent): proceed unchanged (fail-open)' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c 'On \*\*on-host\*\* (exit code 0, binding present): proceed normally' "${DRQUICK}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
