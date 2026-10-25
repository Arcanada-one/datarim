#!/usr/bin/env bats

setup() {
    ROOT="$BATS_TEST_DIRNAME/.."
}

@test "autonomous routes reach compliance evolution step" {
    grep -q 'skills/evolution/autonomous-apply.md' "$ROOT/commands/dr-compliance.md"
    grep -q 'autonomous evolution decision step' "$ROOT/commands/dr-auto.md"
    grep -q 'skills/evolution/autonomous-apply.md' "$ROOT/commands/dr-orchestrate.md"
}

@test "fresh archive still presents unresolved proposals" {
    grep -q 'SKIP the workflow below only for regeneration steps (a-c)' "$ROOT/commands/dr-archive.md"
    grep -q 'before continuing to \*\*Step 0.6\*\*' "$ROOT/commands/dr-archive.md"
    grep -q 'even when freshness exit 0' "$ROOT/commands/dr-archive.md"
}

@test "QA PASS requires all three QA-side gates" {
    line="$(grep -F '**OUTPUT**: Write' "$ROOT/commands/dr-qa.md")"
    [[ "$line" == *'check-live-evidence.sh'* ]]
    [[ "$line" == *'check-qa-charter-coverage.py'* ]]
    [[ "$line" == *'check-qa-verdict-blocked.sh'* ]]
    grep -q 'check-qa-contract-version.py' "$ROOT/commands/dr-qa.md"
}

@test "auto stage summary names all three QA-side gates" {
    line="$(grep 'A QA stage-pass claim requires' "$ROOT/skills/autonomous-mode/SKILL.md")"
    [[ "$line" == *'check-live-evidence.sh'* ]]
    [[ "$line" == *'check-qa-charter-coverage.py'* ]]
    [[ "$line" == *'check-qa-verdict-blocked.sh'* ]]
}

@test "do stage loads unique-violation normalization before merge" {
    grep -q 'Unique-Violation Domain Normalization before the first merge request' "$ROOT/commands/dr-do.md"
}

@test "merged dual-repo scope uses pull-request touched files" {
    grep -q 'merged pull-request diffs and pass `--touched-files' "$ROOT/commands/dr-compliance.md"
}

@test "QA run FAIL-line checker is a blocking Layer 4h gate" {
    grep -q 'check-qa-run-fail-lines.py' "$ROOT/commands/dr-qa.md"
    grep -q 'orphan line, absent manifest' "$ROOT/commands/dr-qa.md"
}

@test "acceptance template states version and invariant contracts" {
    grep -q 'supersedes_version' "$ROOT/templates/acceptance-contract.md"
    grep -q 'observable invariant' "$ROOT/templates/acceptance-contract.md"
}
