#!/usr/bin/env bats
# tune-0461-id-collision-autobump.bats
#
# Verifies: V-AC-01, V-AC-03, V-AC-04 (Group A — markdown-contract assertions)
#           V-AC-05 (Group B — empirical: next-free-id.sh fixture-driven auto-bump)
#
# Group A: grep-based assertions that the probe-before-emit invariant, the
#   pinned max()+1 formula, and auto-bump wording are present in the three
#   canonical shipped surfaces.
#
# Group B: fixture-driven harness that seeds a collision and asserts:
#   (a) a warning is emitted to stderr
#   (b) the returned ID is auto-bumped past the claimed candidate
#
# These are CONTRACT tests (markdown-contract asserts) + FUNCTIONAL tests
# (shell helper). /dr-quick and /dr-init are agent-consumed markdown, not
# binaries; Group A validates their prose contract. Group B validates the
# testable shell helper that implements the same semantics.

CMDS_DIR="${BATS_TEST_DIRNAME}/../commands"
SKILLS_DIR="${BATS_TEST_DIRNAME}/../skills"
HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"

# ── Group A — markdown-contract assertions ────────────────────────────────────

# V-AC-01: probe-before-emit invariant present in BOTH command files
@test "A01: dr-quick.md contains probe-before-emit invariant" {
    grep -iE "do not (emit|announce).*id.*until|probe completes" \
        "${CMDS_DIR}/dr-quick.md"
}

@test "A01: dr-init.md contains probe-before-emit invariant" {
    grep -iE "do not (emit|announce).*id.*until|probe completes" \
        "${CMDS_DIR}/dr-init.md"
}

# V-AC-02: dr-quick.md Stage Header no longer forces line-1 ID
@test "A02: dr-quick.md Stage Header does not say 'first line of every response'" {
    # The old wording "Every operator-facing response begins with ... as the first line"
    # must be gone from the Stage Header section.
    run grep -c "Every operator-facing response begins with" "${CMDS_DIR}/dr-quick.md"
    [ "$output" = "0" ]
}

# V-AC-03: pinned formula present in all three files (grep -F exact match)
FORMULA="max(claimed across documentation/archive ∪ datarim/tasks.md ∪ datarim/backlog.md) + 1"

@test "A03: dr-quick.md contains the pinned max()+1 formula" {
    grep -F "${FORMULA}" "${CMDS_DIR}/dr-quick.md"
}

@test "A03: dr-init.md contains the pinned max()+1 formula" {
    grep -F "${FORMULA}" "${CMDS_DIR}/dr-init.md"
}

@test "A03: task-identity-and-context.md contains the pinned max()+1 formula" {
    grep -F "${FORMULA}" \
        "${SKILLS_DIR}/datarim-system/task-identity-and-context.md"
}

# V-AC-04: auto-bump behaviour documented in all three files
@test "A04: dr-quick.md contains auto-bump/next-free-id wording" {
    grep -iE "auto.?bump|next free id" "${CMDS_DIR}/dr-quick.md"
}

@test "A04: dr-init.md contains auto-bump/next-free-id wording" {
    grep -iE "auto.?bump|next free id" "${CMDS_DIR}/dr-init.md"
}

@test "A04: task-identity-and-context.md contains auto-bump/next-free-id wording" {
    grep -iE "auto.?bump|next free id" \
        "${SKILLS_DIR}/datarim-system/task-identity-and-context.md"
}

# ── Group B — fixture-driven auto-bump harness (V-AC-05) ─────────────────────

setup() {
    # Create a temporary fixture directory for each test
    FIXTURE_DIR="$(mktemp -d)"
    mkdir -p "${FIXTURE_DIR}/datarim"
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

@test "B01: next-free-id.sh returns PREFIX-0001 when no IDs exist" {
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]
}

@test "B02: next-free-id.sh picks max+1 from tasks.md" {
    printf -- '- TUNE-0005 · some task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0003 · another task\n' >> "${FIXTURE_DIR}/datarim/tasks.md"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0006" ]
}

@test "B03: next-free-id.sh picks max across all three surfaces" {
    # tasks.md: TUNE-0003, backlog.md: TUNE-0005, archive: TUNE-0007
    printf -- '- TUNE-0003 · task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-0005 · backlog item\n' > "${FIXTURE_DIR}/datarim/backlog.md"
    printf '# archive-TUNE-0007.md\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-0007.md"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0008" ]
}

@test "B04: next-free-id.sh auto-bumps when max+1 is already claimed (collision)" {
    # Seed TUNE-9999 as the highest known ID — candidate would be TUNE-10000
    # Pre-seed TUNE-10000 in backlog to force a collision on the first candidate
    printf -- '- TUNE-9999 · high-watermark task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-10000 · parallel session claimed this first\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"

    # Use separate stdout/stderr capture so the warning line does not pollute
    # the ID comparison (bats `run` mixes stderr into $output by default)
    STDOUT_FILE="$(mktemp)"
    STDERR_FILE="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"
    STATUS=$?
    CHOSEN_ID="$(cat "${STDOUT_FILE}")"
    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"

    [ "$STATUS" -eq 0 ]
    # Should auto-bump past TUNE-10000 → TUNE-10001
    [ "${CHOSEN_ID}" = "TUNE-10001" ]
}

@test "B05: next-free-id.sh emits a WARNING to stderr on collision" {
    # Same collision setup: TUNE-9999 in tasks, TUNE-10000 in backlog
    printf -- '- TUNE-9999 · high-watermark task\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    printf -- '- TUNE-10000 · parallel session claimed this first\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"

    # Capture stderr separately
    STDOUT_FILE="$(mktemp)"
    STDERR_FILE="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"
    STATUS=$?

    [ "$STATUS" -eq 0 ]
    # Stdout: auto-bumped ID
    CHOSEN_ID="$(cat "${STDOUT_FILE}")"
    [ "$CHOSEN_ID" = "TUNE-10001" ]
    # Stderr: warning line present (regex V-AC-05)
    grep -iE "WARNING.*auto.?bump|parallel.session|already claimed" "${STDERR_FILE}"

    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"
}

@test "B06: next-free-id.sh rejects invalid prefix (non-uppercase)" {
    run bash "${HELPER}" "tune" "${FIXTURE_DIR}"
    [ "$status" -ne 0 ]
    echo "$output" | grep -iE "invalid prefix"
}

@test "B07: next-free-id.sh handles TUNE-9999 boundary — absorbs TUNE-0229 DoD" {
    # This is the TUNE-0229 absorbed requirement:
    # When the highest claimed ID is TUNE-9999, the helper must correctly
    # compute TUNE-10000 as the next free ID (no 4-digit truncation).
    printf -- '- TUNE-9999 · task at boundary\n' > "${FIXTURE_DIR}/datarim/tasks.md"

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    # 10000 is 5 digits — the helper must handle this correctly
    [ "$output" = "TUNE-10000" ]
}
