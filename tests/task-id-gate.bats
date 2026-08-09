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
#   T11-T14: regression invariants — skills/, commands/, agents/, templates/
#            scopes stay gate-clean (parallel to stack-agnostic-gate.bats T5)

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
GATE="${TASK_ID_GATE_OVERRIDE:-$REPO_ROOT/scripts/task-id-gate.sh}"
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
    run "$GATE" --whitelist "$FIXTURES/tune-fail.md" "$FIXTURES/tune-fail.md"
    [ "$status" -eq 0 ]
}

@test "T6b: whitelist matching is exact, not suffix-based" {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/spoof/$FIXTURES"
    cp "$FIXTURES/tune-fail.md" "$TMPROOT/spoof/$FIXTURES/tune-fail.md"
    run "$GATE" --whitelist "$FIXTURES/tune-fail.md" "$TMPROOT/spoof/$FIXTURES/tune-fail.md"
    rm -rf "$TMPROOT"
    [ "$status" -eq 1 ]
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

@test "T10b: directory --diff-only with invalid base exits 2" {
    setup_diff_repo
    run "$GATE" --diff-only definitely-not-a-valid-ref "$DIFF_REPO"
    teardown_diff_repo
    [ "$status" -eq 2 ]
}

@test "T10c: directory --diff-only scans an untracked contaminating file" {
    setup_diff_repo
    printf '%s\n' 'New rule from NOVEL-1234.' > "$DIFF_REPO/new.md"
    run "$GATE" --diff-only "$DIFF_REPO"
    teardown_diff_repo
    [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# --base-commit mode (TUNE-0425: named-flag variant of --diff-only).
# These three tests cover: (a) pre-existing foreign ID ignored, (b) newly-added
# foreign ID caught, (c) no-flag full-file scan unchanged (regression guard).
# -----------------------------------------------------------------------------

@test "T15: --base-commit ignores pre-existing foreign TASK-ID (added-lines-only pass)" {
    setup_diff_repo
    BASE_SHA="$(git -C "$DIFF_REPO" rev-parse HEAD)"
    # Add a clean line — no new task-ID introduced.
    printf '\n## Update\n\n- Minor clarification.\n' >> "$DIFF_REPO/runtime.md"
    run "$GATE" --base-commit "$BASE_SHA" "$DIFF_REPO/runtime.md"
    teardown_diff_repo
    [ "$status" -eq 0 ]
}

@test "T16: --base-commit catches newly-added foreign TASK-ID" {
    setup_diff_repo
    BASE_SHA="$(git -C "$DIFF_REPO" rev-parse HEAD)"
    # Introduce a new task-ID reference in an uncommitted edit.
    printf '\n## Follow-up\n\n- See ABCD-0001 for context.\n' >> "$DIFF_REPO/runtime.md"
    run "$GATE" --base-commit "$BASE_SHA" "$DIFF_REPO/runtime.md"
    teardown_diff_repo
    [ "$status" -eq 1 ]
}

@test "T17: no-flag full-file scan still fails on pre-existing foreign TASK-ID (byte-identical regression)" {
    setup_diff_repo
    # runtime.md at baseline already contains TUNE-0042 and DEV-1183.
    run "$GATE" "$DIFF_REPO/runtime.md"
    teardown_diff_repo
    [ "$status" -eq 1 ]
}

@test "T11: skills/ scope is gate-clean (regression invariant)" {
    run "$GATE" "$REPO_ROOT/skills"
    [ "$status" -eq 0 ]
}

@test "T12: commands/ scope is gate-clean (regression invariant)" {
    run "$GATE" "$REPO_ROOT/commands"
    [ "$status" -eq 0 ]
}

@test "T13: agents/ scope is gate-clean (regression invariant)" {
    run "$GATE" "$REPO_ROOT/agents"
    [ "$status" -eq 0 ]
}

@test "T14: templates/ scope is gate-clean (regression invariant)" {
    run "$GATE" "$REPO_ROOT/templates"
    [ "$status" -eq 0 ]
}

@test "T18: documentation/how-to scope is gate-clean" {
    run "$GATE" "$REPO_ROOT/documentation/how-to"
    [ "$status" -eq 0 ]
}

@test "T19: documentation/reference scope is gate-clean" {
    run "$GATE" "$REPO_ROOT/documentation/reference"
    [ "$status" -eq 0 ]
}

@test "T20: documentation/explanation scope is gate-clean" {
    run "$GATE" "$REPO_ROOT/documentation/explanation"
    [ "$status" -eq 0 ]
}

@test "T21: documentation/tutorials scope is gate-clean" {
    run "$GATE" "$REPO_ROOT/documentation/tutorials"
    [ "$status" -eq 0 ]
}

@test "T22: root CLAUDE.md is gate-clean" {
    run "$GATE" "$REPO_ROOT/CLAUDE.md"
    [ "$status" -eq 0 ]
}

@test "T23: root README.md is gate-clean" {
    run "$GATE" "$REPO_ROOT/README.md"
    [ "$status" -eq 0 ]
}

assert_extension_is_scanned() {
    local extension="$1"
    local tmpdir
    tmpdir="$(mktemp -d)"
    printf '%s\n' 'Leaked NOVEL-1234 provenance.' > "$tmpdir/leak.$extension"
    run "$GATE" "$tmpdir"
    rm -rf "$tmpdir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"leak.$extension"* ]]
}

@test "E1: directory scan includes md" { assert_extension_is_scanned md; }
@test "E2: directory scan includes template" { assert_extension_is_scanned template; }
@test "E3: directory scan includes sh" { assert_extension_is_scanned sh; }
@test "E4: directory scan includes yaml" { assert_extension_is_scanned yaml; }
@test "E5: directory scan includes yml" { assert_extension_is_scanned yml; }

@test "E6: newline-bearing filename cannot bypass directory scan" {
    TMPROOT="$(mktemp -d)"
    printf '%s\n' 'Leaked NOVEL-1234 provenance.' > "$TMPROOT/line
break.md"
    run "$GATE" "$TMPROOT"
    rm -rf "$TMPROOT"
    [ "$status" -eq 1 ]
}

@test "E7: a nested fake tests/fixtures path is not globally excluded" {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/nested/tests/fixtures"
    printf '%s\n' 'Leaked NOVEL-1234 provenance.' > "$TMPROOT/nested/tests/fixtures/leak.md"
    run "$GATE" "$TMPROOT"
    rm -rf "$TMPROOT"
    [ "$status" -eq 1 ]
}

@test "E8: a symlink target fails closed" {
    TMPROOT="$(mktemp -d)"
    printf '%s\n' 'Clean prose.' > "$TMPROOT/real.md"
    ln -s "$TMPROOT/real.md" "$TMPROOT/link.md"
    run "$GATE" "$TMPROOT/link.md"
    rm -rf "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "E9: an unreadable input fails closed" {
    TMPROOT="$(mktemp -d)"
    printf '%s\n' 'Clean prose.' > "$TMPROOT/unreadable.md"
    chmod 000 "$TMPROOT/unreadable.md"
    run "$GATE" "$TMPROOT/unreadable.md"
    chmod 600 "$TMPROOT/unreadable.md"
    rm -rf "$TMPROOT"
    [ "$status" -eq 2 ]
}

make_hatch_fixture() {
    HATCH_FILE="$(mktemp)"
    printf '%s\n' "$@" > "$HATCH_FILE"
}

remove_hatch_fixture() {
    rm -f "${HATCH_FILE:-}"
}

assert_hatch_fails() {
    make_hatch_fixture "$@"
    run "$GATE" "$HATCH_FILE"
    remove_hatch_fixture
    [ "$status" -eq 1 ]
}

@test "H1: balanced unlabeled illustrative hatch passes" {
    make_hatch_fixture '<!-- gate:history-allowed -->' 'Example TASK-0001' '<!-- /gate:history-allowed -->'
    run "$GATE" "$HATCH_FILE"
    remove_hatch_fixture
    [ "$status" -eq 0 ]
}

@test "H2: same-line open and close fails without an earlier sentinel" {
    assert_hatch_fails '<!-- gate:history-allowed -->Example TASK-0001<!-- /gate:history-allowed -->'
}

@test "H3: unmatched opener cannot hide a later ID" {
    assert_hatch_fails '<!-- gate:history-allowed -->' 'Example TASK-0001' 'Leaked NOVEL-1234 provenance.'
}

@test "H4: unmatched closer fails" {
    assert_hatch_fails '<!-- /gate:history-allowed -->'
}

@test "H5: nested opener fails" {
    assert_hatch_fails '<!-- gate:history-allowed -->' '<!-- gate:history-allowed -->' '<!-- /gate:history-allowed -->'
}

@test "H6: opener with payload fails" {
    assert_hatch_fails '<!-- gate:history-allowed --> payload'
}

@test "H7: closer with payload fails" {
    assert_hatch_fails '<!-- gate:history-allowed -->' '<!-- /gate:history-allowed --> payload'
}

@test "H8: provenance labels inside hatches fail in all supported forms" {
    local form
    for form in \
        'Source: TASK-0001' \
        'source task: TASK-0001' \
        '**Reference:** TASK-0001' \
        '> **Created:** TASK-0001' \
        '- Parent epic: TASK-0001' \
        'source: TASK-0001'; do
        make_hatch_fixture '<!-- gate:history-allowed -->' "$form" '<!-- /gate:history-allowed -->'
        run "$GATE" "$HATCH_FILE"
        remove_hatch_fixture
        [ "$status" -eq 1 ]
    done
}

@test "H9: provenance label followed by an ID on the next line fails" {
    assert_hatch_fails '<!-- gate:history-allowed -->' '**Source:**' 'TASK-0001' '<!-- /gate:history-allowed -->'
}

@test "H10: table, ordered-list, and task-list provenance decoration cannot launder IDs" {
    local form
    for form in \
        '| Source: TASK-0001 |' \
        '1. Reference: TASK-0001' \
        '- [ ] Created: TASK-0002'; do
        make_hatch_fixture '<!-- gate:history-allowed -->' "$form" '<!-- /gate:history-allowed -->'
        run "$GATE" "$HATCH_FILE"
        remove_hatch_fixture
        [ "$status" -eq 1 ]
    done
}

@test "F1: scanner subprocess failure exits 2 instead of returning a false PASS" {
    run bash -c 'awk() { return 127; }; export -f awk; exec "$1" "$2"' \
        _ "$GATE" "$FIXTURES/clean-pass.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"scanner error"* ]]
}

@test "F2: shipped shell gate enables the S1 strict-mode floor" {
    run grep -F 'set -euo pipefail' "$GATE"
    [ "$status" -eq 0 ]
    run grep -F "IFS=\$'\\n\\t'" "$GATE"
    [ "$status" -eq 0 ]
}

@test "B1: task-ID boundaries are portable and do not match adjacent word characters" {
    TMPFILE="$(mktemp)"
    printf '%s\n' 'xTASK-0001 TASK-00010 _TASK-0001 TASK-0001_' > "$TMPFILE"
    run "$GATE" "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 0 ]
}

@test "C1: security workflow invokes every governed target" {
    local target
    for target in skills agents commands templates documentation/how-to documentation/reference documentation/explanation documentation/tutorials CLAUDE.md README.md; do
        run grep -F "$target" "$REPO_ROOT/.github/workflows/security.yml"
        [ "$status" -eq 0 ]
    done
}

# -----------------------------------------------------------------------------
# /dr-compliance caller wiring (anti-decay). The gate is only useful if a
# pipeline stage actually invokes it: full-file mode for newly-touched runtime
# files, --diff-only for shared-history files. Behavioural proof of the two
# modes lives above (T8/T9: --diff-only suppresses pre-existing baseline IDs
# and catches freshly-added ones; T17: full-file still fails on baseline IDs).
# These cases pin the wiring prose in commands/dr-compliance.md.
# -----------------------------------------------------------------------------

DR_COMPLIANCE="$REPO_ROOT/commands/dr-compliance.md"

@test "W1: dr-compliance.md carries the HISTORY-AGNOSTIC GATE step invoking task-id-gate.sh" {
    [ -f "$DR_COMPLIANCE" ]
    run grep -c 'HISTORY-AGNOSTIC GATE' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'scripts/task-id-gate.sh' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "W2: dr-compliance wiring prescribes --diff-only for shared-history files" {
    run grep -c 'task-id-gate.sh --diff-only' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'suppressing pre-existing baseline matches' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "W3: dr-compliance wiring prescribes full-file mode for newly-touched runtime files" {
    run grep -c 'full-file mode' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'clean end-to-end, not merely diff-clean' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "W4: dr-compliance NON-COMPLIANT routing bound to gate exit 1" {
    run grep -c 'Exit `1` from either invocation' "$DR_COMPLIANCE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
