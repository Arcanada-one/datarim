#!/usr/bin/env bats
# tune-0210-checklist-verify-routing.bats — Phase 2 expectations verify-routing (F3).
#
# Covers:
#   - dev-tools/check-expectations-checklist.sh --verify <ID>
#   - PASS verdict (all items met / n-a / pending / deleted)
#   - BLOCKED verdict (≥1 item missed/partial without override)  → exit 1
#   - CONDITIONAL_PASS verdict (missed/partial only when accompanied by
#     operator override ≥10 chars)  → exit 0 with marker
#   - FAIL-Routing CTA emits `/dr-do <ID> --focus-items <wish_id_1,wish_id_N>`
#   - Override of <10 chars is treated as absent (BLOCKED)

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# write_expectations <ID> <body-after-Ожидания-heading>
# Wraps the body inside a complete Option B file with valid frontmatter.
write_expectations() {
    local id="$1"; local body="$2"
    local file="$TMPROOT/datarim/tasks/${id}-expectations.md"
    {
        echo "---"
        echo "task_id: $id"
        echo "artifact: expectations"
        echo "schema_version: 1"
        echo "captured_at: 2026-05-14"
        echo "captured_by: /dr-prd"
        echo "agent: architect"
        echo "status: canonical"
        echo "---"
        echo ""
        echo "# $id — Ожидания оператора"
        echo ""
        echo "## Ожидания"
        echo ""
        printf '%s\n' "$body"
        echo ""
        echo "## Append-log (operator amendments)"
        echo ""
        echo "_(пусто)_"
    } > "$file"
}

# --- PASS ------------------------------------------------------------------

@test "R1 --verify exits 0 with PASS when every item is met or n-a" {
    write_expectations "TEST-0001" "$(cat <<'EOF'
- **1. Met.**
  - wish_id: met
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → met · /dr-qa · reason: проверка пройдена
  - #### Текущий статус
    - met

- **2. Not applicable.**
  - wish_id: not-applicable
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: —
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → n-a · /dr-qa · reason: пункт не применим
  - #### Текущий статус
    - n-a
EOF
)"
    run "$CHECK" --verify TEST-0001 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- BLOCKED: partial without override ------------------------------------

@test "R2 --verify exits 1 BLOCKED for partial without override" {
    write_expectations "TEST-0002" "$(cat <<'EOF'
- **1. Partial no override.**
  - wish_id: partial-no-override
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → partial · /dr-qa · reason: один сабчек красный
  - #### Текущий статус
    - partial
EOF
)"
    run "$CHECK" --verify TEST-0002 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"partial-no-override"* ]]
}

# --- BLOCKED: missed without override -------------------------------------

@test "R3 --verify exits 1 BLOCKED for missed without override" {
    write_expectations "TEST-0003" "$(cat <<'EOF'
- **1. Missed no override.**
  - wish_id: missed-no-override
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → missed · /dr-qa · reason: реализация отсутствует
  - #### Текущий статус
    - missed
EOF
)"
    run "$CHECK" --verify TEST-0003 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"missed-no-override"* ]]
}

# --- CONDITIONAL_PASS: missed with override -------------------------------

@test "R4 --verify exits 0 CONDITIONAL_PASS for missed with valid override" {
    write_expectations "TEST-0004" "$(cat <<'EOF'
- **1. Missed but waived.**
  - wish_id: missed-but-waived
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - override: оператор принял решение отложить пункт до следующей итерации релиза
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → missed · /dr-qa · reason: пункт за рамками текущего объёма
  - #### Текущий статус
    - missed
EOF
)"
    run "$CHECK" --verify TEST-0004 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONDITIONAL_PASS"* ]] || [[ "$output" == *"CONDITIONAL"* ]]
}

# --- BLOCKED: short override <10 chars treated as absent ------------------

@test "R5 --verify exits 1 BLOCKED when override is shorter than 10 chars" {
    write_expectations "TEST-0005" "$(cat <<'EOF'
- **1. Short override.**
  - wish_id: short-override
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - override: ок
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → partial · /dr-qa · reason: ок
  - #### Текущий статус
    - partial
EOF
)"
    run "$CHECK" --verify TEST-0005 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"short-override"* ]]
}

# --- CTA emission ---------------------------------------------------------

@test "R6 --verify emits FAIL-Routing CTA pointing at /dr-do with focus-items" {
    write_expectations "TEST-0006" "$(cat <<'EOF'
- **1. Item one.**
  - wish_id: item-one
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → met · /dr-qa · reason: ok
  - #### Текущий статус
    - met

- **2. Item two.**
  - wish_id: item-two
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-2
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → missed · /dr-qa · reason: not done
  - #### Текущий статус
    - missed

- **3. Item three.**
  - wish_id: item-three
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-3
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → partial · /dr-qa · reason: incomplete
  - #### Текущий статус
    - partial
EOF
)"
    run "$CHECK" --verify TEST-0006 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"/dr-do TEST-0006"* ]]
    [[ "$output" == *"--focus-items"* ]]
    # Both blocking wish_ids surface in the focus list; the passing one does not.
    [[ "$output" == *"item-two"* ]]
    [[ "$output" == *"item-three"* ]]
    [[ "$output" != *"focus-items=item-one"* ]]
}

# --- Pending status is non-blocking on --verify ---------------------------

@test "R7 --verify treats pending status as non-blocking (PASS)" {
    # Pending = checklist exists but verification hasn't run yet. We still
    # PASS because no item is in a violating state; the /dr-qa step will
    # transition them. This avoids a Catch-22 where the very first --verify
    # invocation always fails.
    write_expectations "TEST-0007" "$(cat <<'EOF'
- **1. Untouched item.**
  - wish_id: untouched
  - Что хочу проверить: x
  - Как проверить (success criterion): y
  - Связанный AC из PRD: V-AC-1
  - #### История статусов
    - 2026-05-14T12:00:00Z / 14.05.2026 15:00 (MSK) · pending → pending · /dr-prd · reason: создан
  - #### Текущий статус
    - pending
EOF
)"
    run "$CHECK" --verify TEST-0007 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- --verify on missing file behaves like --task ------------------------

@test "R8 --verify exits 1 on missing expectations file" {
    run "$CHECK" --verify TEST-0099 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || [[ "$output" == *"not found"* ]]
}
