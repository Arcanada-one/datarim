#!/usr/bin/env bats
#
# TUNE-0244: override-indent concrete-syntax regression.
#
# dev-tools/check-expectations-checklist.sh matches override lines with the
# exact regex `^  - override:` (2-space, item-bullet level). A misplaced
# 4-space override (the indent used under `#### Текущий статус`) is invisible
# to the regex and must silently degrade to "no override present" — BLOCKED
# for a partial wish — rather than being mis-parsed as present.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/tasks"
    EXP="$WORK/datarim/tasks/FAKE-9200-expectations.md"
    cat > "$WORK/datarim/backlog.md" <<'EOF'
# Backlog
EOF
    cat > "$WORK/datarim/tasks.md" <<'EOF'
# Tasks
## Active
EOF
}

teardown() {
    rm -rf "$WORK"
}

write_exp() {
    local override_block="$1"
    cat > "$EXP" <<EOF
---
task_id: FAKE-9200
artifact: expectations
schema_version: 2
captured_at: 2026-05-30
captured_by: /dr-prd
status: canonical
---

# FAKE-9200 — Ожидания оператора

## Ожидания

- **1. Что-то должно работать.**
  - wish_id: chto-to-rabotaet
  - Что хочу проверить: что фича работает.
  - Как проверить (success criterion): команда возвращает 0.
  - Связанный AC из PRD: «—»
  - evidence_type: empirical
${override_block}
  - #### История статусов
    - 2026-05-30T00:00:00Z / 2026-05-30 · /dr-do · pending → partial · reason: частично сделано
  - #### Текущий статус
    - partial

<!-- end -->

## Append-log (operator amendments)

_(пусто)_
EOF
}

# ---------- correct 2-space override is recognized ----------

@test "2-space override (operator-authored) → CONDITIONAL_PASS" {
    write_exp "  - override: soak period not yet complete, operator-approved deferral
  - override_by: operator"
    run "$SCRIPT" --verify FAKE-9200 --root "$WORK"
    [[ "$output" == *"CONDITIONAL_PASS"* ]]
}

# ---------- misplaced 4-space override is silently invisible to the validator ----------

@test "4-space override (misplaced indent) → BLOCKED, not CONDITIONAL_PASS" {
    write_exp "    - override: soak period not yet complete, operator-approved deferral
    - override_by: operator"
    run "$SCRIPT" --verify FAKE-9200 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" != *"CONDITIONAL_PASS"* ]]
}
