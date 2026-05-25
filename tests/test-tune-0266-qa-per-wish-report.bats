#!/usr/bin/env bats
# test-tune-0266-qa-per-wish-report.bats — Phase 3 /dr-qa Layer 3b
# per-wish detailed report extension.
#
# Contract tests (grep-based against dr-qa.md markdown) — the actual
# per-wish block writing is agent-controlled at runtime (the agent
# consumes dr-qa.md as instructions); verification happens at Phase 6
# dogfooding (/dr-qa TUNE-0266 produces qa-report-TUNE-0266.md with
# 8 per-wish blocks following the template).
#
# Covers:
#   - Per-Wish Detailed Block Template presence in dr-qa.md Layer 3b
#   - 3 mandatory sub-headings (Что было сделано / Команда + результат / Verdict)
#   - evidence_type rules (empirical / static / measurement) declared
#   - Per-wish block instruction in the per-item walk
#
# Companion plan: datarim/plans/TUNE-0266-plan.md § Phase 3.

CMDS_DIR="$BATS_TEST_DIRNAME/../commands"

# Extract Layer 3b section (between "## Layer 3b" and "## Layer 4")
extract_layer_3b() {
    awk '/^## Layer 3b/{flag=1} /^## Layer 4/{flag=0} flag' "$CMDS_DIR/dr-qa.md"
}

@test "dr-qa.md Layer 3b reads evidence_type from each wish (v2 schema)" {
    extract_layer_3b | grep -E "read.*evidence_type|evidence_type.*v2" >/dev/null
}

@test "dr-qa.md Layer 3b declares mandatory per-wish block write (TUNE-0266)" {
    extract_layer_3b | grep -iE "TUNE-0266.*mandatory|mandatory.*per-wish block|qa-report.*per-wish" >/dev/null
}

@test "dr-qa.md Layer 3b contains Per-Wish Detailed Block Template heading" {
    extract_layer_3b | grep -q "Per-Wish Detailed Block Template"
}

@test "Per-Wish block template uses heading pattern '#### Wish N'" {
    extract_layer_3b | grep -E "^#### Wish \{N\} —|#### Wish .* —" >/dev/null
}

@test "Per-Wish block template declares Evidence type field" {
    extract_layer_3b | grep -E "\*\*Evidence type:" >/dev/null
}

@test "Per-Wish block template declares what-was-done sub-heading" {
    extract_layer_3b | grep -F "Что было сделано для проверки" >/dev/null
}

@test "Per-Wish block template declares command-plus-result sub-heading" {
    extract_layer_3b | grep -F "Команда + результат" >/dev/null
}

@test "Per-Wish block template declares 'Verdict' field" {
    extract_layer_3b | grep -E "\*\*Verdict:" >/dev/null
}

@test "Layer 3b declares empirical evidence_type rule (runtime command required)" {
    extract_layer_3b | grep -iE "empirical.*runtime|empirical.*MUST.*command" >/dev/null
}

@test "Layer 3b declares measurement evidence_type rule (numeric value required)" {
    extract_layer_3b | grep -iE "measurement.*numeric|numeric value.*comparison" >/dev/null
}

@test "Layer 3b declares static evidence_type rule (grep/file-check acceptable)" {
    extract_layer_3b | grep -iE "static.*(grep|file-check|MAY use|file presence)" >/dev/null
}

@test "Layer 3b cites operator goal rationale from TUNE-0266 brief" {
    extract_layer_3b | grep -F "по каждому пункту отчёт" >/dev/null
}

@test "Layer 3b declares evidence-type-mismatch finding class" {
    extract_layer_3b | grep -q "evidence-type-mismatch"
}

@test "Layer 3b declares per-wish-block-missing finding class" {
    extract_layer_3b | grep -q "per-wish-block-missing"
}
