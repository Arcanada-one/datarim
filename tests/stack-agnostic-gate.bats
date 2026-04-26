#!/usr/bin/env bats
#
# TUNE-0039 — stack-agnostic gate.
#
# Contract under test (skills/evolution/stack-agnostic-gate.md +
# scripts/stack-agnostic-gate.sh):
#   T1: VERD-0010 fixture (NestJS smoke + npm audit) → exit 1
#   T2: VERD-0021 fixture (fetch migration, multi-PM list, audit recipes) → exit 1
#   T3: process-only fixture (dogfooding clause) → exit 0
#   T4: tech-stack.md whitelisted by default — gate must PASS even with
#       NestJS-laden content (proves --whitelist mechanic works).
#   T5: cleaned commands/dr-plan.md PASSes — regression invariant: if a
#       future edit re-introduces stack-specific wording outside an
#       <!-- gate:example-only --> block, this test catches it.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
GATE="$REPO_ROOT/scripts/stack-agnostic-gate.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/stack-agnostic-gate"

@test "T1: VERD-0010 FAIL fixture exits 1" {
    run "$GATE" "$FIXTURES/verd-0010-fail.md"
    [ "$status" -eq 1 ]
}

@test "T2: VERD-0021 FAIL fixture exits 1" {
    run "$GATE" "$FIXTURES/verd-0021-fail.md"
    [ "$status" -eq 1 ]
}

@test "T3: process-only PASS fixture exits 0" {
    run "$GATE" "$FIXTURES/process-only-pass.md"
    [ "$status" -eq 0 ]
}

@test "T4: whitelist mechanism — tech-stack.md exempt by default" {
    run "$GATE" "$REPO_ROOT/skills/tech-stack.md"
    [ "$status" -eq 0 ]
}

@test "T5: cleaned commands/dr-plan.md is gate-clean (regression invariant)" {
    run "$GATE" "$REPO_ROOT/commands/dr-plan.md"
    [ "$status" -eq 0 ]
}

@test "T6: whitelist precedent — deployment-patterns.md exempt by default (TUNE-0040)" {
    # By-design stack-aware deployment incidents reference (parallel to
    # tech-stack.md). Whitelisted in scripts/stack-agnostic-gate.sh
    # WHITELIST array; precedent rationale documented in
    # skills/evolution/stack-agnostic-gate.md § Whitelist.
    run "$GATE" "$REPO_ROOT/skills/ai-quality/deployment-patterns.md"
    [ "$status" -eq 0 ]
}
