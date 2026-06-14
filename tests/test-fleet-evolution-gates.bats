#!/usr/bin/env bats
# tests/test-fleet-evolution-gates.bats — constraint gates (fail-closed).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    GATES="$REPO/plugins/dr-fleet-evolution/gates"
    TMP="$BATS_TEST_TMPDIR"

    # A clean, in-budget, English-only, secret-free candidate.
    GOOD="$TMP/good.md"
    cat > "$GOOD" <<'EOF'
---
name: fleet-l1-candidate
metadata:
  fleet_level: 1
  context_budget_tokens: 200
---

# Fleet L1 — candidate

Execute the task in one step. Stop and report a level-mismatch if it needs more.
EOF
}

@test "all gate scripts are executable" {
    for g in "$GATES"/gate-*.sh "$GATES/run-all-gates.sh"; do
        [ -x "$g" ]
    done
}

# --- gate-english ---------------------------------------------------------

@test "gate-english passes typographic punctuation (em-dash, arrow)" {
    run "$GATES/gate-english.sh" "$GOOD" l1-basic
    [ "$status" -eq 0 ]
}

@test "gate-english fails on Cyrillic text (non-Latin script)" {
    local bad="$TMP/cyr.md"
    cp "$GOOD" "$bad"
    printf '\nЭто кириллица — запрещено.\n' >> "$bad"
    run "$GATES/gate-english.sh" "$bad" l1-basic
    [ "$status" -eq 1 ]
}

@test "gate-english honours an allow-non-ascii escape on the same line" {
    local ok="$TMP/allow.md"
    cp "$GOOD" "$ok"
    printf '\nactiveContext.md секция <!-- allow-non-ascii: schema-defined heading -->\n' >> "$ok"
    run "$GATES/gate-english.sh" "$ok" l1-basic
    [ "$status" -eq 0 ]
}

# --- gate-size-budget -----------------------------------------------------

@test "gate-size-budget passes a candidate within budget" {
    run "$GATES/gate-size-budget.sh" "$GOOD" l1-basic
    [ "$status" -eq 0 ]
}

@test "gate-size-budget fails a candidate over budget" {
    local big="$TMP/big.md"
    {
        printf -- '---\nmetadata:\n  context_budget_tokens: 10\n---\n\n'
        head -c 400 /dev/zero | tr '\0' 'x'
    } > "$big"
    run "$GATES/gate-size-budget.sh" "$big" l1-basic
    [ "$status" -eq 1 ]
}

@test "gate-size-budget exits 2 when budget field is absent" {
    local nob="$TMP/nobudget.md"
    printf -- '---\nname: x\n---\nbody\n' > "$nob"
    run "$GATES/gate-size-budget.sh" "$nob" l1-basic
    [ "$status" -eq 2 ]
}

# --- gate-no-secrets ------------------------------------------------------

@test "gate-no-secrets passes a clean candidate" {
    run "$GATES/gate-no-secrets.sh" "$GOOD" l1-basic
    [ "$status" -eq 0 ]
}

@test "gate-no-secrets fails on an embedded api key" {
    local sec="$TMP/sec.md"
    cp "$GOOD" "$sec"
    printf '\napi_key=sk-live-abc123def456\n' >> "$sec"
    run "$GATES/gate-no-secrets.sh" "$sec" l1-basic
    [ "$status" -eq 1 ]
}

# --- run-all-gates (fail-closed orchestrator) -----------------------------

@test "run-all-gates passes a fully clean candidate" {
    if ! command -v bats >/dev/null 2>&1; then skip "bats unavailable"; fi
    run "$GATES/run-all-gates.sh" "$GOOD" l1-basic
    [ "$status" -eq 0 ]
}

@test "run-all-gates fails (exit 1) when any single gate fails" {
    local bad="$TMP/badall.md"
    cp "$GOOD" "$bad"
    printf '\nЗапрещённая кириллица.\n' >> "$bad"
    run "$GATES/run-all-gates.sh" "$bad" l1-basic
    [ "$status" -eq 1 ]
}

@test "run-all-gates exits 2 on usage error (missing level)" {
    run "$GATES/run-all-gates.sh" "$GOOD"
    [ "$status" -eq 2 ]
}
