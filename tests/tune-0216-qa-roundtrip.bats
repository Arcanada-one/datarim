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

@test "P2.1b utility refuses an intermediate composition printf failure without publishing" {
    write_base_init_task "TEST-0218"
    local init_file="$TMPROOT/datarim/tasks/TEST-0218-init-task.md"
    local original="$TMPROOT/TEST-0218-before.md"
    local question="$TMPROOT/TEST-0218-question.txt"
    local answer="$TMPROOT/TEST-0218-answer.txt"
    local receipt="$TMPROOT/TEST-0218-printf-receipt.txt"
    local expected_receipt="$TMPROOT/TEST-0218-expected-receipt.txt"
    local out="$TMPROOT/TEST-0218.stdout" err="$TMPROOT/TEST-0218.stderr"
    local append_abs append_sha_before append_sha_after status=0 temp_count=0 temp
    local question_token='Synthetic TEST-0218 question token.'
    local answer_token='Synthetic TEST-0218 answer token.'
    append_abs="$(cd "$(dirname "$APPEND")" && pwd -P)/$(basename "$APPEND")"
    append_sha_before="$(sha256sum "$append_abs" | awk '{print $1}')"
    cp "$init_file" "$original"
    printf '%s\n' "$question_token" > "$question"
    printf '%s\n' "$answer_token" > "$answer"

    if (
        export P2_1B_HELPER="$append_abs"
        export P2_1B_TOKEN="$question_token"
        export P2_1B_MATCH_COUNT=0
        exec 9>"$receipt"
        printf() {
            if [ "${BASH_SOURCE[1]:-}" = "$P2_1B_HELPER" ] \
               && [ "$#" -eq 2 ] \
               && [ "$1" = '%s\n\n' ] \
               && [ "$2" = "$P2_1B_TOKEN" ]; then
                if [ "$P2_1B_MATCH_COUNT" -eq 0 ]; then
                    P2_1B_MATCH_COUNT=1
                    builtin printf 'MATCH_FIRST\n' >&9
                    return 73
                fi
                builtin printf 'MATCH_REPEAT\n' >&9
                builtin printf "$@"
                return $?
            fi
            builtin printf "$@"
        }
        export -f printf
        exec "$append_abs" --root "$TMPROOT" --task TEST-0218 --stage qa --round 1 \
            --question-file "$question" --answer-file "$answer" \
            --decided-by operator --summary synthetic-intermediate-printf-refusal
    ) > "$out" 2> "$err"; then
        status=0
    else
        status=$?
    fi

    append_sha_after="$(sha256sum "$append_abs" | awk '{print $1}')"
    printf 'MATCH_FIRST\n' > "$expected_receipt"
    for temp in "$TMPROOT/datarim/tasks"/.TEST-0218.qa.append.*; do
        [ -e "$temp" ] && temp_count=$((temp_count + 1))
    done

    [ "$status" -eq 1 ] \
        && [ ! -s "$out" ] \
        && [ "$(cat "$err")" = 'ERROR: failed to compose Q&A append' ] \
        && [ "$append_sha_before" = "$append_sha_after" ] \
        && cmp -s "$expected_receipt" "$receipt" \
        && cmp -s "$original" "$init_file" \
        && ! grep -Fq -- "$question_token" "$init_file" \
        && ! grep -Fq -- "$answer_token" "$init_file" \
        && [ "$temp_count" -eq 0 ] \
        && [ ! -e "$TMPROOT/datarim/tasks/.TEST-0218.qa-lock" ]
}

