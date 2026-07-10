#!/usr/bin/env bats
#
# Command-bound Post-Step Self-Verification Hook wiring (TUNE-0138).
#
# Architectural decision: the automatic post-step self-verification hook is
# bound to the COMMAND file (which owns the stage), mirroring the snapshot
# emission contract. Each pipeline-stage command that produces a verifiable
# artifact (`dr-prd`, `dr-plan`, `dr-do`) declares a
# `## Post-Step Self-Verification Hook (Automatic)` section carrying:
#   (a) a reference to the canonical `skills/self-verification/SKILL.md`,
#   (b) the complexity-tiering contract (L1 OFF / L2 = 1 agent / L3+ = 3 parallel),
#   (c) the deterministic Layer 1 floor invocation (`dr-verify-floor.sh`),
#   (d) the advisory/blocking mode env var and the kill switch.
# The recipe body lives in `skills/self-verification/SKILL.md` (single source
# of truth); the command sections wire it into the pipeline.
#
# Checks loop over HOOK_COMMANDS, so registering a new hooked command is a
# single-line edit.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# Commands that carry the automatic post-step self-verification hook.
HOOK_COMMANDS=(
    "dr-prd"
    "dr-plan"
    "dr-do"
)

# Canonical count of hooked commands.
EXPECTED_HOOK_COUNT=3

# ---------- Check 1: section header present in every hooked command ----------

@test "every hooked command carries '## Post-Step Self-Verification Hook (Automatic)' section" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -F '## Post-Step Self-Verification Hook (Automatic)' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing hook section in ${base}.md"; return 1; }
    done
}

# ---------- Check 2: references canonical self-verification skill ----------

@test "every hooked command references skills/self-verification/SKILL.md" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -F 'skills/self-verification/SKILL.md' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing self-verification skill reference in ${base}.md"; return 1; }
    done
}

# ---------- Check 3: declares the complexity-tiering contract ----------

@test "every hooked command declares the L1-OFF / L2-1-agent / L3-3-parallel tiering" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -F 'L1 OFF / L2 = 1 agent / L3+ = 3 parallel' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing complexity-tiering contract in ${base}.md"; return 1; }
    done
}

# ---------- Check 4: wires the deterministic Layer 1 floor invocation ----------

@test "every hooked command invokes dr-verify-floor.sh (Layer 1 floor)" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -F 'dr-verify-floor.sh' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing dr-verify-floor.sh invocation in ${base}.md"; return 1; }
    done
}

# ---------- Check 5: declares kill switch + advisory/hard mode env vars -------

@test "every hooked command declares the kill switch DATARIM_DISABLE_VERIFY_HOOK" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -F 'DATARIM_DISABLE_VERIFY_HOOK=1' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing kill-switch declaration in ${base}.md"; return 1; }
    done
}

@test "every hooked command declares the advisory/hard mode env var DATARIM_VERIFY_HOOK_MODE" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -F 'DATARIM_VERIFY_HOOK_MODE' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing DATARIM_VERIFY_HOOK_MODE declaration in ${base}.md"; return 1; }
    done
}

# ---------- Check 6: findings-only discipline stated ----------

@test "every hooked command states findings-only (no auto-fix)" {
    for base in "${HOOK_COMMANDS[@]}"; do
        run grep -iF 'Findings-only' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing findings-only discipline in ${base}.md"; return 1; }
    done
}

# ---------- Check 7: hook section precedes Stage Snapshot Emission ------------

@test "hook section is emitted before Stage Snapshot Emission in every hooked command" {
    for base in "${HOOK_COMMANDS[@]}"; do
        file="${REPO_ROOT}/commands/${base}.md"
        hook_line="$(grep -n '## Post-Step Self-Verification Hook (Automatic)' "$file" | head -1 | cut -d: -f1)"
        snap_line="$(grep -n '## Stage Snapshot Emission (Mandatory Terminal Step)' "$file" | head -1 | cut -d: -f1)"
        [ -n "$hook_line" ] || { echo "no hook section in ${base}.md"; return 1; }
        [ -n "$snap_line" ] || { echo "no snapshot section in ${base}.md"; return 1; }
        [ "$hook_line" -lt "$snap_line" ] || { echo "hook section not before snapshot in ${base}.md ($hook_line >= $snap_line)"; return 1; }
    done
}

# ---------- AC aggregate gate ----------

@test "AC — on-disk hook-section count matches the canonical hooked-command count" {
    count="$(grep -lF '## Post-Step Self-Verification Hook (Automatic)' "${REPO_ROOT}/commands/"dr-*.md | wc -l | tr -d ' ')"
    [ "$count" -eq "$EXPECTED_HOOK_COUNT" ] || { echo "expected ${EXPECTED_HOOK_COUNT} hooked commands, found ${count}"; return 1; }
}

@test "AC — HOOK_COMMANDS length matches the canonical hooked-command count" {
    [ "${#HOOK_COMMANDS[@]}" -eq "$EXPECTED_HOOK_COUNT" ]
}
