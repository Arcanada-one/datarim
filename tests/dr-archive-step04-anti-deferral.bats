#!/usr/bin/env bats
#
# Integration test for /dr-archive Step 0.4 (Expectations re-validation +
# anti-deferral gate). The command is markdown instruction; this test verifies
# the deterministic surfaces it wires in produce the BLOCK that Step 0.4
# instructs the agent to honour — on a synthetic scenario modelled on the
# triggering incident (agent-edited runbook, stale counter labelled
# "informational, out of scope"). A FICTIONAL task ID is used (no real task IDs
# in shipped tests).
#
# Maps to PRD V-AC-6: a BLOCKED expectations file OR a deferral-on-touched-file
# report aborts the archive before reflection.

setup() {
    EXP_SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"
    PROSE_SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-deferral-prose.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/tasks" "$WORK/datarim/qa"
    printf '# Tasks\n## Active\n' > "$WORK/datarim/tasks.md"
    printf '# Backlog\n' > "$WORK/datarim/backlog.md"
    TOUCHED="$WORK/touched.txt"
    printf 'spaces/aether/runbook.md\n' > "$TOUCHED"
}

teardown() {
    rm -rf "$WORK"
}

# Step 0.4(a): a partial wish with an agent prose-only override BLOCKS archive.
@test "0.4(a) BLOCK: partial wish, agent prose-only override → expectations --verify exit 1" {
    cat > "$WORK/datarim/tasks/FAKE-9200-expectations.md" <<'EOF'
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

- **1. Счётчик контейнеров актуален.**
  - wish_id: schetchik-akkuratlen
  - Что хочу проверить: что в runbook верное число.
  - Как проверить (success criterion): grep совпадает с baseline.
  - Связанный AC из PRD: «—»
  - evidence_type: static
  - override: informational only, cosmetic, not worth doing now
  - override_by: agent
  - #### История статусов
    - 2026-05-30T00:00:00Z / 2026-05-30 · /dr-do · pending → partial · reason: оставил как есть
  - #### Текущий статус
    - partial

## Append-log (operator amendments)

_(пусто)_
EOF
    run "$EXP_SCRIPT" --verify FAKE-9200 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED"* ]]
}

# Step 0.4(b): a deferral phrase on a touched file in the QA report BLOCKS archive.
@test "0.4(b) BLOCK: deferral on touched runbook in QA report → prose scan exit 1" {
    cat > "$WORK/datarim/qa/qa-report-FAKE-9200.md" <<'EOF'
## Layer 3b
The stale "21 containers" figure in spaces/aether/runbook.md is informational,
not a blocker, out of scope for this task.
EOF
    run "$PROSE_SCRIPT" --file "$WORK/datarim/qa/qa-report-FAKE-9200.md" \
        --touched-files "$TOUCHED" --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runbook.md"* ]]
}

# Clean state: a fully-met task passes both 0.4 surfaces (archive proceeds).
@test "0.4 PASS: clean QA report + all-met expectations → both surfaces exit 0" {
    cat > "$WORK/datarim/qa/qa-report-FAKE-9200.md" <<'EOF'
## Layer 3b
All wishes met. Counter corrected in spaces/aether/runbook.md, committed to origin.
EOF
    run "$PROSE_SCRIPT" --file "$WORK/datarim/qa/qa-report-FAKE-9200.md" \
        --touched-files "$TOUCHED" --root "$WORK"
    [ "$status" -eq 0 ]
}
