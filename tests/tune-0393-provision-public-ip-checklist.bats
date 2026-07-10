#!/usr/bin/env bats
# tune-0393-provision-public-ip-checklist.bats — reflection-SPACE-0029 EV-4.
#
# Covers: skills/infra-automation/SKILL.md carries a post-provision checklist
# rule requiring a routable public IP to be recorded in the server inventory
# before a provisioning task closes (root cause: arcana-prod had a null
# public_ip from bootstrap, so an operator SSHing to a known address did not
# recognize the host from the inventory record — SPACE-0029 "dark server"
# false perception).

SKILL="$BATS_TEST_DIRNAME/../skills/infra-automation/SKILL.md"

@test "Q1 infra-automation SKILL.md has the Post-Provision Checklist heading" {
    grep -qE '^## Post-Provision Checklist — Public IP' "$SKILL"
}

@test "Q2 rule says the public IP must not be left null/blank" {
    awk '/^## Post-Provision Checklist/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qi 'null'
}

@test "Q3 rule ties the check to provisioning task closure" {
    awk '/^## Post-Provision Checklist/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qi 'before the provisioning task is closed'
}

@test "Q4 rule mentions an optional lint check as non-blocking" {
    awk '/^## Post-Provision Checklist/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qi 'Optional lint'
}
