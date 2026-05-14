#!/usr/bin/env bats
# tune-0210-expectations-schema.bats — Phase 2 expectations checklist (F2).
#
# Covers:
#   - dev-tools/check-expectations-checklist.sh structural validation (--task)
#   - Option B schema: frontmatter (artifact: expectations, schema_version 1),
#     `## Ожидания` heading, per-item shape, `#### История статусов`,
#     `#### Текущий статус`
#   - wish_id slug (kebab + cyrillic allowed)
#   - status enum {pending, met, partial, missed, n-a, deleted}
#   - malformed История line rejection
#   - advisory --all mode (L3+ tasks without expectations file)
#
# Routing semantics live in `tune-0210-checklist-verify-routing.bats`.

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- Helpers ----------------------------------------------------------------

# write_valid_expectations <ID>
# Writes a minimal valid Option B file with 2 items, both status pending.
write_valid_expectations() {
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

- **1. Сохранение исходного промпта.**
  - wish_id: сохранение-исходного-промпта
  - Что хочу проверить: Промпт оператора не искажён при передаче между этапами pipeline.
  - Как проверить (success criterion): Файл tasks/{ID}-init-task.md содержит verbatim текст.
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: пункт создан
  - #### Текущий статус
    - pending

- **2. Verify-routing на этапах.**
  - wish_id: verify-routing-na-etapah
  - Что хочу проверить: QA и COMPLIANCE блокируют проход при missed/partial без override.
  - Как проверить (success criterion): Прогон валидатора показывает BLOCKED для partial без override.
  - Связанный AC из PRD: V-AC-10
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: пункт создан
  - #### Текущий статус
    - pending

## Append-log (operator amendments)

_(пусто на момент создания)_
EOF
}

# write_task_description <ID> <created> [<complexity>] [<status>]
write_task_description() {
    local id="$1"; local created="$2"
    local complexity="${3:-L3}"; local status="${4:-in_progress}"
    local file="$TMPROOT/datarim/tasks/${id}-task-description.md"
    cat > "$file" <<EOF
---
task_id: $id
title: $id task
status: $status
priority: P2
complexity: $complexity
type: framework
project: Datarim
created: $created
---

# $id
EOF
}

# --- Single-file validation (--task) ----------------------------------------

@test "S1 check --task exits 0 on valid Option B file" {
    write_valid_expectations "TEST-0001"
    run "$CHECK" --task TEST-0001 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "S2 check --task exits 1 when file missing" {
    run "$CHECK" --task TEST-0002 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || [[ "$output" == *"not found"* ]]
}

@test "S3 check --task exits 1 on wrong artifact label" {
    local file="$TMPROOT/datarim/tasks/TEST-0003-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0003
artifact: task-description
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0003

## Ожидания

- **1. Item.**
  - wish_id: item
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: создан
  - #### Текущий статус
    - pending
EOF
    run "$CHECK" --task TEST-0003 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"artifact"* ]]
}

@test "S4 check --task exits 1 when expectations heading missing" {
    local file="$TMPROOT/datarim/tasks/TEST-0004-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0004
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0004

## Wishlist

- **1. Item.**
EOF
    run "$CHECK" --task TEST-0004 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Ожидания"* ]]
}

@test "S5 check --task exits 1 when item lacks wish_id" {
    local file="$TMPROOT/datarim/tasks/TEST-0005-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0005
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0005

## Ожидания

- **1. Item without wish_id.**
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: создан
  - #### Текущий статус
    - pending
EOF
    run "$CHECK" --task TEST-0005 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"wish_id"* ]]
}

@test "S6 check --task exits 1 when current-status value is out of enum" {
    local file="$TMPROOT/datarim/tasks/TEST-0006-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0006
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0006

## Ожидания

- **1. Bad status.**
  - wish_id: bad-status
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: создан
  - #### Текущий статус
    - frobnicated
EOF
    run "$CHECK" --task TEST-0006 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"status"* ]] || [[ "$output" == *"enum"* ]]
}

@test "S7 check --task accepts cyrillic wish_id slug" {
    write_valid_expectations "TEST-0007"
    # The default helper already uses cyrillic slugs. Validate explicitly.
    run "$CHECK" --task TEST-0007 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    # Sanity: ensure file actually contains a cyrillic wish_id
    grep -q 'wish_id: сохранение-исходного-промпта' "$TMPROOT/datarim/tasks/TEST-0007-expectations.md"
}

@test "S8 check --task exits 1 on malformed status-history line" {
    local file="$TMPROOT/datarim/tasks/TEST-0008-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0008
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0008

## Ожидания

- **1. Bad history line.**
  - wish_id: bad-history
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - this line is not in the canonical format
  - #### Текущий статус
    - pending
EOF
    run "$CHECK" --task TEST-0008 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"История"* ]] || [[ "$output" == *"history"* ]]
}

@test "S9 check --task accepts n-a, deleted and partial-with-override statuses" {
    local file="$TMPROOT/datarim/tasks/TEST-0009-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0009
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0009

## Ожидания

- **1. N-A item.**
  - wish_id: n-a-item
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: —
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → n-a · /dr-qa · reason: пункт не применим в этом релизе
  - #### Текущий статус
    - n-a

- **2. Partial with override.**
  - wish_id: partial-with-override
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-2
  - override: оператор подтвердил частичное выполнение пункта на текущей итерации
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → partial · /dr-qa · reason: один сабчек не зелёный
  - #### Текущий статус
    - partial

- **3. Deleted item.**
  - wish_id: deleted-item
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: —
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → deleted · /dr-prd · reason: оператор снял требование
  - #### Текущий статус
    - deleted
EOF
    run "$CHECK" --task TEST-0009 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "S10 check --task exits 1 when file has zero items under expectations heading" {
    local file="$TMPROOT/datarim/tasks/TEST-0010-expectations.md"
    cat > "$file" <<'EOF'
---
task_id: TEST-0010
artifact: expectations
schema_version: 1
captured_at: 2026-05-14
captured_by: /dr-prd
status: canonical
---

# TEST-0010

## Ожидания

_(пусто на момент создания)_
EOF
    run "$CHECK" --task TEST-0010 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"item"* ]] || [[ "$output" == *"empty"* ]] || [[ "$output" == *"пуст"* ]]
}

# --- Multi-task advisory scan (--all) ---------------------------------------

@test "S11 check --all info finding for fresh L3 task without expectations" {
    today="$(date +%Y-%m-%d)"
    write_task_description "TEST-0011" "$today" "L3"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-0011"* ]]
    [[ "$output" == *"info"* ]]
}

@test "S12 check --all warn finding for stale L3 task (>=30d) without expectations" {
    today="2026-06-20"
    write_task_description "TEST-0012" "2026-05-14" "L3"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-0012"* ]]
    [[ "$output" == *"warn"* ]]
}

@test "S13 check --all skips L1/L2 tasks (expectations optional below L3)" {
    today="2026-06-20"
    write_task_description "TEST-0013" "2026-05-14" "L1"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" != *"TEST-0013"* ]]
}

@test "S14 check --all skips archived task" {
    today="2026-06-20"
    write_task_description "TEST-0014" "2026-05-14" "L3" "archived"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" != *"TEST-0014"* ]]
}

# --- Usage / safety ---------------------------------------------------------

@test "S15 check exits 2 on usage error" {
    run "$CHECK" --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "S16 check --help prints usage and exits 0" {
    run "$CHECK" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}
