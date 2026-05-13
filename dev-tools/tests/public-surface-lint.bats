#!/usr/bin/env bats
#
# bats spec for dev-tools/public-surface-lint.sh — Public Surface Hygiene
# Mandate gate. Covers: positive (clean exit 0), negative (forbidden patterns
# exit 1), edge (empty regex / missing regex / no paths).

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../public-surface-lint.sh"
    REGEX="${BATS_TEST_DIRNAME}/../public-surface-forbidden.regex"
    WORK="$(mktemp -d)"
    cd "$WORK"
}

teardown() {
    rm -rf "$WORK"
}

@test "clean public surface — exit 0" {
    cat >README.md <<'EOF'
# my-package

Validate, repair, retry LLM structured output. Two-pass orchestrator.
Output-guard middleware shipped in v0.2.0.
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 0 ]
}

@test "task-id-like prefix without PRD/creative/plans/insights — exit 0" {
    cat >README.md <<'EOF'
# my-package

Reference: see commit hash a1b2c3d4. Issue: #123. Version v1.2.3.
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 0 ]
}

@test "PRD-X-NNNN reference — exit 1" {
    cat >README.md <<'EOF'
Design rationale per PRD-CONN-0087.
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 1 ]
}

@test "creative-X-NNNN reference — exit 1" {
    cat >README.md <<'EOF'
See creative-CONN-0087 for the two-pass orchestrator decision.
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 1 ]
}

@test "plans-X-NNNN reference — exit 1" {
    cat >README.md <<'EOF'
Per plans-CONN-0089 § Rollback Strategy.
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 1 ]
}

@test "internal datarim/tasks/ link — exit 1" {
    cat >README.md <<'EOF'
Source: https://github.com/Arcanada-one/datarim/blob/main/datarim/tasks/CONN-0087-task-description.md
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 1 ]
}

@test "M2 milestone code — exit 1" {
    cat >README.md <<'EOF'
v0.1.0 in progress per M2 milestone.
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md
    [ "$status" -eq 1 ]
}

@test "skips dist/ build/ node_modules/" {
    mkdir -p dist node_modules
    echo "creative-CONN-0001 leak in dist" >dist/index.js
    echo "creative-CONN-0001 leak in node_modules" >node_modules/foo.md
    cat >README.md <<'EOF'
clean README
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md dist node_modules
    [ "$status" -eq 0 ]
}

@test "--report on failure prints matches" {
    cat >README.md <<'EOF'
Per PRD-CONN-0001 the design...
EOF
    run "$SCRIPT" --regex "$REGEX" --paths README.md --report
    [ "$status" -eq 1 ]
    [[ "$output" == *"PRD-CONN-0001"* ]]
}

@test "--report on success prints PASS" {
    echo "clean" >README.md
    run "$SCRIPT" --regex "$REGEX" --paths README.md --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "missing regex file — exit 2" {
    echo "clean" >README.md
    run "$SCRIPT" --regex /no/such/file.regex --paths README.md
    [ "$status" -eq 2 ]
}

@test "empty regex file (only comments) — exit 2" {
    cat >empty.regex <<'EOF'
# only comments
# no patterns
EOF
    echo "clean" >README.md
    run "$SCRIPT" --regex empty.regex --paths README.md
    [ "$status" -eq 2 ]
}

@test "no paths exist — exit 0 (no-op)" {
    run "$SCRIPT" --regex "$REGEX" --paths nonexistent1 nonexistent2
    [ "$status" -eq 0 ]
}

@test "unknown argument — exit 2" {
    echo "clean" >README.md
    run "$SCRIPT" --regex "$REGEX" --paths README.md --bogus
    [ "$status" -eq 2 ]
}
