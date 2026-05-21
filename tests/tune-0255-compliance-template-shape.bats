#!/usr/bin/env bats
# tune-0255-compliance-template-shape.bats — Phase 1 compliance template shape guards.

TEMPLATE="$BATS_TEST_DIRNAME/../templates/compliance-report-template.md"
SKILL="$BATS_TEST_DIRNAME/../skills/compliance.md"
COMMAND="$BATS_TEST_DIRNAME/../commands/dr-compliance.md"
VALIDATOR="$BATS_TEST_DIRNAME/../dev-tools/check-banlist-on-prose.sh"

# ---------- T1 four top sections + audit addendum in canonical order ----------

@test "T1 compliance-report-template exists with four top sections + audit addendum" {
    [ -f "$TEMPLATE" ]
    local nach reshili artefakty steps addendum
    nach=$(grep -n '^## Начальная задача$' "$TEMPLATE" | cut -d: -f1)
    reshili=$(grep -n '^## Как решили$' "$TEMPLATE" | cut -d: -f1)
    artefakty=$(grep -n '^## Артефакты задачи$' "$TEMPLATE" | cut -d: -f1)
    steps=$(grep -n '^## Следующие шаги$' "$TEMPLATE" | cut -d: -f1)
    addendum=$(grep -n '^## Дополнительно для аудита$' "$TEMPLATE" | cut -d: -f1)
    [ -n "$nach" ] && [ -n "$reshili" ] && [ -n "$artefakty" ] && [ -n "$steps" ] && [ -n "$addendum" ]
    [ "$nach" -lt "$reshili" ]
    [ "$reshili" -lt "$artefakty" ]
    [ "$artefakty" -lt "$steps" ]
    [ "$steps" -lt "$addendum" ]
}

# ---------- T2 cross-link from skill/command to new template ----------

@test "T2 skills/compliance.md and commands/dr-compliance.md reference the new template" {
    grep -q 'compliance-report-template' "$SKILL"
    grep -q 'compliance-report-template' "$COMMAND"
}

# ---------- T3 validator runs cleanly on the compliance template ----------

@test "T3 check-banlist-on-prose.sh exits 0 on compliance-report-template.md" {
    [ -x "$VALIDATOR" ]
    run "$VALIDATOR" --file "$TEMPLATE"
    [ "$status" -eq 0 ]
}

# ---------- T4 frontmatter shape ----------

@test "T4 compliance template frontmatter carries task_id, date, verdict" {
    head -20 "$TEMPLATE" > "$BATS_TEST_TMPDIR/fm.txt"
    grep -q '^task_id:' "$BATS_TEST_TMPDIR/fm.txt"
    grep -q '^date:' "$BATS_TEST_TMPDIR/fm.txt"
    grep -q '^verdict:' "$BATS_TEST_TMPDIR/fm.txt"
}
