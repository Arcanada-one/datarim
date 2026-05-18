#!/usr/bin/env bats
#
# Spec-regression: skills/testing/live-smoke-gates.md must carry a
# `Current-State Auth Probe` subsection placed AFTER the
# `# Live Smoke-Test Gates` H1 header.
#
# Contract: the subsection prescribes an auth-scoped probe step before any
# live smoke-test that crosses an authentication boundary. Wording MUST be
# stack-neutral (no Auth Arcana, no AUTH-NNNN, no ecosystem-specific repo
# names). The subsection is a cross-cutting prerequisite for all gates that
# follow, not a standalone numbered gate.

FRAGMENT="${BATS_TEST_DIRNAME}/../skills/testing/live-smoke-gates.md"

@test "fragment file exists" {
    [ -f "$FRAGMENT" ]
}

@test "subsection 'Current-State Auth Probe' header is present" {
    run grep -E "^## Current-State Auth Probe\b" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "subsection appears AFTER '# Live Smoke-Test Gates' header" {
    parent_line=$(grep -n "^# Live Smoke-Test Gates\b" "$FRAGMENT" | head -1 | cut -d: -f1)
    sub_line=$(grep -n "^## Current-State Auth Probe\b" "$FRAGMENT" | head -1 | cut -d: -f1)
    [ -n "$parent_line" ]
    [ -n "$sub_line" ]
    [ "$sub_line" -gt "$parent_line" ]
}

@test "subsection wording is stack-neutral (no Auth Arcana / AUTH-NNNN / Arcanada-one)" {
    sub_line=$(grep -n "^## Current-State Auth Probe\b" "$FRAGMENT" | head -1 | cut -d: -f1)
    [ -n "$sub_line" ]
    # Body spans from subsection header to next ## (or EOF)
    next_h2=$(awk -v start="$sub_line" 'NR>start && /^## / {print NR; exit}' "$FRAGMENT")
    [ -z "$next_h2" ] && next_h2=$(wc -l < "$FRAGMENT")
    body=$(sed -n "${sub_line},${next_h2}p" "$FRAGMENT")
    ! printf '%s' "$body" | grep -qiE "Auth Arcana|\bAUTH-[0-9]{4}\b|Arcanada-one"
}

@test "subsection body fits within 30 lines" {
    sub_line=$(grep -n "^## Current-State Auth Probe\b" "$FRAGMENT" | head -1 | cut -d: -f1)
    next_h2=$(awk -v start="$sub_line" 'NR>start && /^## / {print NR; exit}' "$FRAGMENT")
    [ -z "$next_h2" ] && next_h2=$(wc -l < "$FRAGMENT")
    # Exclude trailing horizontal-rule separator if present
    body_lines=$(( next_h2 - sub_line ))
    [ "$body_lines" -le 30 ]
}
