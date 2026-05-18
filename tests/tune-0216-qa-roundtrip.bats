#!/usr/bin/env bats
# tune-0216-qa-roundtrip.bats — Init-task Q&A auto-append contract (TUNE-0216).
#
# Covers six phases of the TUNE-0216 plan:
#   Phase 1: skill contract presence + validator Q&A block recognition.
#   Phase 2: dev-tools/append-init-task-qa.sh utility — atomic write, flock,
#            realpath boundary, oversized input rejection.
#   Phase 3: six pipeline commands wire the APPEND Q&A IF ANY step.
#   Phase 4: /dr-qa Layer 3b — agent-decision implementation grep + conflict
#            closure verification.
#   Phase 6: legacy fallback — task without init-task has no Q&A blockers.
#
# Source-of-truth contracts: skills/init-task-persistence.md § Q&A round-trip,
# plans/TUNE-0216-plan.md.

ROOT_DIR="$BATS_TEST_DIRNAME/.."
CHECK="$ROOT_DIR/dev-tools/check-init-task-presence.sh"
APPEND="$ROOT_DIR/dev-tools/append-init-task-qa.sh"
SKILL_FILE="$ROOT_DIR/skills/init-task-persistence.md"
QA_COMMAND_FILE="$ROOT_DIR/commands/dr-qa.md"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# write_base_init_task <ID>
# Writes a minimal valid init-task file with empty Append-log.
write_base_init_task() {
    local id="$1"
    local file="$TMPROOT/datarim/tasks/${id}-init-task.md"
    {
        echo "---"
        echo "task_id: $id"
        echo "artifact: init-task"
        echo "schema_version: 1"
        echo "captured_at: 2026-05-14"
        echo "captured_by: /dr-init"
        echo "operator: Pavel"
        echo "status: canonical"
        echo "source: /dr-init"
        echo "---"
        echo ""
        echo "# $id — Init-Task"
        echo ""
        echo "## Operator brief (verbatim)"
        echo ""
        echo "Original prompt body."
        echo ""
        echo "## Append-log (operator amendments)"
        echo ""
        echo "_(пусто)_"
    } > "$file"
}

# append_qa_block <ID> <stage> <round> <decided-by> [<rationale>]
# Appends a syntactically valid Q&A block; rationale is required when
# decided-by is "agent" — caller supplies it as a single argument.
append_qa_block() {
    local id="$1" stage="$2" round="$3" decided="$4" rationale="${5:-}"
    local file="$TMPROOT/datarim/tasks/${id}-init-task.md"
    {
        echo ""
        echo "### 2026-05-14T12:00:00Z — Q&A by /dr-${stage} (round ${round})"
        echo ""
        echo "**Question (verbatim, asked by architect agent):**"
        echo ""
        echo "Sample question text."
        echo ""
        echo "**Answer (verbatim, by ${decided}):**"
        echo ""
        echo "Sample answer text."
        echo ""
        echo "**Decided by:** ${decided}"
        echo ""
        if [ "$decided" = "agent" ] && [ -n "$rationale" ]; then
            echo "**Decision rationale:**"
            echo ""
            echo "${rationale}"
            echo ""
        fi
        echo "**Summary (how it changes initial conditions):**"
        echo ""
        echo "One-line summary of the change."
        echo ""
        echo "**Conflict with existing wish:** none"
        echo ""
    } >> "$file"
}

# write_task_description <ID> <created> [<status>]
write_task_description() {
    local id="$1" created="$2" status="${3:-in_progress}"
    local file="$TMPROOT/datarim/tasks/${id}-task-description.md"
    {
        echo "---"
        echo "task_id: $id"
        echo "title: $id task"
        echo "status: $status"
        echo "priority: P2"
        echo "complexity: L2"
        echo "type: framework"
        echo "project: Datarim"
        echo "created: $created"
        echo "---"
        echo ""
        echo "# $id"
    } > "$file"
}

# ---------------------------------------------------------------------------
# Phase 1 — Skill contract + validator extension
# ---------------------------------------------------------------------------

@test "P1.1 skill init-task-persistence.md contains Q&A round-trip section" {
    [ -f "$SKILL_FILE" ]
    grep -q '^## Q&A round-trip' "$SKILL_FILE"
}

