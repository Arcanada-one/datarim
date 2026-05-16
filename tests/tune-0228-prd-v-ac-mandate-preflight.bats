#!/usr/bin/env bats
#
# /dr-prd V-AC pre-flight against active ecosystem mandates.
#
# Contract under test (dev-tools/check-v-ac-mandate-preflight.sh +
# dev-tools/public-surface-forbidden.regex):
#   T1: V-AC line with PRD-PFX-NNNN literal (forbidden by default regex) -> WARNING, exit 0
#   T2: V-AC line with reflection-PFX-NNNN literal -> WARNING, exit 0
#   T3: V-AC text with safe content -> stdout silent, exit 0
#   T4: PRD without Success Criteria + no AC markers -> stdout silent, exit 0
#   T5: --prd /nonexistent -> stderr ERROR, exit 2 (usage)
#   T6: --prd real --regex /nonexistent -> stderr ERROR, exit 2 (usage)
#   T7: Forbidden literal in § Risks (outside V-AC scope) -> stdout silent, exit 0
#   T8: --regex override loads consumer-extended pattern set (contract surface reuse) -> WARNING, exit 0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPT="$REPO_ROOT/dev-tools/check-v-ac-mandate-preflight.sh"
DEFAULT_REGEX="$REPO_ROOT/dev-tools/public-surface-forbidden.regex"

setup() {
    TMPDIR="$(mktemp -d)"
}

teardown() {
    [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"
}

@test "T1: V-AC line with PRD-PFX-NNNN literal triggers WARNING (exit 0)" {
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example

## Success Criteria

- V-AC-1: see PRD-AUTH-0001 follow-up for context.
- V-AC-2: plain safe text.
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "T2: V-AC line with reflection-PFX-NNNN literal triggers WARNING (exit 0)" {
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example

## Success Criteria

- V-AC-1: mirrors reflection-AUTH-0001 decision.
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "T3: V-AC text with safe content is silent (exit 0)" {
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example

## Success Criteria

- V-AC-1: VERSION file equals 2.11 and bats suite is green.
- V-AC-2: shellcheck reports zero warnings on touched scripts.
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T4: PRD without Success Criteria heading or V-AC markers is silent (exit 0)" {
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example

## Context

Plain prose without any verification block.

## Risks

Generic risk statement.
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T5: --prd /nonexistent emits ERROR and exits 2 (usage)" {
    run "$SCRIPT" --prd "$TMPDIR/does-not-exist.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "T6: --regex /nonexistent emits ERROR and exits 2 (usage)" {
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md" --regex "$TMPDIR/nope.regex"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "T7: forbidden literal outside V-AC scope (§ Risks) is silent (exit 0)" {
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example

## Success Criteria

- V-AC-1: plain safe text without forbidden patterns.

## Risks

- Reference to PRD-AUTH-0001 — internal-only commentary, should NOT trigger gate.
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T8: --regex override loads consumer-extended pattern set (contract surface reuse)" {
    cat > "$TMPDIR/custom.regex" <<'EOF'
# Consumer-extended pattern set.
\bTUNE-[0-9]{4}\b
EOF
    cat > "$TMPDIR/prd.md" <<'EOF'
# PRD example

## Success Criteria

- V-AC-1: align with TUNE-0001 follow-up.
EOF
    run "$SCRIPT" --prd "$TMPDIR/prd.md" --regex "$TMPDIR/custom.regex"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}
