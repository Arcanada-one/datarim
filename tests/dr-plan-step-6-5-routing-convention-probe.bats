#!/usr/bin/env bats
# TUNE-0269 — Step 6.5 public-surface routing convention probe contract regression guard.
# Anchor-based extraction (robust to bullet relocation, BSD vs GNU sed/awk).

DR_PLAN="$BATS_TEST_DIRNAME/../commands/dr-plan.md"

# Extract the bullet block: from header "routing convention probe" to next sibling
# bullet. Case-insensitive via tolower() — portable across BSD/GNU awk.
bullet_block() {
    awk 'tolower($0) ~ /routing convention probe/ {flag=1; print; next}
         flag && /^    -   \*\*/ {exit}
         flag {print}' "$DR_PLAN"
}

@test "Step 6.5 contains 'routing convention probe' bullet" {
    run grep -ci 'routing convention probe' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "Routing probe bullet names a front-controller / router example WITHIN the bullet" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    run bash -c "printf '%s' \"\$1\" | grep -cE 'router/index\\.php|app/routes\\.php|front-controller'" _ "$block"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "Routing probe bullet covers pagination + lang + slug conventions (anchored regex)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" =~ [Pp]agination[[:space:]]format ]]
    [[ "$block" =~ [Ll]ang[[:space:]]prefix ]]
    [[ "$block" =~ [Ss]lug[[:space:]]regex ]]
}

@test "Routing probe bullet prescribes secret redaction in router cite (S3 hardening)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" =~ (DSN|secret|redact|NEVER[[:space:]]cite) ]]
}

@test "Routing probe trigger broadened beyond curl-only to HTTP tooling diversity" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    # Two of the additional HTTP tools must be named in the trigger or examples.
    local hits=0
    [[ "$block" =~ wget ]] && hits=$((hits+1))
    [[ "$block" =~ HTTPie ]] && hits=$((hits+1))
    [[ "$block" =~ [Pp]laywright ]] && hits=$((hits+1))
    [[ "$block" =~ fetch ]] && hits=$((hits+1))
    [[ "$block" =~ [Bb]rowser[[:space:]]smoke ]] && hits=$((hits+1))
    [ "$hits" -ge 2 ]
}

@test "gate:example-only block stays minimal (<=8 inner lines) within routing bullet (SEC-03)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    local inner
    inner=$(printf '%s\n' "$block" | awk '/<!-- gate:example-only -->/{flag=1; next} /<!-- \/gate:example-only -->/{flag=0} flag')
    local n
    # grep -c . counts non-empty lines (the dot matches any character on the line);
    # blank lines inside the gate fence do not count toward the 8-line cap. Intent:
    # bound substantive content, not whitespace.
    n=$(printf '%s\n' "$inner" | grep -c .)
    [ "$n" -le 8 ]
}

@test "Routing probe bullet names a concrete redaction token (S3 binding to falsifiable check)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    # S3 redaction MUST cite a concrete placeholder (ellipsis '…' is the canonical
    # token per the dr-plan.md routing bullet) — without a named token, the redaction
    # clause is prose-only and reviewers cannot falsify a generated plan's compliance.
    [[ "$block" =~ (…|\<REDACTED\>|\<\*\*\*\>) ]]
}
