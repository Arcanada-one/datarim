#!/usr/bin/env bats
#
# Spec-regression tests for the human-summary contract.
#
# Verifies that the operator-facing commands (/dr-qa, /dr-compliance,
# /dr-archive, /dr-auto) reference the human-summary skill and that the skill itself
# carries the four mandated sub-headings, the RU+EN mini-examples, and the
# Option C banlist + whitelist + per-paragraph escape-hatch contract.
#
# Coverage target: ≥16 cases.

SKILL="${BATS_TEST_DIRNAME}/../skills/human-summary/SKILL.md"
BANLIST="${BATS_TEST_DIRNAME}/../skills/human-summary/banlist.txt"
WHITELIST="${BATS_TEST_DIRNAME}/../skills/human-summary/whitelist.txt"
CMD_QA="${BATS_TEST_DIRNAME}/../commands/dr-qa.md"
CMD_COMPLIANCE="${BATS_TEST_DIRNAME}/../commands/dr-compliance.md"
CMD_ARCHIVE="${BATS_TEST_DIRNAME}/../commands/dr-archive.md"
CMD_AUTO="${BATS_TEST_DIRNAME}/../commands/dr-auto.md"
CMD_QUICK="${BATS_TEST_DIRNAME}/../commands/dr-quick.md"
EVOLUTION="${BATS_TEST_DIRNAME}/../skills/evolution/SKILL.md"

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
@test "skill contains the four language-neutral semantic sub-section markers" {
    for key in done worked open next; do
        run grep -F "datarim:summary:${key}" "$SKILL"
        [ "$status" -eq 0 ]
    done
    run grep -F 'datarim:operator-summary' "$SKILL"
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
@test "skill preserves completeness without a hard word cap" {
    run grep -F "no hard word cap" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -E "Hard upper bound|compress aggressively|drop detail; never extend" "$SKILL"
    [ "$status" -ne 0 ]
}

# 14
@test "all three commands carry the completeness-first policy" {
    # Each consumer must retain the no-cap policy across all four sections.
    for command in "$CMD_QA" "$CMD_COMPLIANCE" "$CMD_ARCHIVE"; do
        run grep -F "no hard word cap" "$command"
        [ "$status" -eq 0 ]
    done
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

# These are static prompt-contract checks only. They do not prove a delegated
# agent emitted the summary in a live chat; runtime delivery remains NOT_MEASURED.

# 25 — fail-before on the pre-fix source: /dr-auto did not require this handoff.
@test "dr-auto forwards delegated reflection states through the human-summary skill" {
    run grep -F 'skills/human-summary/SKILL.md' "$CMD_AUTO"
    [ "$status" -eq 0 ]
    run grep -F 'current reflection artifact' "$CMD_AUTO"
    [ "$status" -eq 0 ]
    run grep -F 'compliance report when one exists' "$CMD_AUTO"
    [ "$status" -eq 0 ]
    for state in 'pending approval' 'held' 'applied' 'rejected'; do
        run grep -F "$state" "$CMD_AUTO"
        [ "$status" -eq 0 ]
    done
    run grep -F 'do not reduce this handoff to the compliance verdict' "$CMD_AUTO"
    [ "$status" -eq 0 ]
    run grep -F 'When compliance ran, include its recorded verdict in the summary' "$CMD_AUTO"
    [ "$status" -eq 0 ]
}

# 26 — omission controls: absent evidence or skipped stages cannot become "none".
@test "dr-auto preserves reflection and compliance omission states" {
    run grep -F 'If reflection is absent, stale, or unavailable, report it as unmeasured' "$CMD_AUTO"
    [ "$status" -eq 0 ]
    run grep -F 'do not imply reflection ran' "$CMD_AUTO"
    [ "$status" -eq 0 ]
    run grep -F 'Say "no proposals" only when the current reflection artifact confirms none' "$CMD_AUTO"
    [ "$status" -eq 0 ]
}

# 27 — propagation controls: summary rules retain status and application evidence.
@test "human-summary distinguishes proposal states and requires application evidence" {
    for phrase in 'No proposals:' 'Pending approval:' 'Held:' 'Applied:' 'Rejected:'; do
        run grep -F "$phrase" "$SKILL"
        [ "$status" -eq 0 ]
    done
    run grep -F 'actual learning/evolution record' "$SKILL"
    [ "$status" -eq 0 ]
    run grep -F 'source prompt contract' "$SKILL"
    [ "$status" -eq 0 ]
}

# 28 — quick remains light; only a verified corrected mismatch creates a signal.
@test "dr-quick emits a conditional learning signal only for verified mutating mistakes" {
    run grep -F 'Conditional learning signal (mutating QCK only)' "$CMD_QUICK"
    [ "$status" -eq 0 ]
    run grep -F 'concrete mistake or logic mismatch' "$CMD_QUICK"
    [ "$status" -eq 0 ]
    run grep -F 'corrected and verified by its acceptance/evidence check' "$CMD_QUICK"
    [ "$status" -eq 0 ]
    run grep -F 'ordinary quick fixes and all read-only lookups' "$CMD_QUICK"
    [ "$status" -eq 0 ]
    run grep -F 'If no such verified mismatch occurred' "$CMD_QUICK"
    [ "$status" -eq 0 ]
    run grep -F 'it is a proposal record, not an applied skill' "$CMD_QUICK"
    [ "$status" -eq 0 ]
}

# 29 — trigger docs match compliance primary and archive freshness fallback.
@test "evolution trigger contract names compliance primary and archive fallback" {
    run grep -F 'Automatic: Inside `/dr-compliance` Step 8.5' "$EVOLUTION"
    [ "$status" -eq 0 ]
    run grep -F '`/dr-archive` Step 0.5 is the fallback' "$EVOLUTION"
    [ "$status" -eq 0 ]
    run grep -F 'primary trigger later moved to passing `/dr-compliance` Step 8.5' "$EVOLUTION"
    [ "$status" -eq 0 ]
}
