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
# Source-of-truth contracts: skills/init-task-persistence/SKILL.md § Q&A round-trip,
# plans/TUNE-0216-plan.md.

ROOT_DIR="$BATS_TEST_DIRNAME/.."
CHECK="$ROOT_DIR/dev-tools/check-init-task-presence.sh"
APPEND="$ROOT_DIR/dev-tools/append-init-task-qa.sh"
SKILL_FILE="$ROOT_DIR/skills/init-task-persistence/SKILL.md"
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

# Count one fixed P2.5 marker without exposing the fixture path or contents.
# "unknown" distinguishes an unavailable/read-error input from a measured zero.
_p25_marker_count() {
    local file="$1" marker="$2" result count grep_status
    if [ ! -r "$file" ]; then
        printf 'unknown'
        return 0
    fi
    result="$( { grep -F -o -- "$marker" < "$file" 2>/dev/null | wc -l; printf ':%s' "${PIPESTATUS[0]}"; } 2>/dev/null )"
    count="$(printf '%s' "${result%%:*}" | tr -d '[:space:]')"
    grep_status="${result##*:}"
    case "$grep_status" in
        0|1)
            case "$count" in
                ''|*[!0-9]*) printf 'unknown' ;;
                *) if [ "${#count}" -gt 20 ]; then printf 'overflow'; else printf '%s' "$count"; fi ;;
            esac
            ;;
        *) printf 'unknown' ;;
    esac
}

_p25_marker_presence() {
    case "$1" in
        unknown) printf 'unknown' ;;
        overflow) printf 'yes' ;;
        *[1-9]*) printf 'yes' ;;
        *) printf 'no' ;;
    esac
}

_p25_safe_marker_count() {
    case "$1" in
        unknown|overflow) printf '%s' "$1" ;;
        ''|*[!0-9]*) printf 'unknown' ;;
        *) if [ "${#1}" -gt 20 ]; then printf 'overflow'; else printf '%s' "$1"; fi ;;
    esac
}

# Emit only fixed field names and bounded numeric/unknown values on Bats FD 3.
# Counts over 20 digits become "overflow"; the complete block stays below 512 bytes.
# Best-effort writes never affect the caller's assertion status.
_p25_emit_marker_summary() {
    local count1 count2 count3 count4 count5 count6
    count1="$(_p25_safe_marker_count "${1:-}")"
    count2="$(_p25_safe_marker_count "${2:-}")"
    count3="$(_p25_safe_marker_count "${3:-}")"
    count4="$(_p25_safe_marker_count "${4:-}")"
    count5="$(_p25_safe_marker_count "${5:-}")"
    count6="$(_p25_safe_marker_count "${6:-}")"
    {
        printf 'P2.5 marker summary v1\n' >&3 || :
        printf 'prd_round_1_heading count=%s present=%s\n' "$count1" "$(_p25_marker_presence "$count1")" >&3 || :
        printf 'plan_round_2_heading count=%s present=%s\n' "$count2" "$(_p25_marker_presence "$count2")" >&3 || :
        printf 'question_round_1 count=%s present=%s\n' "$count3" "$(_p25_marker_presence "$count3")" >&3 || :
        printf 'question_round_2 count=%s present=%s\n' "$count4" "$(_p25_marker_presence "$count4")" >&3 || :
        printf 'answer_round_1 count=%s present=%s\n' "$count5" "$(_p25_marker_presence "$count5")" >&3 || :
        printf 'answer_round_2 count=%s present=%s\n' "$count6" "$(_p25_marker_presence "$count6")" >&3 || :
    } 2>/dev/null
    return 0
}

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
        echo "operator: test-operator"
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

