#!/usr/bin/env bats
# tune-0394-migration-entrypoint-probe.bats — reflection-SPACE-0029 EV-3.
#
# Covers: templates/infra-artifact-checklist.md Phase A carries a mandatory
# Phase-0 step requiring a live `docker inspect ... Entrypoint` probe before
# a migration step is authored (root cause: SPACE-0029's plan assumed
# `lf-worker` ran Langfuse ClickHouse migrations; the actual entrypoint was
# on `lf-web`, caught only on /dr-do execution).

CHECKLIST="$BATS_TEST_DIRNAME/../templates/infra-artifact-checklist.md"

@test "E1 checklist Phase A has a Phase-0 migration entrypoint-probe item" {
    grep -qi 'Phase-0' "$CHECKLIST"
}

@test "E2 Phase-0 item names the exact docker inspect probe command" {
    grep -oE '\- \[ \] .*Phase-0.*' "$CHECKLIST" | grep -qF '.Config.Entrypoint'
}

@test "E3 Phase-0 item is listed under Phase A, before the general artifact items" {
    awk '/^## Phase A:/{flag=1} flag && /^## Phase B:/{exit} flag' "$CHECKLIST" \
        | grep -qi 'Phase-0'
}

@test "E4 Phase-0 item warns against assuming the entrypoint from name/role" {
    grep -oE '\- \[ \] .*Phase-0.*' "$CHECKLIST" | grep -qi 'rather than assuming'
}
