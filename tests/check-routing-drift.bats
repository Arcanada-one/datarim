#!/usr/bin/env bats
#
# Tests for scripts/check-routing-drift.sh (TUNE-0022).
#
# Contract under test:
#   - R1: clean fixture → exit 0 (canonical sequences + all derived files in sync)
#   - R2-R4: drop a single token from any derived file → exit 1, file:level + token in output
#   - R5: missing invariants file → exit 2 with ERROR
#   - R6: --quiet suppresses output, exit code only
#
# Tmpdir isolation: each test builds a minimal FAKE_REPO mirroring repo-relative
# paths used by the mapping block in routing-invariants.md.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
    export FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$FAKE_REPO/scripts"
    mkdir -p "$FAKE_REPO/skills/datarim-system"
    mkdir -p "$FAKE_REPO/skills/visual-maps"
    mkdir -p "$FAKE_REPO/commands"

    cp "$REPO_ROOT/scripts/check-routing-drift.sh" "$FAKE_REPO/scripts/check-routing-drift.sh"
    chmod +x "$FAKE_REPO/scripts/check-routing-drift.sh"
    cp "$REPO_ROOT/skills/datarim-system/routing-invariants.md" \
       "$FAKE_REPO/skills/datarim-system/routing-invariants.md"

    # Seed each derived file with EXACTLY the canonical tokens from the real
    # runtime — minimal content is enough; the script greps by literal substring.
    cat > "$FAKE_REPO/skills/datarim-system/backlog-and-routing.md" <<'EOF'
# backlog-and-routing fixture
| `/dr-plan` | L3-4 | `/dr-design {TASK-ID}` |
| `/dr-plan` | L1-2 | `/dr-do {TASK-ID}` |
| `/dr-design` | L3-4 | `/dr-do {TASK-ID}` |
| `/dr-do` | L3-4 | `/dr-qa {TASK-ID}` |
| `/dr-do` | L1-2 | `/dr-archive {TASK-ID}` |
| `/dr-qa` PASS / CONDITIONAL_PASS | L3-4 | `/dr-compliance {TASK-ID}` |
| `/dr-qa` PASS / CONDITIONAL_PASS | L1-2 | `/dr-archive {TASK-ID}` |
| `/dr-compliance` COMPLIANT* | L3-4 | `/dr-archive {TASK-ID}` |
EOF

    cat > "$FAKE_REPO/skills/visual-maps/pipeline-routing.md" <<'EOF'
# pipeline-routing fixture
Do1 --> Archive1
Plan2 --> Do2
Do2 --> QA2
QA2 --> Archive2
Plan3 --> Design3
Design3 --> Do3
Do3 --> QA3
QA3 --> Compliance3
Compliance3 --> Archive3
Plan4 --> Design4
Design4 --> Do4
Do4 --> QA4
QA4 --> Comp4
Comp4 --> Archive4
EOF

    cat > "$FAKE_REPO/skills/visual-maps/stage-process-flows.md" <<'EOF'
# stage-process-flows fixture
| `/dr-plan` (L3-4) | `/dr-design {TASK-ID}` |
| `/dr-plan` (L1-2) | `/dr-do {TASK-ID}` |
| `/dr-do` (L3-4) | `/dr-qa {TASK-ID}` |
| `/dr-do` (L1-2) | `/dr-archive {TASK-ID}` |
| `/dr-qa` PASS / CONDITIONAL_PASS (L3-4) | `/dr-compliance {TASK-ID}` |
| `/dr-compliance` COMPLIANT | `/dr-archive {TASK-ID}` |
EOF

    cat > "$FAKE_REPO/commands/dr-plan.md" <<'EOF'
# dr-plan fixture
- L3-4 with creative-phase needs → primary `/dr-design {TASK-ID}`
- L3-4 without creative-phase needs → primary `/dr-do {TASK-ID}`
- L1-2 → primary `/dr-do {TASK-ID}`
EOF

    cat > "$FAKE_REPO/commands/dr-qa.md" <<'EOF'
# dr-qa fixture
- ALL_PASS or CONDITIONAL_PASS at L3-4 → primary `/dr-compliance {TASK-ID}`
- ALL_PASS or CONDITIONAL_PASS at L1-2 → primary `/dr-archive {TASK-ID}`
EOF

    cat > "$FAKE_REPO/commands/dr-do.md" <<'EOF'
# dr-do fixture
- All checks pass, L3-4 → primary `/dr-qa {TASK-ID}`
- All checks pass, L1-2 → primary `/dr-archive {TASK-ID}`
EOF
}

run_check() {
    run env DATARIM_REPO_DIR="$FAKE_REPO" "$FAKE_REPO/scripts/check-routing-drift.sh" "$@"
}

# ---------- R1: sync baseline ----------

@test "R1 sync baseline: clean fixture → exit 0" {
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"all 35 routing tokens in sync"* ]]
}

# ---------- R2-R4: drift injection per surface family ----------

@test "R2 drift in backlog-and-routing.md → exit 1, file + token reported" {
    # Remove the L3-4 plan→design row by overwriting without it.
    sed -i.bak '/L3-4 | `\/dr-design/d' "$FAKE_REPO/skills/datarim-system/backlog-and-routing.md"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"backlog-and-routing.md"* ]]
    [[ "$output" == *"plan→design"* ]]
}

@test "R3 drift in pipeline-routing.md (Mermaid edge removed) → exit 1" {
    sed -i.bak '/QA3 --> Compliance3/d' "$FAKE_REPO/skills/visual-maps/pipeline-routing.md"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"pipeline-routing.md"* ]]
    [[ "$output" == *"qa→compliance"* ]]
}

@test "R4 drift in dr-plan.md CTA → exit 1" {
    sed -i.bak '/creative-phase needs → primary `\/dr-design/d' "$FAKE_REPO/commands/dr-plan.md"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"dr-plan.md"* ]]
    [[ "$output" == *"plan→design"* ]]
}

# ---------- R5: missing invariants file ----------

@test "R5 missing routing-invariants.md → exit 2 with ERROR" {
    rm -f "$FAKE_REPO/skills/datarim-system/routing-invariants.md"
    run_check
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"routing-invariants.md"* ]]
}

# ---------- R6: --quiet flag ----------

@test "R6 --quiet suppresses output on sync (exit 0, empty stdout)" {
    run_check --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "R6b --quiet suppresses output on drift (exit 1, empty stdout)" {
    sed -i.bak '/L3-4 | `\/dr-design/d' "$FAKE_REPO/skills/datarim-system/backlog-and-routing.md"
    run_check --quiet
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# ---------- Edge: missing derived file ----------

@test "R7 derived file deleted → exit 1, 'derived file missing' reported" {
    rm -f "$FAKE_REPO/commands/dr-do.md"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"dr-do.md"* ]]
    [[ "$output" == *"derived file missing"* ]]
}
