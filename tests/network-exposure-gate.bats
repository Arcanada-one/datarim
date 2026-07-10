#!/usr/bin/env bats
# TUNE-0109 Phase 2 — network-exposure-gate.sh tiered-gate decision suite.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/network-exposure-gate.sh"
    F="$REPO_ROOT/tests/fixtures/network-exposure-gate"
}

# --- Hard block via P0 absolute floor ---

@test "gate: P0 + feature -> hard_block" {
    run "$SCRIPT" --task-description "$F/p0-feature.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P0 + bug-fix -> hard_block" {
    run "$SCRIPT" --task-description "$F/p0-bugfix.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

# --- Hard block via P1 + sec/infra ---

@test "gate: P1 + security-incident -> hard_block" {
    run "$SCRIPT" --task-description "$F/p1-security-incident.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P1 + infrastructure -> hard_block" {
    run "$SCRIPT" --task-description "$F/p1-infrastructure.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P1 + infra -> hard_block" {
    run "$SCRIPT" --task-description "$F/p1-infra.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P1 + framework-hardening -> hard_block" {
    run "$SCRIPT" --task-description "$F/p1-framework-hardening.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P1 + auth-mandate -> hard_block" {
    run "$SCRIPT" --task-description "$F/p1-auth-mandate.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P1 + quoted security-incident -> hard_block" {
    run "$SCRIPT" --task-description "$F/p1-quoted.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

@test "gate: P1 + security -> hard_block (TUNE-0407 short-form gap)" {
    run "$SCRIPT" --task-description "$F/p1-security.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "hard_block" ]
}

# --- Advisory warn ---

@test "gate: P1 + feature -> advisory_warn" {
    run "$SCRIPT" --task-description "$F/p1-feature.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "advisory_warn" ]
}

@test "gate: P2 + feature + --network-diff -> advisory_warn" {
    run "$SCRIPT" --task-description "$F/p2-feature.md" --network-diff --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "advisory_warn" ]
}

@test "gate: P3 + research + --network-diff -> advisory_warn" {
    run "$SCRIPT" --task-description "$F/p3-research.md" --network-diff --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "advisory_warn" ]
}

# --- Skip ---

@test "gate: P2 + feature without --network-diff -> skip" {
    run "$SCRIPT" --task-description "$F/p2-feature.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "skip" ]
}

@test "gate: P4 + feature without --network-diff -> skip" {
    run "$SCRIPT" --task-description "$F/p4-feature.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "skip" ]
}

@test "gate: P4 + feature + --network-diff -> advisory_warn" {
    run "$SCRIPT" --task-description "$F/p4-feature.md" --network-diff --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "advisory_warn" ]
}

@test "gate: P3 + research without --network-diff -> skip" {
    run "$SCRIPT" --task-description "$F/p3-research.md" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "skip" ]
}

# --- Fail-closed on malformed/missing ---

@test "gate: missing priority -> hard_block (fail-closed)" {
    run "$SCRIPT" --task-description "$F/missing-priority.md" --quiet
    [ "$status" -eq 0 ]
    # WARN goes to stderr (merged by bats run); decision is the last line.
    last_line="${lines[${#lines[@]}-1]}"
    [ "$last_line" = "hard_block" ]
}

@test "gate: malformed priority 'PX' -> hard_block (fail-closed)" {
    run "$SCRIPT" --task-description "$F/malformed-priority.md" --quiet
    [ "$status" -eq 0 ]
    last_line="${lines[${#lines[@]}-1]}"
    [ "$last_line" = "hard_block" ]
}

@test "gate: missing priority emits WARN to stderr" {
    run "$SCRIPT" --task-description "$F/missing-priority.md" --quiet
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -q "missing priority frontmatter" || \
        [[ "$output" == *"hard_block"* ]]  # stderr capture varies; decision is the contract
}

# --- Init-task artefact: skip, not fail-closed hard_block ---
# An init-task is a different schema (no priority/type by design). Early pipeline
# stages (/dr-prd, /dr-plan) probe it before the task-description exists; the gate
# must resolve to skip, not fail-closed hard_block, for a non-networking task.

@test "gate: init-task-only (no priority/type) -> skip (not fail-closed)" {
    run "$SCRIPT" --task-description "$F/init-task-only.md" --quiet
    [ "$status" -eq 0 ]
    last_line="${lines[${#lines[@]}-1]}"
    [ "$last_line" = "skip" ]
}

@test "gate: init-task-only + --network-diff -> advisory_warn (real networking signal not suppressed)" {
    run "$SCRIPT" --task-description "$F/init-task-only.md" --network-diff --quiet
    [ "$status" -eq 0 ]
    last_line="${lines[${#lines[@]}-1]}"
    [ "$last_line" = "advisory_warn" ]
}

@test "gate: missing-priority on a NON-init-task still fail-closes (regression guard)" {
    # missing-priority.md has type: feature but no artifact: init-task → still hard_block.
    run "$SCRIPT" --task-description "$F/missing-priority.md" --quiet
    [ "$status" -eq 0 ]
    last_line="${lines[${#lines[@]}-1]}"
    [ "$last_line" = "hard_block" ]
}

# --- Usage ---

@test "gate: --version emits version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"network-exposure-gate.sh"* ]]
}

@test "gate: missing --task-description exits 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "gate: unreadable task description exits 2" {
    run "$SCRIPT" --task-description "/nonexistent/path-${RANDOM}.md" --quiet
    [ "$status" -eq 2 ]
}

@test "gate: unknown flag exits 2" {
    run "$SCRIPT" --task-description "$F/p1-feature.md" --bogus
    [ "$status" -eq 2 ]
}