@test "P2.0c utility reports usage error when any option value is missing" {
    local option
    for option in \
        --root --task --stage --round \
        --question-file --answer-file --decided-by --rationale-file \
        --summary --asked-by --conflict-with --conflict-detail-file \
        --timestamp; do
        run "$APPEND" "$option"
        if [ "$status" -ne 2 ]; then
            echo "$option without a value returned $status, expected 2" >&2
            return 1
        fi
    done
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

@test "P2.1b utility reports final replace failure and cleans temp and lock" {
    write_base_init_task "TEST-0205"
    local init_file="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    local original="$TMPROOT/original.before"
    local question="$TMPROOT/refusal-question.txt"
    local answer="$TMPROOT/refusal-answer.txt"
    local shim_dir="$TMPROOT/mv-shim"
    local target="$init_file"
    local receipt="$TMPROOT/mv-receipt.txt"
    local out="$TMPROOT/refusal.stdout" err="$TMPROOT/refusal.stderr"
    local real_mv status temp_count=0 temp
    real_mv="$(command -v mv)"
    cp "$init_file" "$original"
    printf 'Synthetic refusal question.\n' > "$question"
    printf 'Synthetic refusal answer.\n' > "$answer"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/mv" <<'SHIM'
#!/usr/bin/env bash
set -u
if [ "$#" -eq 3 ] \
   && [ "$1" = "-f" ] \
   && [ "$3" = "$CONTROL_EXPECTED_TARGET" ] \
   && [[ "$2" == "$CONTROL_EXPECTED_PREFIX"* ]] \
   && [ -f "$2" ]; then
    printf 'match=exact_final_replace\nsource_regular=1\ntarget_present_before=1\nforced_rc=73\n' \
        > "$CONTROL_RECEIPT"
    exit 73
fi
exec "$CONTROL_REAL_MV" "$@"
SHIM
    chmod +x "$shim_dir/mv"

    if env PATH="$shim_dir:$PATH" \
        CONTROL_EXPECTED_TARGET="$target" \
        CONTROL_EXPECTED_PREFIX="$TMPROOT/datarim/tasks/.TEST-0205.qa.append." \
        CONTROL_RECEIPT="$receipt" CONTROL_REAL_MV="$real_mv" \
        "$APPEND" --root "$TMPROOT" --task TEST-0205 --stage qa --round 1 \
        --question-file "$question" --answer-file "$answer" \
        --decided-by operator --summary synthetic-mv-refusal-control \
        > "$out" 2> "$err"; then
        status=0
    else
        status=$?
    fi

    for temp in "$TMPROOT/datarim/tasks"/.TEST-0205.qa.append.*; do
        [ -e "$temp" ] && temp_count=$((temp_count + 1))
    done
    [ "$status" -eq 1 ] \
        && [ ! -s "$out" ] \
        && grep -Fxq 'ERROR: failed to publish Q&A append' "$err" \
        && cmp -s "$original" "$init_file" \
        && grep -Fxq 'match=exact_final_replace' "$receipt" \
        && grep -Fxq 'source_regular=1' "$receipt" \
        && grep -Fxq 'target_present_before=1' "$receipt" \
        && grep -Fxq 'forced_rc=73' "$receipt" \
        && [ "$temp_count" -eq 0 ] \
        && [ ! -e "$TMPROOT/datarim/tasks/.TEST-0205.qa-lock" ]
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
    local out1="$TMPROOT/child-1.stdout" out2="$TMPROOT/child-2.stdout"
    local err1="$TMPROOT/child-1.stderr" err2="$TMPROOT/child-2.stderr"
    local pid1 pid2 status1 status2 child stdout_file stderr_file stream stream_file
    echo "Q1 round 1." > "$q1"; echo "A1." > "$a1"
    echo "Q2 round 2." > "$q2"; echo "A2." > "$a2"

    "$APPEND" --root "$TMPROOT" --task TEST-0205 --stage prd --round 1 \
        --question-file "$q1" --answer-file "$a1" --decided-by operator \
        --summary "First parallel round." > "$out1" 2> "$err1" &
    pid1=$!
    "$APPEND" --root "$TMPROOT" --task TEST-0205 --stage plan --round 2 \
        --question-file "$q2" --answer-file "$a2" --decided-by operator \
        --summary "Second parallel round." > "$out2" 2> "$err2" &
    pid2=$!
    if wait "$pid1"; then status1=0; else status1=$?; fi
    if wait "$pid2"; then status2=0; else status2=$?; fi

    local file="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    local heading_count failed=0 marker validator_status
    local prd_round_1_count plan_round_2_count question_round_1_count question_round_2_count answer_round_1_count answer_round_2_count
    heading_count="$(grep -c 'Q&A by /dr-' "$file" || true)"
    # Capture every fixed marker before any assertion can stop this test.
    prd_round_1_count="$(_p25_marker_count "$file" 'Q&A by /dr-prd (round 1)')"
    plan_round_2_count="$(_p25_marker_count "$file" 'Q&A by /dr-plan (round 2)')"
    question_round_1_count="$(_p25_marker_count "$file" 'Q1 round 1.')"
    question_round_2_count="$(_p25_marker_count "$file" 'Q2 round 2.')"
    answer_round_1_count="$(_p25_marker_count "$file" 'A1.')"
    answer_round_2_count="$(_p25_marker_count "$file" 'A2.')"
    [ "$status1" -eq 0 ] || failed=1
    [ "$status2" -eq 0 ] || failed=1
    [ "$heading_count" = 2 ] || failed=1
    for marker in \
        'Q&A by /dr-prd (round 1)' 'Q&A by /dr-plan (round 2)' \
        'Q1 round 1.' 'Q2 round 2.' 'A1.' 'A2.'; do
        grep -Fq -- "$marker" "$file" || failed=1
    done

    # Validator still runs even when the content checks fail.
    run "$CHECK" --task TEST-0205 --root "$TMPROOT"
    local validator_status="$status"
    [ "$validator_status" -eq 0 ] || failed=1

    if [ "$failed" -ne 0 ]; then
        _p25_emit_marker_summary \
            "$prd_round_1_count" "$plan_round_2_count" \
            "$question_round_1_count" "$question_round_2_count" \
            "$answer_round_1_count" "$answer_round_2_count" || true
        printf 'P2.5 child exits: %s, %s; headings: %s; validator exit: %s\n' \
            "$status1" "$status2" "$heading_count" "$validator_status"
        for child in 1 2; do
            if [ "$child" -eq 1 ]; then stdout_file="$out1"; stderr_file="$err1"; else stdout_file="$out2"; stderr_file="$err2"; fi
            for stream in stdout stderr; do
                if [ "$stream" = stdout ]; then stream_file="$stdout_file"; else stream_file="$stderr_file"; fi
                printf 'child %s %s (first 1024 bytes):\n' "$child" "$stream"
                head -c 1024 "$stream_file" || true
                printf '\n'
            done
        done
        return 1
    fi
}

@test "P2.5 failure diagnostics report all markers when the first is missing" {
    local file="$TMPROOT/synthetic-marker-fixture.txt"
    local summary="$TMPROOT/marker-summary.txt"
    cat > "$file" <<'EOF'
Q&A by /dr-plan (round 2)
Q1 round 1.
Q2 round 2.
A1.
A2.
synthetic-raw-content-sentinel
EOF

    local prd_round_1_count plan_round_2_count question_round_1_count question_round_2_count answer_round_1_count answer_round_2_count
    prd_round_1_count="$( _p25_marker_count "$file" 'Q&A by /dr-prd (round 1)' )"
    plan_round_2_count="$( _p25_marker_count "$file" 'Q&A by /dr-plan (round 2)' )"
    question_round_1_count="$( _p25_marker_count "$file" 'Q1 round 1.' )"
    question_round_2_count="$( _p25_marker_count "$file" 'Q2 round 2.' )"
    answer_round_1_count="$( _p25_marker_count "$file" 'A1.' )"
    answer_round_2_count="$( _p25_marker_count "$file" 'A2.' )"

    # Model the original first marker predicate failing before later checks.
    local predicate_failed=0
    case "$prd_round_1_count" in
        0|unknown) predicate_failed=1 ;;
    esac
    if [ "$predicate_failed" -ne 0 ]; then
        _p25_emit_marker_summary \
            "$prd_round_1_count" "$plan_round_2_count" \
            "$question_round_1_count" "$question_round_2_count" \
            "$answer_round_1_count" "$answer_round_2_count" 3>"$summary" || true
    fi

    # A closed diagnostic sink is best-effort and cannot clear the failed predicate.
    local sink_status=0
    _p25_emit_marker_summary \
        "$prd_round_1_count" "$plan_round_2_count" \
        "$question_round_1_count" "$question_round_2_count" \
        "$answer_round_1_count" "$answer_round_2_count" 3>&- 2>/dev/null || sink_status=$?

    [ "$predicate_failed" -eq 1 ] \
        && [ "$sink_status" -eq 0 ] \
        && grep -Fxq 'P2.5 marker summary v1' "$summary" \
        && grep -Fxq 'prd_round_1_heading count=0 present=no' "$summary" \
        && grep -Fxq 'plan_round_2_heading count=1 present=yes' "$summary" \
        && grep -Fxq 'question_round_1 count=1 present=yes' "$summary" \
        && grep -Fxq 'question_round_2 count=1 present=yes' "$summary" \
        && grep -Fxq 'answer_round_1 count=1 present=yes' "$summary" \
        && grep -Fxq 'answer_round_2 count=1 present=yes' "$summary" \
        && [ "$(wc -c < "$summary" | tr -d '[:space:]')" -le 512 ] \
        && ! grep -qF -- "$TMPROOT" "$summary" \
        && ! grep -qF 'synthetic-raw-content-sentinel' "$summary"
}

