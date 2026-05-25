#!/usr/bin/env bats
# tune-0255-archive-business-structure.bats — Phase 1 archive business-structure guards.
#
# Covers PRD V-AC-1..4 and V-AC-7..9 plus ported T6-T10 from
# tune-0210-archive-expectations-section.bats (retired by TUNE-0255).

TEMPLATE="$BATS_TEST_DIRNAME/../templates/archive-template.md"
COMMAND="$BATS_TEST_DIRNAME/../commands/dr-archive.md"
VALIDATOR="$BATS_TEST_DIRNAME/../dev-tools/check-banlist-on-prose.sh"

# ---------- T1 four top sections in canonical order ----------

@test "T1 archive-template carries four top-level sections in canonical order" {
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

# ---------- T2 init-task mapping referenced in dr-archive Step 2 ----------

@test "T2 dr-archive Step 2 instructs to map init-task bullets into Kak-reshili" {
    grep -q 'init-task' "$COMMAND"
    grep -q 'Operator brief' "$COMMAND"
    grep -q 'Как решили' "$COMMAND"
}

# ---------- T3 expectations fold instruction ----------

@test "T3 dr-archive instructs to fold expectations into Kak-reshili with operator-clarification marker" {
    grep -q '(уточнение брифа)' "$COMMAND"
    grep -q 'expectations' "$COMMAND"
}

# ---------- T4 audit addendum invariants ----------

@test "T4 audit addendum carries verification_outcome / Acceptance Criteria / Lessons Learned / Related subsections" {
    awk '/^## Дополнительно для аудита$/{flag=1; next} /^## /{flag=0} flag' "$TEMPLATE" > "$BATS_TEST_TMPDIR/addendum.txt"
    [ -s "$BATS_TEST_TMPDIR/addendum.txt" ]
    grep -q '^### verification_outcome' "$BATS_TEST_TMPDIR/addendum.txt"
    grep -q '^### Acceptance Criteria' "$BATS_TEST_TMPDIR/addendum.txt"
    grep -q '^### Lessons Learned' "$BATS_TEST_TMPDIR/addendum.txt"
    grep -q '^### Related' "$BATS_TEST_TMPDIR/addendum.txt"
}

# ---------- T5 (ported from tune-0210 T9) status word translations in dr-archive ----------

@test "T5 dr-archive declares the four status-word translations" {
    grep -q 'выполнено' "$COMMAND"
    grep -q 'частично' "$COMMAND"
    grep -q 'не выполнено' "$COMMAND"
    grep -q 'неприменимо' "$COMMAND"
}

# ---------- T6 (ported from tune-0210 T10) forbid raw schema enum in rendered section ----------

@test "T6 dr-archive forbids the raw schema enum (met/partial/missed/n-a) in the rendered section" {
    grep -qE 'never the schema enum|не использовать .*met|без enum' "$COMMAND"
}

# ---------- T7 (ported from tune-0210 T7) no-tables rule for 'Как решили' ----------

@test "T7 dr-archive declares the no-tables rule for the Kak-reshili section" {
    grep -qE 'No tables in this section|Без таблиц|никаких таблиц' "$COMMAND"
}

# ---------- T8 (ported from tune-0210 T8) banlist + human-summary references ----------

@test "T8 dr-archive declares the no-anglicisms rule (banlist from human-summary)" {
    grep -q 'banlist' "$COMMAND"
    grep -q 'human-summary' "$COMMAND"
}

# ---------- T9 single-level bullet rule in 'Как решили' template body ----------

@test "T9 archive-template Kak-reshili body has single-level bullets only and no tables" {
    awk '/^## Как решили$/{flag=1; next} /^## /{flag=0} flag' "$TEMPLATE" > "$BATS_TEST_TMPDIR/section.txt"
    [ -s "$BATS_TEST_TMPDIR/section.txt" ]
    ! grep -qE '^\s*\|' "$BATS_TEST_TMPDIR/section.txt"
    ! grep -qE '^[[:space:]]+-[[:space:]]' "$BATS_TEST_TMPDIR/section.txt"
}

# ---------- T10 validator runs cleanly on the archive template ----------

@test "T10 check-banlist-on-prose.sh exits 0 on archive-template.md" {
    [ -x "$VALIDATOR" ]
    run "$VALIDATOR" --file "$TEMPLATE"
    [ "$status" -eq 0 ]
}
