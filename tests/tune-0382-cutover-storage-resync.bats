#!/usr/bin/env bats
# tune-0382-cutover-storage-resync.bats — reflection-INFRA-0280 EP-1.
#
# Covers: skills/infra-automation/SKILL.md carries a rule requiring the final
# cutover-window re-sync to cover every stateful storage (not only the
# primary database), so a new-primary-on-stale-snapshot incident class
# (INFRA-0280: Vault re-issued secret_id against stale data) is prevented.

SKILL="$BATS_TEST_DIRNAME/../skills/infra-automation/SKILL.md"

@test "T1 infra-automation SKILL.md has the Cutover Re-sync Scope Rule heading" {
    grep -qE '^## Cutover Re-sync Scope Rule' "$SKILL"
}

@test "T2 rule names Postgres, Mongo, and Vault as example stateful stores" {
    awk '/^## Cutover Re-sync Scope Rule/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -q 'Postgres'
    awk '/^## Cutover Re-sync Scope Rule/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -q 'Mongo'
    awk '/^## Cutover Re-sync Scope Rule/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -q 'Vault'
}

@test "T3 rule states verification must not be DB-only" {
    awk '/^## Cutover Re-sync Scope Rule/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qi 'not just the primary database'
}

@test "T4 rule explains freshness must be verified per-store, not assumed" {
    awk '/^## Cutover Re-sync Scope Rule/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qi 'independent freshness claim'
}