@test "P2.6 utility preserves init-task when its source read fails" {
    write_base_init_task "TEST-0206"
    local tasks_dir="$TMPROOT/datarim/tasks"
    local init_file="$tasks_dir/TEST-0206-init-task.md"
    local original="$TMPROOT/TEST-0206-init-task.original.md"
    local q="$TMPROOT/q.txt" a="$TMPROOT/a.txt"
    local fake_bin="$TMPROOT/fake-bin"
    cp "$init_file" "$original"
    echo "Q whose append must fail." > "$q"
    echo "A whose append must fail." > "$a"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/cat" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -eq 1 ] && [ "$1" = "${CAT_FAIL_PATH:?}" ]; then
    echo "simulated init-task read failure" >&2
    exit 74
fi
exec /bin/cat "$@"
EOF
    chmod +x "$fake_bin/cat"

    run env \
        PATH="$fake_bin:$PATH" \
        CAT_FAIL_PATH="$init_file" \
        "$APPEND" \
        --root "$TMPROOT" \
        --task TEST-0206 --stage do --round 1 \
        --question-file "$q" --answer-file "$a" \
        --decided-by operator \
        --summary "This append must not replace an unreadable source."

    [ "$status" -ne 0 ] \
        && [[ "$output" == *"simulated init-task read failure"* ]] \
        && [[ "$output" == *"failed to read init-task file"* ]] \
        && cmp -s "$original" "$init_file" \
        && [ ! -d "$tasks_dir/.TEST-0206.qa-lock" ] \
        && [ -z "$(find "$tasks_dir" -maxdepth 1 -name '.TEST-0206.qa.append.*' -print)" ]
}

