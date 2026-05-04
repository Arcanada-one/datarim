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

# -----------------------------------------------------------------------------
# TUNE-0058: --diff-only mode. Scan only added lines (`+` prefix in
# `git diff <base> -- <file>`), ignore pre-existing baseline matches.
# Source: TUNE-0044 + TUNE-0056 self-dogfood operator-toll on
# docs/evolution-log.md (3 pre-existing npm/NestJS/vitest matches from old
# entries kept failing the gate every time the file was touched, requiring
# manual `git diff '^+'` verification to prove no fresh leak).
# -----------------------------------------------------------------------------

# Build a throwaway git repo whose HEAD already contains a baseline file with
# stack-specific terms (simulating docs/evolution-log.md). Caller can then add
# more lines (clean or dirty) and invoke the gate with --diff-only.
setup_diff_repo() {
    DIFF_REPO="$(mktemp -d)"
    (
        cd "$DIFF_REPO"
        git init -q
        git config user.email "test@example.com"
        git config user.name "test"
        cat > evolution-log.md <<'EOF'
# Evolution Log

## 2025-01-01 baseline

- Switched from NestJS to plain handlers.
- Replaced npm install with manual lockfile review.
- Vitest suites now run in CI.
EOF
        git add evolution-log.md
        git commit -q -m "baseline"
    )
}

teardown_diff_repo() {
    [ -n "${DIFF_REPO:-}" ] && rm -rf "$DIFF_REPO"
}

@test "T7: --diff-only ignores pre-existing baseline matches (no diff)" {
    setup_diff_repo
    # No new edits — diff against HEAD is empty. Even though file contains
    # NestJS / npm install / Vitest in HEAD, --diff-only must exit 0.
    run "$GATE" --diff-only "$DIFF_REPO/evolution-log.md"
    teardown_diff_repo
    [ "$status" -eq 0 ]
}

@test "T8: --diff-only catches freshly-added stack-specific term" {
    setup_diff_repo
    # Append a stack-specific line. Baseline matches must remain ignored,
    # only the freshly-added Prisma line should trigger FAIL.
    cat >> "$DIFF_REPO/evolution-log.md" <<'EOF'

## 2026-04-29 follow-up

- Migrated database layer to Prisma.
EOF
    run "$GATE" --diff-only "$DIFF_REPO/evolution-log.md"
    teardown_diff_repo
    [ "$status" -eq 1 ]
}

@test "T9: --diff-only with mixed baseline+added — only fresh hits reported" {
    setup_diff_repo
    cat >> "$DIFF_REPO/evolution-log.md" <<'EOF'

## 2026-04-29 follow-up

- Pure prose addition with no stack terms whatsoever.
- Another safe line.
EOF
    run "$GATE" --diff-only "$DIFF_REPO/evolution-log.md"
    teardown_diff_repo
    # Only added lines scanned; added lines clean → exit 0 even though HEAD
    # still has NestJS/npm install/Vitest baseline matches.
    [ "$status" -eq 0 ]
}

@test "T10: --diff-only on non-git path exits 2 (not silent PASS)" {
    TMPFILE="$(mktemp)"
    printf '%s\n' "Some content with NestJS." > "$TMPFILE"
    run "$GATE" --diff-only "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 2 ]
}
