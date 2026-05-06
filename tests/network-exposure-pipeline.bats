#!/usr/bin/env bats
# TUNE-0109 Phase 2 — pipeline-command integration smoke.
# Verifies that each touched command file references the canonical executor
# (network-exposure-gate.sh / network-exposure-check.sh) and the contract
# skill, so a future refactor cannot silently drop the integration.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CMD="$REPO_ROOT/commands"
}

@test "dr-prd.md references network-exposure-gate.sh" {
    grep -q "network-exposure-gate.sh" "$CMD/dr-prd.md"
}

@test "dr-prd.md references network-exposure-baseline skill" {
    grep -q "network-exposure-baseline" "$CMD/dr-prd.md"
}

@test "dr-prd.md mentions hard_block | advisory_warn | skip verdicts" {
    grep -q "hard_block" "$CMD/dr-prd.md"
    grep -q "advisory_warn" "$CMD/dr-prd.md"
    grep -q "skip" "$CMD/dr-prd.md"
}

@test "dr-plan.md references network-exposure-gate.sh" {
    grep -q "network-exposure-gate.sh" "$CMD/dr-plan.md"
}

@test "dr-plan.md transition checkpoint mentions networking surface gate" {
    grep -q "network-exposure-gate.sh" "$CMD/dr-plan.md"
    grep -qE "hard_block|Network Exposure" "$CMD/dr-plan.md"
}

@test "dr-do.md references network-exposure-check.sh (verifier diff-check)" {
    grep -q "network-exposure-check.sh" "$CMD/dr-do.md"
}

@test "dr-do.md references network-exposure-gate.sh (tiered gate)" {
    grep -q "network-exposure-gate.sh" "$CMD/dr-do.md"
}

@test "dr-do.md documents --skip-exposure-gate override + Ops Bot warning" {
    grep -q -- "--skip-exposure-gate" "$CMD/dr-do.md"
    grep -q "ops.arcanada.one/events" "$CMD/dr-do.md"
}

@test "dr-archive.md references both verifier and gate executor" {
    grep -q "network-exposure-check.sh" "$CMD/dr-archive.md"
    grep -q "network-exposure-gate.sh" "$CMD/dr-archive.md"
}

@test "dr-archive.md mandates external proof for Tier 3 listeners" {
    # Either nmap or external port-scan + waiver paragraph must appear.
    grep -q "Tier 3" "$CMD/dr-archive.md"
    grep -qiE "nmap|port-scan" "$CMD/dr-archive.md"
}

@test "skill references gate executor and rule table" {
    SKILL="$REPO_ROOT/skills/network-exposure-baseline.md"
    grep -q "network-exposure-gate.sh" "$SKILL"
    grep -q "Tiered Gate Rules" "$SKILL"
}