@test "P2.1c utility refuses composition temp redirection failure without publishing" {
    [ "$(id -u)" -ne 0 ] || skip "read-only file mode is bypassed by root"
    write_base_init_task "TEST-0219"
    local init_file="$TMPROOT/datarim/tasks/TEST-0219-init-task.md"
    local tasks_dir="$TMPROOT/datarim/tasks"
    local original="$TMPROOT/TEST-0219-before.md"
    local question="$TMPROOT/TEST-0219-question.txt"
    local answer="$TMPROOT/TEST-0219-answer.txt"
    local shim_dir="$TMPROOT/TEST-0219-mktemp-shim"
    local receipt="$TMPROOT/TEST-0219-mktemp-receipt.txt"
    local expected_receipt="$TMPROOT/TEST-0219-expected-receipt.txt"
    local out="$TMPROOT/TEST-0219.stdout" err="$TMPROOT/TEST-0219.stderr"
    local append_abs append_sha_before append_sha_after expected_prefix expected_template
    local real_mktemp status=0 temp_count=0 temp probe
    append_abs="$(cd "$(dirname "$APPEND")" && pwd -P)/$(basename "$APPEND")"
    append_sha_before="$(sha256sum "$append_abs" | awk '{print $1}')"
    real_mktemp="$(command -v mktemp)"
    expected_prefix="$(cd "$tasks_dir" && pwd -P)/.TEST-0219.qa.append."
    expected_template="${expected_prefix}XXXXXX"

    probe="$("$real_mktemp" "$tasks_dir/.TEST-0219-open-probe.XXXXXX")"
    chmod 0400 "$probe" || { rm -f "$probe"; skip "fixture cannot set mode 0400"; }
    if ( : > "$probe" ) 2>/dev/null; then
        rm -f "$probe"
        skip "fixture permits opening mode-0400 files for writing"
    fi
    rm -f "$probe"
    cp "$init_file" "$original"
    printf '%s\n' 'Synthetic TEST-0219 question token.' > "$question"
    printf '%s\n' 'Synthetic TEST-0219 answer token.' > "$answer"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/mktemp" <<'SHIM'
#!/usr/bin/env bash
set -u
if [ "$#" -eq 1 ] && [ "$1" = "${P2_1C_EXPECTED_TEMPLATE:?}" ]; then
    tmp="$("${P2_1C_REAL_MKTEMP:?}" "$@")" || exit $?
    case "$tmp" in
        "${P2_1C_EXPECTED_PREFIX:?}"*) path_ok=1 ;;
        *) path_ok=0 ;;
    esac
    if [ -f "$tmp" ]; then regular=1; else regular=0; fi
    if [ "$path_ok" -eq 1 ] && [ "$regular" -eq 1 ] && chmod 0400 "$tmp"; then
        chmod_rc=0
    else
        chmod_rc=1
    fi
    if ( : > "$tmp" ) 2>/dev/null; then write_blocked=0; else write_blocked=1; fi
    if [ "$path_ok" -ne 1 ] || [ "$regular" -ne 1 ] \
       || [ "$chmod_rc" -ne 0 ] || [ "$write_blocked" -ne 1 ]; then
        exit 75
    fi
    {
        builtin printf 'MATCH_EXACT_TEMPLATE\n'
        builtin printf 'CHMOD_RC_0\n'
        builtin printf 'WRITE_BLOCKED_1\n'
    } > "${P2_1C_RECEIPT:?}"
    builtin printf '%s\n' "$tmp"
    exit 0
fi
exec "${P2_1C_REAL_MKTEMP:?}" "$@"
SHIM
    chmod +x "$shim_dir/mktemp"

    if env PATH="$shim_dir:$PATH" \
        P2_1C_EXPECTED_TEMPLATE="$expected_template" \
        P2_1C_EXPECTED_PREFIX="$expected_prefix" \
        P2_1C_REAL_MKTEMP="$real_mktemp" P2_1C_RECEIPT="$receipt" \
        "$append_abs" --root "$TMPROOT" --task TEST-0219 --stage qa --round 1 \
        --question-file "$question" --answer-file "$answer" \
        --decided-by operator --summary synthetic-compose-open-refusal \
        > "$out" 2> "$err"; then
        status=0
    else
        status=$?
    fi

    append_sha_after="$(sha256sum "$append_abs" | awk '{print $1}')"
    printf 'MATCH_EXACT_TEMPLATE\nCHMOD_RC_0\nWRITE_BLOCKED_1\n' > "$expected_receipt"
    for temp in "$tasks_dir"/.TEST-0219.qa.append.*; do
        [ -e "$temp" ] && temp_count=$((temp_count + 1))
    done
    [ "$status" -eq 1 ] \
        && [ ! -s "$out" ] \
        && grep -Fq 'Permission denied' "$err" \
        && grep -Fxq 'ERROR: failed to compose Q&A append' "$err" \
        && [ "$append_sha_before" = "$append_sha_after" ] \
        && cmp -s "$expected_receipt" "$receipt" \
        && cmp -s "$original" "$init_file" \
        && ! grep -Fq -- 'Synthetic TEST-0219 question token.' "$init_file" \
        && ! grep -Fq -- 'Synthetic TEST-0219 answer token.' "$init_file" \
        && [ "$temp_count" -eq 0 ] \
        && [ ! -e "$tasks_dir/.TEST-0219.qa-lock" ]
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
    heading_count="$(grep -c 'Q&A by /dr-' "$file" || true)"
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
