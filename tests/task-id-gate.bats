#!/usr/bin/env bats
#
# task-id-gate — history-agnostic policy on Datarim runtime.
#
# Contract under test (skills/evolution/history-agnostic-gate.md +
# scripts/task-id-gate.sh). Sibling pattern: tests/stack-agnostic-gate.bats.
#
#   T1: clean-pass fixture (process-only prose) → exit 0
#   T2: tune-fail fixture (TUNE-0042 inline) → exit 1
#   T3: dev-fail fixture (DEV-1183 inline) → exit 1
#   T4: escape-hatch-pass fixture (IDs inside <!-- gate:history-allowed -->)
#       → exit 0
#   T5: same-line-marker-fail fixture (bypass attempt) → exit 1
#   T6: --whitelist mechanism — passing the failing tune fixture via whitelist
#       suppresses the failure
#   T7: gate's own contract document is whitelisted by default — exit 0
#   T8: --diff-only ignores pre-existing baseline matches (no diff)
#   T9: --diff-only catches freshly-added task-ID line
#   T10: --diff-only on non-git path → exit 2

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
GATE="$REPO_ROOT/scripts/task-id-gate.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/task-id-gate"

@test "T1: clean-pass fixture exits 0" {
    run "$GATE" "$FIXTURES/clean-pass.md"
    [ "$status" -eq 0 ]
}

@test "T2: tune-fail fixture exits 1" {
    run "$GATE" "$FIXTURES/tune-fail.md"
    [ "$status" -eq 1 ]
}

@test "T3: dev-fail fixture exits 1" {
    run "$GATE" "$FIXTURES/dev-fail.md"
    [ "$status" -eq 1 ]
}

@test "T4: escape-hatch-pass fixture exits 0" {
    run "$GATE" "$FIXTURES/escape-hatch-pass.md"
    [ "$status" -eq 0 ]
}

@test "T5: same-line-marker-fail fixture exits 1 (bypass attempt caught)" {
    run "$GATE" "$FIXTURES/same-line-marker-fail.md"
    [ "$status" -eq 1 ]
}

@test "T6: --whitelist mechanism suppresses tune-fail" {
    run "$GATE" --whitelist "tune-fail.md" "$FIXTURES/tune-fail.md"
    [ "$status" -eq 0 ]
}

@test "T7: gate's own contract doc whitelisted by default" {
    if [ ! -f "$REPO_ROOT/skills/evolution/history-agnostic-gate.md" ]; then
        skip "contract doc not yet present"
    fi
    run "$GATE" "$REPO_ROOT/skills/evolution/history-agnostic-gate.md"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# --diff-only mode (parity with stack-agnostic-gate TUNE-0058 contract).
# -----------------------------------------------------------------------------

setup_diff_repo() {
    DIFF_REPO="$(mktemp -d)"
    (
        cd "$DIFF_REPO"
        git init -q
        git config user.email "test@example.com"
        git config user.name "test"
        cat > runtime.md <<'EOF'
# Baseline

- Pre-existing rule referencing TUNE-0042 in source incident.
- Per DEV-1183, prefer machine-readable output.
EOF
        git add runtime.md
        git commit -q -m "baseline"
    )
}

teardown_diff_repo() {
    [ -n "${DIFF_REPO:-}" ] && rm -rf "$DIFF_REPO"
}

@test "T8: --diff-only ignores pre-existing baseline matches" {
    setup_diff_repo
    run "$GATE" --diff-only "$DIFF_REPO/runtime.md"
    teardown_diff_repo
    [ "$status" -eq 0 ]
}

@test "T9: --diff-only catches freshly-added task-ID" {
    setup_diff_repo
    cat >> "$DIFF_REPO/runtime.md" <<'EOF'

## Follow-up

- See INFRA-0029 for SSH route fallout.
EOF
    run "$GATE" --diff-only "$DIFF_REPO/runtime.md"
    teardown_diff_repo
    [ "$status" -eq 1 ]
}

@test "T10: --diff-only on non-git path exits 2" {
    TMPFILE="$(mktemp)"
    printf '%s\n' "Some content with TUNE-0042." > "$TMPFILE"
    run "$GATE" --diff-only "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 2 ]
}
