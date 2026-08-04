#!/usr/bin/env bats
# tune-0204-dr-plan-stdlib-advisory.bats
#
# Prose-contract regression for the standard-library symbol/module coverage
# advisory in commands/dr-plan.md (the Step 6.5 symbol-existence check family).
#
# The base symbol check greps the PROJECT tree, which by construction cannot
# resolve a symbol shipping in the language's standard library — a plain grep
# reports "not found" even when the reference is correct. The advisory bullet
# closes both halves of that gap and each half is load-bearing:
#
#   (a) MISSING-IMPORT SURFACE CASE — a wrong or renamed stdlib symbol (a
#       module absent in the target runtime version, a deprecated core module)
#       still deserves a plan-time flag; the check is lowered to advisory, not
#       deleted.
#   (b) ALREADY-IMPORTED PASS-SILENTLY SEMANTICS — a project-grep miss alone
#       must NOT fail the plan when the symbol is a plausible stdlib reference;
#       the plan records a one-line advisory note instead of a hard fail.
#
# The command spec is prose executed by an LLM, so dropping either half in an
# edit breaks nothing structurally — this suite is the load-bearing wiring.

DOC="${BATS_TEST_DIRNAME}/../commands/dr-plan.md"

# The whole bullet lives on one (very long) source line; capture it once.
bullet() {
    grep 'Standard-library symbol/module coverage' "$DOC"
}

@test "dr-plan.md carries the standard-library symbol/module coverage bullet" {
    [ -f "$DOC" ]
    # grep -c (not -q) — SIGPIPE-safe under pipefail
    count="$(grep -c 'Standard-library symbol/module coverage' "$DOC")"
    [ "$count" -ge 1 ]
}

@test "bullet is marked ADVISORY, not a hard fail" {
    line="$(bullet)"
    [[ "$line" == *"ADVISORY"* ]]
    [[ "$line" == *"not a hard fail"* ]]
}

@test "(a) missing-import surface case: a wrong/renamed stdlib symbol still gets a plan-time flag" {
    line="$(bullet)"
    # the surface half: wrong or renamed stdlib references are still flagged
    [[ "$line" == *"wrong or renamed stdlib symbol"* ]]
    [[ "$line" == *"still deserves a plan-time flag"* ]]
}

@test "(b) already-imported pass-silently semantics: a project-grep miss alone must not fail the plan" {
    line="$(bullet)"
    # the pass-silently half: grep-miss on a plausible stdlib symbol is not a failure
    [[ "$line" == *"do not fail the plan on a project-grep miss alone"* ]]
}

@test "bullet prescribes the advisory note so /dr-do sees the surface was sanity-checked" {
    line="$(bullet)"
    [[ "$line" == *"stdlib check"* ]]
    [[ "$line" == *"advisory note"* ]]
}
