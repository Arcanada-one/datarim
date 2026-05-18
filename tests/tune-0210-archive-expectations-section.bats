#!/usr/bin/env bats
# tune-0210-archive-expectations-section.bats — Phase 5 archive expectations section (F6).
#
# Covers:
#   - templates/archive-template.md carries the `## Выполнение ожиданий оператора` heading
#     between Final Acceptance Criteria and Known Outstanding State.
#   - The template section forbids tables (bullet list only).
#   - commands/dr-archive.md Step 2 enumerates the section as mandatory + no-tables + no-anglicisms.
#   - Missing-expectations-file fallback wording is documented.
#   - Status word translation is documented (met → выполнено, partial → частично,
#     missed → не выполнено, n-a → неприменимо).

TEMPLATE="$BATS_TEST_DIRNAME/../templates/archive-template.md"
COMMAND="$BATS_TEST_DIRNAME/../commands/dr-archive.md"

# --- Template shape ---------------------------------------------------------

@test "T1 template carries the operator-expectations section heading" {
    grep -q '^## Выполнение ожиданий оператора$' "$TEMPLATE"
}

@test "T2 template places the section between Final Acceptance Criteria and Known Outstanding State" {
    local ac_line outstanding_line section_line
    ac_line=$(grep -n '^## Final Acceptance Criteria$' "$TEMPLATE" | cut -d: -f1)
    section_line=$(grep -n '^## Выполнение ожиданий оператора$' "$TEMPLATE" | cut -d: -f1)
    outstanding_line=$(grep -n '^## Known Outstanding State / Operator Handoff$' "$TEMPLATE" | cut -d: -f1)
    [ -n "$ac_line" ] && [ -n "$section_line" ] && [ -n "$outstanding_line" ]
    [ "$ac_line" -lt "$section_line" ]
    [ "$section_line" -lt "$outstanding_line" ]
}

@test "T3 template section body has no markdown tables" {
    # Extract everything between this heading and the next `## ` heading.
    awk '/^## Выполнение ожиданий оператора$/{flag=1; next} /^## /{flag=0} flag' "$TEMPLATE" > "$BATS_TEST_TMPDIR/section.txt"
    [ -s "$BATS_TEST_TMPDIR/section.txt" ]
    ! grep -qE '^\s*\|' "$BATS_TEST_TMPDIR/section.txt"
}

@test "T4 template section uses single-level bullets only (no nested bullets)" {
    awk '/^## Выполнение ожиданий оператора$/{flag=1; next} /^## /{flag=0} flag' "$TEMPLATE" > "$BATS_TEST_TMPDIR/section.txt"
    # Single-level bullet starts with `- ` at column 0; nested bullet would start with `  - ` or deeper.
    ! grep -qE '^[[:space:]]+-[[:space:]]' "$BATS_TEST_TMPDIR/section.txt"
}

@test "T5 template documents the missing-expectations fallback wording" {
    grep -q 'Чек-лист ожиданий не заводился' "$TEMPLATE"
}

# --- Command-file contract --------------------------------------------------

@test "T6 commands/dr-archive.md Step 2 references the section by exact heading" {
    grep -q '`## Выполнение ожиданий оператора`' "$COMMAND"
}

@test "T7 commands/dr-archive.md declares the no-tables rule for the section" {
    grep -qE 'No tables in this section|Без таблиц|никаких таблиц' "$COMMAND"
}

@test "T8 commands/dr-archive.md declares the no-anglicisms rule (banlist from human-summary)" {
    grep -q 'banlist' "$COMMAND"
    grep -q 'human-summary' "$COMMAND"
}

@test "T9 commands/dr-archive.md declares the four status-word translations" {
    grep -q 'выполнено' "$COMMAND"
    grep -q 'частично' "$COMMAND"
    grep -q 'не выполнено' "$COMMAND"
    grep -q 'неприменимо' "$COMMAND"
}

@test "T10 commands/dr-archive.md forbids the raw schema enum (met/partial/missed/n-a) in the rendered section" {
    grep -qE 'never the schema enum|не использовать .*met|без enum' "$COMMAND"
}
