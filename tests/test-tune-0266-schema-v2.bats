#!/usr/bin/env bats
# test-tune-0266-schema-v2.bats — Phase 1 schema_version 1 → 2 migration.
#
# Covers:
#   - schema_version: 2 with valid evidence_type per wish → exit 0
#   - schema_version: 2 + missing evidence_type → exit 1
#   - schema_version: 2 + invalid evidence_type enum → exit 1
#   - schema_version: 1 (legacy) → exit 0 + stderr DEPRECATION warning
#   - schema_version: 99 (unsupported) → exit 1
#
# Companion plan: datarim/plans/TUNE-0266-plan.md § Phase 1.

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- Helpers ----------------------------------------------------------------

# write_v2 <ID> <evidence_type_1> <evidence_type_2>
# Writes a minimal valid v2 file with 2 items, each carrying evidence_type.
# Pass empty string for evidence_type to simulate "missing field" case.
write_v2() {
    local id="$1"; local ev1="$2"; local ev2="$3"
    local file="$TMPROOT/datarim/tasks/${id}-expectations.md"
    local ev1_line=""
    local ev2_line=""
    [ -n "$ev1" ] && ev1_line="  - evidence_type: $ev1"
    [ -n "$ev2" ] && ev2_line="  - evidence_type: $ev2"

    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 2
captured_at: 2026-05-23
captured_by: /dr-init
agent: planner
status: canonical
---

# $id — Ожидания оператора

## Ожидания

- **1. Первое ожидание тестовое.**
  - wish_id: pervoe-ozhidanie-testovoe
  - Что хочу проверить: Тестовое описание первого ожидания.
  - Как проверить (success criterion): Проверочный сигнал first.
  - Связанный AC из PRD: V-AC-1
$ev1_line
  - #### История статусов
    - 2026-05-23T00:00:00Z / 03:00 (MSK) · pending → pending · /dr-init · reason: пункт создан
  - #### Текущий статус
    - pending

- **2. Второе ожидание тестовое.**
  - wish_id: vtoroe-ozhidanie-testovoe
  - Что хочу проверить: Тестовое описание второго ожидания.
  - Как проверить (success criterion): Проверочный сигнал second.
  - Связанный AC из PRD: V-AC-2
$ev2_line
  - #### История статусов
    - 2026-05-23T00:00:00Z / 03:00 (MSK) · pending → pending · /dr-init · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(пусто на момент создания)_
EOF
}

# write_v1 <ID> — minimal valid v1 file (legacy, no evidence_type field)
write_v1() {
    local id="$1"
    local file="$TMPROOT/datarim/tasks/${id}-expectations.md"
    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
agent: architect
status: canonical
---

# $id — Ожидания оператора

## Ожидания

- **1. Легаси ожидание.**
  - wish_id: legacy-ozhidanie
  - Что хочу проверить: legacy v1 behaviour preserved.
  - Как проверить (success criterion): grep file passes.
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(пусто на момент создания)_
EOF
}

# write_unsupported <ID> <version>
write_unsupported() {
    local id="$1"; local ver="$2"
    local file="$TMPROOT/datarim/tasks/${id}-expectations.md"
    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: $ver
captured_at: 2026-05-23
captured_by: /dr-init
status: canonical
---

# $id — Ожидания оператора

## Ожидания

- **1. Ожидание из будущего.**
  - wish_id: ozhidanie-iz-budushchego
  - Что хочу проверить: future schema.
  - Как проверить (success criterion): N/A.
  - Связанный AC из PRD: V-AC-1
  - evidence_type: empirical
  - #### История статусов
    - 2026-05-23T00:00:00Z / 03:00 (MSK) · pending → pending · /dr-init · reason: created
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(пусто на момент создания)_
EOF
}

# --- Cases ------------------------------------------------------------------

@test "schema_v2: valid evidence_type empirical per wish → exit 0" {
    write_v2 "TEST-0001" "empirical" "static"
    run "$CHECK" --task TEST-0001 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "schema_v2: missing evidence_type on item → exit 1" {
    write_v2 "TEST-0002" "empirical" ""
    run "$CHECK" --task TEST-0002 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"evidence_type"* ]]
}

@test "schema_v2: invalid evidence_type enum → exit 1" {
    write_v2 "TEST-0003" "empirical" "foo"
    run "$CHECK" --task TEST-0003 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"evidence_type"* ]]
}

@test "schema_v1: legacy file → exit 0 + stderr DEPRECATION" {
    write_v1 "TEST-0004"
    run "$CHECK" --task TEST-0004 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPRECATION"* ]] || [[ "$stderr" == *"DEPRECATION"* ]]
}

@test "schema_unsupported: schema_version=99 → exit 1" {
    write_unsupported "TEST-0005" "99"
    run "$CHECK" --task TEST-0005 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"schema_version"* ]]
}

@test "schema_v2: measurement evidence_type accepted" {
    write_v2 "TEST-0006" "measurement" "measurement"
    run "$CHECK" --task TEST-0006 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}
