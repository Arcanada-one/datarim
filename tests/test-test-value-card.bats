#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    VALIDATOR="$REPO_ROOT/dev-tools/check-test-value-card.py"
    CARD="$BATS_TEST_TMPDIR/card.md"
}

write_card() {
    cat >"$CARD"
}

@test "accepts a card whose causal regression is demonstrated red before repair" {
    write_card <<'EOF'
---
protects: "Invalid test-value cards are rejected before they justify coverage."
fails_when: "Removing the causal check makes this fixture test fail at its assertion."
why_new: "Existing gates check template links, not test-value meaning."
seam: "none"
no_claim: "Structural card validation does not prove a production test ran."
---
EOF
    run python3 "$VALIDATOR" --card "$CARD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test value card: PASS"* ]]
}

@test "rejects a card without a specific causal failure" {
    for generic_condition in If When; do
        cat >"$CARD" <<EOF
---
protects: "A behavior contract."
fails_when: "${generic_condition} this test runs, its assertion fails."
why_new: "Existing gates check structure, not causal test evidence."
seam: "none"
no_claim: "No production behavior is proven."
---
EOF
        run python3 "$VALIDATOR" --card "$CARD"
        [ "$status" -eq 1 ]
        [[ "$output" == *"causal trigger"* ]]
    done
}

@test "rejects a named seam introduced only for tests" {
    write_card <<'EOF'
---
protects: "A real input boundary."
fails_when: "Removing the boundary check makes the fixture fail."
why_new: "Existing coverage starts after this boundary."
seam: "forced-red hook; testing only; no production caller"
no_claim: "Synthetic fixture only; no live service claim."
---
EOF
    run python3 "$VALIDATOR" --card "$CARD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"production caller"* ]]
}

@test "accepts a named existing seam only with a production caller and reason" {
    write_card <<'EOF'
---
protects: "The parser rejects malformed records at its public boundary."
fails_when: "Bypassing the parser check makes the malformed-record fixture fail."
why_new: "Current tests cover normalized records only."
seam: "parse_record; production caller: ingest_file; needed because malformed bytes enter there"
no_claim: "Parser fixture only; no storage or ingestion acceptance claim."
---
EOF
    run python3 "$VALIDATOR" --card "$CARD"
    [ "$status" -eq 0 ]
}

@test "rejects any value exceeding 160 UTF-8 bytes" {
    python3 - "$CARD" <<'PY'
from pathlib import Path
import sys
card = '''---
protects: "''' + ('é' * 81) + '''"
fails_when: "Removing the required check makes the fixture fail."
why_new: "Existing tests cover another boundary."
seam: "none"
no_claim: "Synthetic fixture only."
---
'''
Path(sys.argv[1]).write_text(card, encoding='utf-8')
PY
    run python3 "$VALIDATOR" --card "$CARD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"160 UTF-8 bytes"* ]]
}

@test "emits the stable valid JSON summary without changing the card" {
    write_card <<'EOF'
---
protects: "Invalid test-value cards are rejected before they justify coverage."
fails_when: "Removing the causal check makes this fixture test fail at its assertion."
why_new: "Existing gates check template links, not test-value meaning."
seam: "none"
no_claim: "Structural card validation does not prove a production test ran."
---
EOF
    before="$(sha256sum "$CARD" | cut -d' ' -f1)"
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
    [ "$output" = '{"diagnostic_codes":[],"exit_code":0,"result":true,"schema":"TestValueCardValidationSummary/v1","status":"valid","validation_error_count":0,"validation_error_count_status":"MEASURED"}' ]
    after="$(sha256sum "$CARD" | cut -d' ' -f1)"
    [ "$before" = "$after" ]
}

@test "maps validation failures to fixed codes and redacts hostile paths and card values" {
    CARD="$BATS_TEST_TMPDIR/path-secret-marker/card-secret-marker.md"
    mkdir -p "$(dirname "$CARD")"
    cat >"$CARD" <<'EOF'
---
protects: "frontmatter-secret-marker"
fails_when: "When this test runs, its assertion fails."
why_new: "Existing gates check structure, not causal test evidence."
seam: "none"
no_claim: "No production behavior is proven."
---
EOF
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 1 ]
    [ -z "$stderr" ]
    [[ "$output" == *'"diagnostic_codes":["CAUSAL_EVIDENCE_INVALID"]'* ]]
    [[ "$output" == *'"validation_error_count":1'* ]]
    [[ "$output" != *"$CARD"* ]]
    [[ "$output" != *"path-secret-marker"* ]]
    [[ "$output" != *"frontmatter-secret-marker"* ]]
    [[ "$output" != *"this test runs"* ]]
}

@test "reports unreadable input with unknown count and no path details" {
    CARD="$BATS_TEST_TMPDIR/unreadable-path-secret/card.md"
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 2 ]
    [ -z "$stderr" ]
    [ "$output" = '{"diagnostic_codes":["CARD_UNREADABLE"],"exit_code":2,"result":false,"schema":"TestValueCardValidationSummary/v1","status":"unreadable","validation_error_count":null,"validation_error_count_status":"NOT_MEASURED"}' ]
    [[ "$output" != *"$CARD"* ]]

    CARD="$BATS_TEST_TMPDIR/invalid-encoding.md"
    printf '\377' >"$CARD"
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 2 ]
    [ -z "$stderr" ]
    [[ "$output" == *'"validation_error_count":null'* ]]
}

@test "JSON and default modes preserve the same validation exit for invalid cards" {
    write_card <<'EOF'
---
protects: "A behavior contract."
fails_when: "If this test runs, its assertion fails."
why_new: "Existing gates check structure, not causal test evidence."
seam: "none"
no_claim: "No production behavior is proven."
---
EOF
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"causal trigger"* ]]
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 1 ]
    [ -z "$stderr" ]
    [[ "$output" == *'"status":"invalid"'* ]]
    [[ "$output" == *'"exit_code":1'* ]]
}

@test "JSON diagnostics cover malformed YAML, non-mapping, missing fields and invalid seams" {
    printf '%s\n' '---' 'field: [unclosed' '---' >"$CARD"
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 1 ]
    [ -z "$stderr" ]
    [[ "$output" == *'"diagnostic_codes":["YAML_INVALID"]'* ]]
    [[ "$output" != *"unclosed"* ]]

    printf '%s\n' '---' '- item' '---' >"$CARD"
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"diagnostic_codes":["FRONTMATTER_NOT_MAPPING"]'* ]]

    printf '%s\n' '---' 'protects: "concrete"' '---' >"$CARD"
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"diagnostic_codes":["FIELD_TYPE_INVALID"]'* ]]

    cat >"$CARD" <<'EOF'
---
protects: "A real input boundary."
fails_when: "Bypassing the parser check makes the fixture fail."
why_new: "Current tests cover normalized records only."
seam: "forced-red hook; testing only; no production caller"
no_claim: "Synthetic fixture only; no live service claim."
---
EOF
    run --separate-stderr python3 "$VALIDATOR" --card "$CARD" --summary-json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"diagnostic_codes":["SEAM_INVALID"]'* ]]
}
