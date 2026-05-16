#!/usr/bin/env bats
#
# Structural-guards invariance tests for /dr-init and /dr-archive.
#
# These tests guard the structural protections that remain in place after
# the operator-only contract (frontmatter `disable-model-invocation: true`,
# 🔒 marker, planner/compliance STOP-rule) was removed and agent autonomy
# was restored on the two lifecycle commands.
#
# The contract is enforced in code, not by visibility flags:
#   • `pre-archive-check.sh` runs the schema gate + staged-diff audit at
#     `/dr-archive` Step 0.1.
#   • `datarim-doctor.sh --quiet` probes the thin-index schema at
#     `/dr-init` Step 2.4 self-heal entry point.
#   • The PRE-ARCHIVE CLEAN-GIT CHECK header, blob-swap recipe,
#     Archive Area Mapping (prefix → subdir), and Operator Handoff
#     section template are documented in the command body and the
#     archive template.
#
# If any of these tests fail, an irreversible workspace-mutation path has
# lost its in-code guard and the relaxation of the operator-only contract
# would no longer be safe — restore the missing reference before merging.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
COMMANDS_DIR="${REPO_ROOT}/commands"
TEMPLATES_DIR="${REPO_ROOT}/templates"

# ---------- /dr-archive structural guards ----------

@test "dr-archive.md Step 0.1 invokes scripts/pre-archive-check.sh (schema gate + staged-diff audit)" {
    matches=$(grep -cF "pre-archive-check.sh" "${COMMANDS_DIR}/dr-archive.md")
    [ "$matches" -ge 3 ]
}

@test "dr-archive.md body retains the PRE-ARCHIVE CLEAN-GIT CHECK header" {
    run grep -F "PRE-ARCHIVE CLEAN-GIT CHECK" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

@test "dr-archive.md body retains the blob-swap recipe reference" {
    matches=$(grep -ciF "blob-swap" "${COMMANDS_DIR}/dr-archive.md")
    [ "$matches" -ge 1 ]
}

@test "dr-archive.md body retains the Archive Area Mapping (prefix → subdir) reference" {
    run grep -F "Archive Area Mapping" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

@test "dr-archive.md body retains the Operator Handoff section reference" {
    run grep -E "Operator[- ]Handoff" "${COMMANDS_DIR}/dr-archive.md"
    [ "$status" -eq 0 ]
}

# ---------- /dr-init structural guards ----------

@test "dr-init.md Step 2.4 invokes scripts/datarim-doctor.sh (thin-index schema probe)" {
    matches=$(grep -cF "datarim-doctor.sh" "${COMMANDS_DIR}/dr-init.md")
    [ "$matches" -ge 1 ]
}

@test "dr-init.md retains the STRUCTURAL COMPLIANCE CHECK header" {
    run grep -F "STRUCTURAL COMPLIANCE CHECK" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -eq 0 ]
}

@test "dr-init.md retains the WORKSPACE CROSS-TASK HYGIENE CHECK header" {
    run grep -F "WORKSPACE CROSS-TASK HYGIENE CHECK" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -eq 0 ]
}

# ---------- archive template retains Operator Handoff section ----------

@test "archive-template.md retains the Operator Handoff section template" {
    run grep -E "Operator[- ]Handoff" "${TEMPLATES_DIR}/archive-template.md"
    [ "$status" -eq 0 ]
}
