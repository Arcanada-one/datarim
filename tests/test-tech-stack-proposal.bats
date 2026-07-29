#!/usr/bin/env bats
#
# Contract tests for skills/tech-stack/SKILL.md — TUNE-0530.
#
# Verifies:
#   T1 — Stack proposal template shape (mandatory sections present)
#   T2 — Trigger classifier (correct routing for key scenarios)
#   T3 — No prescriptive MANDATORY stack assignments
#   T4 — Rust and Go are first-class options
#   T5 — Immutability binding documented (ADR, Return-to-Source, Security-Emergency Fast-Track)
#   T6 — Security posture factor present in proposal template
#   T7 — Escape velocity factor present in proposal template
#   T8 — New domains present (CLI, Desktop, Systems, Data/ML, WASM)

SKILL="${BATS_TEST_DIRNAME}/../skills/tech-stack/SKILL.md"

setup() {
    if [ ! -f "$SKILL" ]; then
        skip "skills/tech-stack/SKILL.md not found"
    fi
}

# ---------------------------------------------------------------------------
# T1 — Stack proposal template shape
# ---------------------------------------------------------------------------

@test "T1 — stack proposal template has mandatory sections" {
    run grep -c "## Stack Proposal Template" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "### Context" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "### Candidate Stacks" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "### Trade-off Summary" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "### Recommendation" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "### Operator Decision" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Candidate ordering: recommendation separate from position (no "Candidate 1 (Recommended)")
    run grep -cE "Candidate [0-9].*Recommended" "$SKILL"
    [ "$status" -eq 1 ]  # grep -c returns 0 matches (exit 1) = no positional Recommended labels
}

# ---------------------------------------------------------------------------
# T2 — Trigger classifier
# ---------------------------------------------------------------------------

@test "T2 — trigger classifier has required signals and default catch-all" {
    run grep -c "Trigger.*FULL" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "Trigger.*SKIP" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Stack-migration trigger
    run grep -c "stack.migration\|Stack migration" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Default catch-all
    run grep -c "default to.*FULL\|Default catch-all\|When uncertain.*FULL\|cost of an unnecessary proposal" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # L1 exclusion
    run grep -c "L1.*SKIP\|L1.*skip\|L1 tasks.*SKIP" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Sticky choices / child-task inheritance
    run grep -c "inherit\|sticky\|auto-inherit" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T3 — No prescriptive MANDATORY stack assignments
# ---------------------------------------------------------------------------

@test "T3 — no prescriptive MANDATORY language in stack assignments" {
    # The old heading must be gone
    run grep -c "Project Type.*Required Stack" "$SKILL"
    [ "$status" -eq 1 ]  # grep returns 0 matches = exit 1

    # "Required Stack" as a section heading must be gone
    run grep -c "Required Stack" "$SKILL"
    [ "$status" -eq 1 ]

    # Old Final Rule that suppressed operator choice
    run grep -c "Do NOT ask which stack to use" "$SKILL"
    [ "$status" -eq 1 ]

    # Old "Apply rules automatically" anti-choice mandate
    run grep -c "Apply.*rules.*automatically\|Apply these rules automatically" "$SKILL"
    [ "$status" -eq 1 ]

    # "No guessing, no inventing, no asking" anti-choice TL;DR
    run grep -c "No guessing.*no inventing.*no asking" "$SKILL"
    [ "$status" -eq 1 ]

    # Heading reworked
    run grep -c "Starting Points.*Alternatives\|Starting Points & Alternatives" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T4 — Rust and Go are first-class options
# ---------------------------------------------------------------------------

@test "T4 — Rust and Go appear as first-class options in >=3 rows each" {
    # Rust: count rows where Rust appears as a stack option (in table rows or Default Recommendation / Viable Alternatives columns)
    # The pipe-delimited table rows have Rust in Viable Alternatives or Default Recommendation
    rust_count=$(grep -cE '\*\*.*Rust.*\*\*|Rust \+' "$SKILL" || true)
    [ "$rust_count" -ge 3 ]

    go_count=$(grep -cE '\*\*.*Go \+.*\*\*|Go \+' "$SKILL" || true)
    [ "$go_count" -ge 3 ]
}

# ---------------------------------------------------------------------------
# T5 — Immutability binding documented
# ---------------------------------------------------------------------------

@test "T5 — immutability binding documented with escape sequence" {
    # ADR / decision note binding
    run grep -c "decision note\|ADR" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Return-to-Source or Return-to-Plan mentioned
    run grep -c "Return-to-Plan\|Return-to-Source" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Security-emergency fast-track
    run grep -c "Security-Emergency Fast-Track\|security-emergency\|CVSS.*9\|KEV" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Concrete escape sequence steps
    run grep -c "Changing the Stack During Implementation" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Binding contract referenced
    run grep -c "immutability contract\|immutability.*SKILL" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T6 — Security posture factor in proposal template
# ---------------------------------------------------------------------------

@test "T6 — security posture is a mandatory factor in the proposal template" {
    run grep -c "Security posture" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # CVE history referenced in security factor
    run grep -c "CVE\|vulnerability history\|supply-chain trust\|SLSA" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T7 — Escape velocity factor in proposal template
# ---------------------------------------------------------------------------

@test "T7 — escape velocity is a mandatory factor in the proposal template" {
    run grep -c "Escape velocity" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Must appear in the decision note format too
    run grep -c "how hard to migrate" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T8 — New domains present
# ---------------------------------------------------------------------------

@test "T8 — five new domains are present in the Starting Points table" {
    run grep -c "Cross-Platform CLI" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "Desktop Application" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "Systems Daemon" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "Data.*ML Pipeline\|Data / ML Pipeline" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "WASM Module" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T9 — Licence and cost are separate factors
# ---------------------------------------------------------------------------

@test "T9 — licence compatibility and cost are separate factors in proposal template" {
    run grep -c "Licence compatibility" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Cost must be a separate factor from licence
    run grep -cE '^\| Cost \|' "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# T10 — Backend-standards boundary documented
# ---------------------------------------------------------------------------

@test "T10 — backend-stack-standards.md boundary is documented" {
    run grep -c "backend-stack-standards" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c "authoritative mandate" "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
