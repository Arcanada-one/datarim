#!/usr/bin/env bats
#
# Spec-regression tests for the human-summary contract.
#
# Verifies that the three operator-facing commands (/dr-qa, /dr-compliance,
# /dr-archive) reference the human-summary skill and that the skill itself
# carries the four mandated sub-headings, the RU+EN mini-examples, and the
# Option C banlist + whitelist + per-paragraph escape-hatch contract.
#
# Coverage target: ≥16 cases.

SKILL="${BATS_TEST_DIRNAME}/../skills/human-summary.md"
BANLIST="${BATS_TEST_DIRNAME}/../skills/human-summary/banlist.txt"
WHITELIST="${BATS_TEST_DIRNAME}/../skills/human-summary/whitelist.txt"
CMD_QA="${BATS_TEST_DIRNAME}/../commands/dr-qa.md"
CMD_COMPLIANCE="${BATS_TEST_DIRNAME}/../commands/dr-compliance.md"
CMD_ARCHIVE="${BATS_TEST_DIRNAME}/../commands/dr-archive.md"

# 1
@test "skill file exists" {
    [ -f "$SKILL" ]
}

# 2
@test "banlist file exists in skills/human-summary/" {
    [ -f "$BANLIST" ]
}

# 3
@test "whitelist file exists in skills/human-summary/" {
    [ -f "$WHITELIST" ]
}

# 4
@test "dr-qa.md references the human-summary skill" {
    run grep -F "human-summary" "$CMD_QA"
    [ "$status" -eq 0 ]
}

# 5
@test "dr-qa.md contains HUMAN SUMMARY step heading" {
    run grep -F "HUMAN SUMMARY" "$CMD_QA"
    [ "$status" -eq 0 ]
}

# 6
@test "dr-compliance.md references the human-summary skill" {
    run grep -F "human-summary" "$CMD_COMPLIANCE"
    [ "$status" -eq 0 ]
}

# 7
@test "dr-compliance.md contains HUMAN SUMMARY step heading" {
    run grep -F "HUMAN SUMMARY" "$CMD_COMPLIANCE"
    [ "$status" -eq 0 ]
}

# 8
@test "dr-archive.md references the human-summary skill" {
    run grep -F "human-summary" "$CMD_ARCHIVE"
    [ "$status" -eq 0 ]
}

# 9
@test "dr-archive.md contains HUMAN SUMMARY step heading" {
    run grep -F "HUMAN SUMMARY" "$CMD_ARCHIVE"
    [ "$status" -eq 0 ]
}

# 10
@test "skill contains the four mandated RU sub-headings" {
    run grep -F "Что было сделано" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "Что получилось" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "Что не получилось" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "Что дальше" "$SKILL"
    [ "$status" -eq 0 ]
}

# 11
@test "skill contains RU mini-example" {
    run grep -E "^## Example \(RU\)" "$SKILL"
    [ "$status" -eq 0 ]
}

# 12
@test "skill contains EN mini-example" {
    run grep -E "^## Example \(EN\)" "$SKILL"
    [ "$status" -eq 0 ]
}

# 13
@test "skill declares length budget 150-400 words" {
    run grep -E "150.{0,3}400" "$SKILL"
    [ "$status" -eq 0 ]
}

# 14
@test "all three commands carry the exact total-budget wording" {
    # Parity guard: skill says "total across the four sub-sections" — every
    # consumer command must restate the same scope so operators do not read
    # 150-400 as per-sub-section.
    run grep -F "total across the four sub-sections" "$CMD_QA"
    [ "$status" -eq 0 ]
    run grep -F "total across the four sub-sections" "$CMD_COMPLIANCE"
    [ "$status" -eq 0 ]
    run grep -F "total across the four sub-sections" "$CMD_ARCHIVE"
    [ "$status" -eq 0 ]
}

# 15
@test "skill documents per-caller mutability" {
    run grep -F "Mutability per caller" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "chat-only" "$SKILL"
    [ "$status" -eq 0 ]
}

# 16
@test "skill clarifies «Mirror» means paraphrase not verbatim copy" {
    run grep -F "Mirror" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "paraphrase, not verbatim" "$SKILL"
    [ "$status" -eq 0 ]
}

# 17
@test "skill documents banlist contract (Option C)" {
    run grep -F "banlist" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "whitelist" "$SKILL"
    [ "$status" -eq 0 ]
}

# 18
@test "skill documents per-paragraph escape hatch fence" {
    run grep -F "<!-- gate:literal -->" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F "<!-- /gate:literal -->" "$SKILL"
    [ "$status" -eq 0 ]
}

# 19
@test "skill documents severity ladder (info / warn / block)" {
    run grep -E "info" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -E "warn" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -E "block" "$SKILL"
    [ "$status" -eq 0 ]
}

# 20
@test "skill documents archive exclusion from re-validation" {
    run grep -F "archive" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -E "(never re-validated|exclud(ed|es) from re-validation|not re-validated|grandfather)" "$SKILL"
    [ "$status" -eq 0 ]
}

# 21
@test "banlist carries representative banned terms" {
    run grep -E "^pipeline([[:space:]]|$|#)" "$BANLIST"
    [ "$status" -eq 0 ]
    run grep -E "^deploy([[:space:]]|$|#)" "$BANLIST"
    [ "$status" -eq 0 ]
    run grep -E "^commit([[:space:]]|$|#)" "$BANLIST"
    [ "$status" -eq 0 ]
    run grep -E "^runtime([[:space:]]|$|#)" "$BANLIST"
    [ "$status" -eq 0 ]
}

# 22
@test "whitelist carries representative universal terms" {
    run grep -E "^JSON([[:space:]]|$|#)" "$WHITELIST"
    [ "$status" -eq 0 ]
    run grep -E "^OAuth([[:space:]]|$|#)" "$WHITELIST"
    [ "$status" -eq 0 ]
    run grep -E "^CLI([[:space:]]|$|#)" "$WHITELIST"
    [ "$status" -eq 0 ]
    run grep -E "^HTTP([[:space:]]|$|#)" "$WHITELIST"
    [ "$status" -eq 0 ]
}

# 23
@test "skill bans tables" {
    run grep -F "No tables" "$SKILL"
    [ "$status" -eq 0 ]
}

# 24
@test "skill caps escape-hatch paragraphs per task" {
    # Per Option C: 3rd gated paragraph → warn; 5th → block.
    run grep -E "(2 paragraphs|two paragraphs|paragraph budget|paragraph cap)" "$SKILL"
    [ "$status" -eq 0 ]
}
