#!/usr/bin/env bats
# tune-0383-cutover-config-files-probe.bats — reflection-INFRA-0280 EP-2.
#
# Covers: skills/infra-automation/SKILL.md carries a rule requiring a
# `docker inspect ... config_files` label check before any
# `docker compose down`/`up` against a production container, so a cutover
# never starts an unrelated default-config container by mistake
# (INFRA-0280: auth-prod started from default docker-compose.yml, wiping the
# working container).

SKILL="$BATS_TEST_DIRNAME/../skills/infra-automation/SKILL.md"

@test "T1 infra-automation SKILL.md has the Compose Config-File Verification heading" {
    grep -qE '^## Compose Config-File Verification Before Cutover' "$SKILL"
}

@test "T2 rule gives the exact docker inspect probe command" {
    awk '/^## Compose Config-File Verification Before Cutover/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qF 'com.docker.compose.project.config_files'
}

@test "T3 rule names both compose down and up as guarded operations" {
    awk '/^## Compose Config-File Verification Before Cutover/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -q 'docker compose down'
    awk '/^## Compose Config-File Verification Before Cutover/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -q 'docker compose up'
}

@test "T4 rule warns against default-config fallback" {
    awk '/^## Compose Config-File Verification Before Cutover/{flag=1; next} /^## /{flag=0} flag' "$SKILL" \
        | grep -qi 'default `docker-compose.yml`'
}