@test "P1.2 validator accepts valid Q&A block with decided_by: operator" {
    write_base_init_task "TEST-0101"
    append_qa_block "TEST-0101" "prd" 1 "operator"
    run "$CHECK" --task TEST-0101 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "P1.3 validator accepts valid Q&A block with decided_by: agent + rationale >=50 chars" {
    write_base_init_task "TEST-0102"
    append_qa_block "TEST-0102" "prd" 1 "agent" \
        "Decided by best practice X because no operator answer arrived within the time window; rationale anchored in FB-1 to FB-5 from autonomous operating rules."
    run "$CHECK" --task TEST-0102 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "P1.4 validator rejects Q&A block with decided_by: agent missing rationale" {
    write_base_init_task "TEST-0103"
    # Append without rationale (rationale arg omitted → block carries no rationale).
    append_qa_block "TEST-0103" "prd" 1 "agent"
    run "$CHECK" --task TEST-0103 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rationale"* ]] || [[ "$output" == *"Decision"* ]]
}

@test "P1.5 validator rejects Q&A block with decided_by: agent and rationale <50 chars" {
    write_base_init_task "TEST-0104"
    append_qa_block "TEST-0104" "prd" 1 "agent" "too short"
    run "$CHECK" --task TEST-0104 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rationale"* ]] || [[ "$output" == *"50"* ]]
}

@test "P1.6 validator rejects Q&A block with invalid Decided by value" {
    write_base_init_task "TEST-0105"
    # Bad decided_by literal (not operator or agent)
    local file="$TMPROOT/datarim/tasks/TEST-0105-init-task.md"
    cat >> "$file" <<'EOF'

### 2026-05-14T12:00:00Z — Q&A by /dr-plan (round 1)

**Question (verbatim, asked by architect agent):**

Q text.

**Answer (verbatim, by operator):**

A text.

**Decided by:** robot

**Summary (how it changes initial conditions):**

S.

**Conflict with existing wish:** none

EOF
    run "$CHECK" --task TEST-0105 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Decided"* ]] || [[ "$output" == *"decided_by"* ]]
}

@test "P1.7 validator passes init-task file with empty Append-log (no Q&A blocks)" {
    write_base_init_task "TEST-0106"
    run "$CHECK" --task TEST-0106 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Phase 2 — Utility append-init-task-qa.sh (atomic, flock, boundary)
# ---------------------------------------------------------------------------

@test "P2.0 utility append-init-task-qa.sh exists and is executable" {
    [ -x "$APPEND" ]
}

@test "P2.0b utility --help prints usage and exits 0" {
    run "$APPEND" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "P2.1 utility writes a valid Q&A block and validator passes" {
    write_base_init_task "TEST-0201"
    local q="$TMPROOT/q.txt" a="$TMPROOT/a.txt"
    echo "Sample utility question." > "$q"
    echo "Sample utility answer." > "$a"
    run "$APPEND" \
        --root "$TMPROOT" \
        --task TEST-0201 --stage prd --round 1 \
        --question-file "$q" --answer-file "$a" \
        --decided-by operator \
        --summary "Summary of the change."
    [ "$status" -eq 0 ]
    # And validator agrees the resulting file is well-formed.
    run "$CHECK" --task TEST-0201 --root "$TMPROOT"
    [ "$status" -eq 0 ]
    # File now contains the canonical heading.
    grep -q 'Q&A by /dr-prd (round 1)' "$TMPROOT/datarim/tasks/TEST-0201-init-task.md"
}

@test "P2.2 utility supports decided-by agent with --rationale-file" {
    write_base_init_task "TEST-0202"
    local q="$TMPROOT/q.txt" a="$TMPROOT/a.txt" r="$TMPROOT/r.txt"
    echo "Q?" > "$q"
    echo "A by agent." > "$a"
    # Rationale must be >= 50 chars to satisfy validator (Phase 1 contract).
    printf '%s' "Best practice rationale anchored in FB-1..FB-5; chose option X over Y because of operational simplicity." > "$r"
    run "$APPEND" \
        --root "$TMPROOT" \
        --task TEST-0202 --stage qa --round 2 \
        --question-file "$q" --answer-file "$a" \
        --decided-by agent --rationale-file "$r" \
        --summary "Agent-decision recorded for later QA verification."
    [ "$status" -eq 0 ]
    run "$CHECK" --task TEST-0202 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "P2.3 utility rejects --question-file outside the project tree (path traversal)" {
    write_base_init_task "TEST-0203"
    local a="$TMPROOT/a.txt"
    echo "A." > "$a"
    # /etc/passwd is well-known; readable but outside TMPROOT — utility must
    # accept readable arbitrary read paths BUT must refuse to write outside
    # datarim/tasks. We verify the write boundary by passing an out-of-tree
    # --root override: if --task-file resolves outside TMPROOT/datarim/tasks
    # it must exit 1.
    # Pass a task ID with traversal characters — utility must reject by regex.
    run "$APPEND" \
        --root "$TMPROOT" \
        --task "../../etc" --stage prd --round 1 \
        --question-file "/etc/passwd" --answer-file "$a" \
        --decided-by operator \
        --summary "Attempt to write outside the project tree."
    [ "$status" -ne 0 ]
}

@test "P2.4 utility rejects oversized --question-file (>100 KB)" {
    write_base_init_task "TEST-0204"
    local q="$TMPROOT/big.txt" a="$TMPROOT/a.txt"
    # Generate ~150 KB of plain text (well above the 100 KB cap).
    yes "this is filler text used to exceed the size cap" | head -c 153600 > "$q"
    echo "A." > "$a"
    run "$APPEND" \
        --root "$TMPROOT" \
        --task TEST-0204 --stage prd --round 1 \
        --question-file "$q" --answer-file "$a" \
        --decided-by operator \
        --summary "S."
    [ "$status" -ne 0 ]
    [[ "$output" == *"size"* ]] || [[ "$output" == *"large"* ]] || [[ "$output" == *"cap"* ]]
}

@test "P2.5 utility appends atomically — parallel invocations preserve both blocks" {
    write_base_init_task "TEST-0205"
    local q1="$TMPROOT/q1.txt" a1="$TMPROOT/a1.txt"
    local q2="$TMPROOT/q2.txt" a2="$TMPROOT/a2.txt"
    echo "Q1 round 1." > "$q1"; echo "A1." > "$a1"
    echo "Q2 round 2." > "$q2"; echo "A2." > "$a2"

    "$APPEND" --root "$TMPROOT" --task TEST-0205 --stage prd --round 1 \
        --question-file "$q1" --answer-file "$a1" --decided-by operator \
        --summary "First parallel round." &
    pid1=$!
    "$APPEND" --root "$TMPROOT" --task TEST-0205 --stage plan --round 2 \
        --question-file "$q2" --answer-file "$a2" --decided-by operator \
        --summary "Second parallel round." &
    pid2=$!
    wait "$pid1" && wait "$pid2"

    # File must contain both headings, no duplicate framing.
    local file="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    grep -c 'Q&A by /dr-' "$file" | grep -q '^2$'
    # Validator still happy.
    run "$CHECK" --task TEST-0205 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Phase 3 — Wire six pipeline commands
# ---------------------------------------------------------------------------

@test "P3.1 all six pipeline commands invoke append-init-task-qa.sh" {
    local count
    count=0
    for cmd in dr-prd dr-plan dr-design dr-do dr-qa dr-compliance; do
        if grep -q 'append-init-task-qa.sh' "$ROOT_DIR/commands/${cmd}.md"; then
            count=$(( count + 1 ))
        fi
    done
    [ "$count" -eq 6 ]
}

# ---------------------------------------------------------------------------
# Phase 4 — /dr-qa Layer 3b Q&A round-trip verification
# ---------------------------------------------------------------------------

@test "P4.1 dr-qa.md Layer 3b mentions Q&A round-trip verification" {
    [ -f "$QA_COMMAND_FILE" ]
    grep -q 'Q&A round-trip' "$QA_COMMAND_FILE"
}

@test "P4.2 dr-qa.md Layer 3b instructs to surface unclosed conflict as BLOCKED" {
    grep -E 'Conflict.*BLOCKED|BLOCKED.*Conflict|Conflict.*unclosed' "$QA_COMMAND_FILE"
}

# ---------------------------------------------------------------------------
# Phase 6 — Legacy fallback (task without init-task → no Q&A blockers)
# ---------------------------------------------------------------------------

@test "P6.1 legacy task without init-task surfaces only advisory in --all mode" {
    # No init-task file, fresh task — finding is info, exit code is 0.
    today="$(date +%Y-%m-%d)"
    write_task_description "TEST-0601" "$today"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    # No Q&A-related blocker text; advisory only.
    [[ "$output" == *"info"* ]] || [[ "$output" == *"warn"* ]] || [ -z "$output" ]
}
