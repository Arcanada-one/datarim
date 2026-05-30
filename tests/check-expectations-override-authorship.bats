#!/usr/bin/env bats
#
# Contract test for the override-authorship + artefact extension of
# dev-tools/check-expectations-checklist.sh --verify.
#
# A partial/missed wish may only CONDITIONAL_PASS when its override is either
# (a) operator-authored, or (b) agent-authored AND backed by a verifiable
# legitimate-deferral artefact (a follow-up ID or blocked_by reference that
# exists in backlog.md / tasks.md). An agent-authored prose-only override —
# the self-certification loophole — must BLOCK.
#
# Maps to PRD V-AC-4 (agent prose-only override → BLOCK) and
# V-AC-5 (operator-authored OR artefact-backed agent override → CONDITIONAL_PASS).

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/tasks"
    EXP="$WORK/datarim/tasks/FAKE-9100-expectations.md"
    # KB with one real follow-up ID for artefact verification
    cat > "$WORK/datarim/backlog.md" <<'EOF'
- FAKE-9101 · pending · P3 · L1 · Re-verify after 7-day prod soak (time-dependent) → tasks/FAKE-9101-task-description.md
EOF
    cat > "$WORK/datarim/tasks.md" <<'EOF'
# Tasks
## Active
EOF
}

teardown() {
    rm -rf "$WORK"
}

# Helper: write a one-wish expectations file with a partial status and the
# given override stanza (passed as a heredoc body via $1 = extra override lines).
write_exp() {
    local override_block="$1"
    cat > "$EXP" <<EOF
---
task_id: FAKE-9100
artifact: expectations
schema_version: 2
captured_at: 2026-05-30
captured_by: /dr-prd
status: canonical
---

# FAKE-9100 — Ожидания оператора

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

# ---------- V-AC-4: agent-authored prose-only override → BLOCK ----------

@test "BLOCK: partial wish, agent-authored prose-only override (no class/artefact)" {
    write_exp "  - override: this is just cosmetic and not worth doing now honestly
  - override_by: agent"
    run "$SCRIPT" --verify FAKE-9100 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "BLOCK: partial wish, agent override with class but NON-existent artefact ID" {
    write_exp "  - override: deferred to follow-up after soak
  - override_by: agent
  - override_class: time-dependent
  - override_artifact: FAKE-7777"
    run "$SCRIPT" --verify FAKE-9100 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "BLOCK: backwards-compat — partial wish, legacy override >=10 chars, NO override_by → defaults to agent" {
    write_exp "  - override: legacy reason that is well over ten characters long"
    run "$SCRIPT" --verify FAKE-9100 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}

# ---------- V-AC-5: operator OR artefact-backed agent override → CONDITIONAL_PASS ----------

@test "CONDITIONAL_PASS: partial wish, operator-authored override" {
    write_exp "  - override: operator accepts this partial for the current cycle
  - override_by: operator"
    run "$SCRIPT" --verify FAKE-9100 --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONDITIONAL_PASS"* ]]
}

@test "CONDITIONAL_PASS: partial wish, agent override backed by a real FU-ID in backlog" {
    write_exp "  - override: physically unverifiable now, needs a 7-day prod soak
  - override_by: agent
  - override_class: time-dependent
  - override_artifact: FAKE-9101"
    run "$SCRIPT" --verify FAKE-9100 --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONDITIONAL_PASS"* ]]
}

# ---------- regression: all-met still PASS, structural validity intact ----------

@test "PASS: all wishes met (no override needed)" {
    cat > "$EXP" <<'EOF'
---
task_id: FAKE-9100
artifact: expectations
schema_version: 2
captured_at: 2026-05-30
captured_by: /dr-prd
status: canonical
---

# FAKE-9100 — Ожидания оператора

## Ожидания

- **1. Что-то должно работать.**
  - wish_id: chto-to-rabotaet
  - Что хочу проверить: что фича работает.
  - Как проверить (success criterion): команда возвращает 0.
  - Связанный AC из PRD: «—»
  - evidence_type: empirical
  - #### История статусов
    - 2026-05-30T00:00:00Z / 2026-05-30 · /dr-do · pending → met · reason: сделано
  - #### Текущий статус
    - met

## Append-log (operator amendments)

_(пусто)_
EOF
    run "$SCRIPT" --verify FAKE-9100 --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
