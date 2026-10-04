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
#   - 3 mandatory fields (How it was verified / Command and observed result / Verdict)
#   - Localize presentation in the resolved artifact language, preserving evidence
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

@test "Per-Wish block template declares verification sub-heading" {
    extract_layer_3b | grep -F "**How it was verified:**" >/dev/null
}

@test "Per-Wish block template declares command-and-observed-result sub-heading" {
    extract_layer_3b | grep -F "**Command and observed result:**" >/dev/null
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

@test "Layer 3b ties every operator wish to the observed verification evidence" {
    extract_layer_3b | grep -F "Each operator wish needs its own record of what was checked" >/dev/null
    extract_layer_3b | grep -F "a one-to-one link between intent and evidence" >/dev/null
}

@test "Per-Wish presentation uses resolved artifact language and preserves machine evidence" {
    extract_layer_3b | tr '\n' ' ' | grep -F \
        "Localize the following presentation labels and prose in the resolved artifact language." >/dev/null
    extract_layer_3b | grep -F "Keep wish identifiers, evidence enums, exact commands, stdout/stderr," >/dev/null
    extract_layer_3b | grep -F "exit codes and measured values unchanged." >/dev/null
}

@test "Layer 3b declares evidence-type-mismatch finding class" {
    extract_layer_3b | grep -q "evidence-type-mismatch"
}

@test "Layer 3b declares per-wish-block-missing finding class" {
    extract_layer_3b | grep -q "per-wish-block-missing"
}
