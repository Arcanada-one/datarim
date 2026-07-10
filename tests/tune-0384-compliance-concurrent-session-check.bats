#!/usr/bin/env bats
#
# Compliance Infrastructure Checklist "Concurrent-Session Check" regression guard.
#
# Stage-rule contract: skills/compliance/SKILL.md § Infrastructure Checklist
# MUST keep the concurrent-session check — when a task modifies access to
# shared infra (NAS, Vault, shared runner), grep active
# datarim/.auto-mode-active markers across sibling workspaces and flag
# provisioning-conflict risk. Prevents two parallel sessions from racing
# each other's provisioning steps against the same resource.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
COMPLIANCE_SKILL="$REPO_ROOT/skills/compliance/SKILL.md"

@test "T1: compliance SKILL.md contains the Concurrent-Session Check item" {
    [ -f "$COMPLIANCE_SKILL" ]
    run grep -F "Concurrent-Session Check (shared infra)" "$COMPLIANCE_SKILL"
    [ "$status" -eq 0 ]
}

@test "T2: check greps active auto-mode-active markers" {
    run grep -F "datarim/.auto-mode-active" "$COMPLIANCE_SKILL"
    [ "$status" -eq 0 ]
}

@test "T3: check names the shared-infra examples (NAS, Vault, shared runner)" {
    run grep -F "NAS, Vault, a shared CI runner" "$COMPLIANCE_SKILL"
    [ "$status" -eq 0 ]
}
