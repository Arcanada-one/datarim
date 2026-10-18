#!/usr/bin/env bats

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
    write_card <<'EOF'
---
protects: "A behavior contract."
fails_when: "No known failure; this test seems useful."
why_new: "The test is new."
seam: "none"
no_claim: "No production behavior is proven."
---
EOF
    run python3 "$VALIDATOR" --card "$CARD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"causal trigger"* ]]
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
