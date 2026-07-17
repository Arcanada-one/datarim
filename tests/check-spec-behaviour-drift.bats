#!/usr/bin/env bats
# check-spec-behaviour-drift.bats — regression guard for shipped-spec ↔ actual-behaviour
# drift reconciled by the spec/behaviour audit. Each assertion pins a spec claim to the
# behaviour it must match, so a future edit that reintroduces the drift fails CI.
#
# Covered drifts:
#   - writer.md must document the LinkedIn-English authoring rule (was operator-memory only).
#   - dr-doctor.md must cite the real /dr-init self-heal probe step (Step 2.4), not the
#     stale "Step 0.6" that never existed in dr-init.md.
#   - dr-edit.md's critical-claim source count must match the factcheck skill it loads
#     (critical => 3+ sources; the 2+ figure is the factcheck `high` tier).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WRITER="$REPO_ROOT/agents/writer.md"
    DR_DOCTOR="$REPO_ROOT/commands/dr-doctor.md"
    DR_INIT="$REPO_ROOT/commands/dr-init.md"
    DR_EDIT="$REPO_ROOT/commands/dr-edit.md"
    FACTCHECK="$REPO_ROOT/skills/factcheck/SKILL.md"
}

# --- Drift 2: writer LinkedIn-English rule is documented in the spec ---

@test "writer.md documents the LinkedIn-English authoring rule" {
    run grep -Eiq 'LinkedIn posts are authored in English' "$WRITER"
    [ "$status" -eq 0 ]
}

# --- Drift 3: dr-doctor cites the real /dr-init probe step, not the stale one ---

@test "dr-doctor.md carries no stale '/dr-init Step 0.6' citation" {
    run grep -Fq '/dr-init` Step 0.6' "$DR_DOCTOR"
    [ "$status" -ne 0 ]
}

@test "dr-doctor.md cites the real self-heal probe step (2.4)" {
    run grep -Fq 'Step 2.4' "$DR_DOCTOR"
    [ "$status" -eq 0 ]
}

@test "dr-init.md actually defines the self-heal probe at Step 2.4" {
    run grep -Eq '^2\.4\.' "$DR_INIT"
    [ "$status" -eq 0 ]
}

# --- Drift 4: dr-edit critical-claim source count matches the factcheck skill ---

@test "dr-edit.md requires 3+ sources for critical claims" {
    run grep -Eq 'critical claims, cross-reference with 3\+' "$DR_EDIT"
    [ "$status" -eq 0 ]
}

@test "factcheck skill's critical tier requires 3+ sources (source of truth)" {
    run grep -Eiq 'critical.*3\+ sources|3\+ sources' "$FACTCHECK"
    [ "$status" -eq 0 ]
}