@test "P2.7 cleanup removes the lock after temp cleanup itself fails" {
    write_base_init_task "TEST-0207"
    local tasks_dir="$TMPROOT/datarim/tasks"
    local init_file="$tasks_dir/TEST-0207-init-task.md"
    local original="$TMPROOT/TEST-0207-init-task.original.md"
    local q="$TMPROOT/q.txt" a="$TMPROOT/a.txt"
    local fake_bin="$TMPROOT/fake-bin"
    local rm_log="$TMPROOT/rm-calls.log" rmdir_log="$TMPROOT/rmdir-calls.log"
    cp "$init_file" "$original"
    echo "Q whose append must fail." > "$q"
    echo "A whose append must fail." > "$a"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/cat" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -eq 1 ] && [ "$1" = "${CAT_FAIL_PATH:?}" ]; then
    echo "simulated init-task read failure" >&2
    exit 74
fi
exec /bin/cat "$@"
EOF
    cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${RM_CALL_LOG:?}"
if [ "$#" -eq 2 ] && [ "$1" = "-f" ] && [[ "$2" == "${RM_FAIL_PREFIX:?}"* ]]; then
    echo "simulated temp cleanup failure" >&2
    exit 75
fi
exec /bin/rm "$@"
EOF
    cat > "$fake_bin/rmdir" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${RMDIR_CALL_LOG:?}"
exec /bin/rmdir "$@"
EOF
    chmod +x "$fake_bin/cat" "$fake_bin/rm" "$fake_bin/rmdir"

    run env \
        PATH="$fake_bin:$PATH" \
        CAT_FAIL_PATH="$init_file" \
        RM_CALL_LOG="$rm_log" \
        RM_FAIL_PREFIX="$tasks_dir/.TEST-0207.qa.append." \
        RMDIR_CALL_LOG="$rmdir_log" \
        "$APPEND" \
        --root "$TMPROOT" \
        --task TEST-0207 --stage do --round 1 \
        --question-file "$q" --answer-file "$a" \
        --decided-by operator \
        --summary "Cleanup must continue after a failed temp removal."

    [ "$status" -ne 0 ] \
        && [[ "$output" == *"simulated init-task read failure"* ]] \
        && [[ "$output" == *"simulated temp cleanup failure"* ]] \
        && grep -qF "$tasks_dir/.TEST-0207.qa.append." "$rm_log" \
        && grep -qF "$tasks_dir/.TEST-0207.qa-lock" "$rmdir_log" \
        && cmp -s "$original" "$init_file" \
        && [ ! -d "$tasks_dir/.TEST-0207.qa-lock" ]
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
