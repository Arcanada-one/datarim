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

# p25_failure_fixture_metrics <fixture>
# Returns tab-separated metadata; snapshot bytes are hex-escaped and bounded.
p25_failure_fixture_metrics() {
    local fixture="$1" fixture_bytes='unavailable' fixture_sha='unavailable'
    local snapshot_hex='unavailable' snapshot_bytes='unavailable' snapshot_truncated='unavailable'
    local hash_output snapshot_raw

    if [[ "$fixture" == "$TMPROOT"/datarim/tasks/TEST-0205-init-task.md ]] \
        && [ -f "$fixture" ] && [ ! -L "$fixture" ]; then
        if fixture_bytes="$(wc -c < "$fixture" 2>/dev/null)"; then
            fixture_bytes="${fixture_bytes//[[:space:]]/}"
        else
            fixture_bytes='unavailable: byte count failed'
        fi
        if hash_output="$(sha256sum < "$fixture" 2>/dev/null)" \
            && [[ "${hash_output%%[[:space:]]*}" =~ ^[0-9a-f]{64}$ ]]; then
            fixture_sha="${hash_output%%[[:space:]]*}"
        else
            fixture_sha='unavailable: sha256sum failed'
        fi
        if snapshot_raw="$(od -An -v -tx1 -N 2048 < "$fixture" 2>/dev/null)" \
            && [[ "$snapshot_raw" =~ ^[[:space:]0-9a-fA-F]*$ ]] \
            && snapshot_hex="$(printf '%s' "$snapshot_raw" | tr -d '[:space:]')"; then
            snapshot_bytes="$(( ${#snapshot_hex} / 2 ))"
            if [[ "$fixture_bytes" =~ ^[0-9]+$ ]]; then
                if [ "$fixture_bytes" -gt 2048 ]; then
                    snapshot_truncated='yes'
                else
                    snapshot_truncated='no'
                fi
            else
                snapshot_truncated='unavailable'
            fi
        else
            snapshot_hex='unavailable: hex snapshot failed'
        fi
    else
        fixture_bytes='unavailable: fixture unavailable'
        fixture_sha='unavailable: fixture unavailable'
    fi
    printf '%s|%s|%s|%s|%s\n' \
        "$fixture_bytes" "$fixture_sha" "$snapshot_hex" "$snapshot_bytes" "$snapshot_truncated"
}

# p25_fixture_marker_outcome <fixture> <fixed-marker>
p25_fixture_marker_outcome() {
    local fixture="$1" marker="$2" grep_status
    if [[ "$fixture" != "$TMPROOT"/datarim/tasks/TEST-0205-init-task.md ]] \
        || [ ! -f "$fixture" ] || [ -L "$fixture" ]; then
        printf 'unavailable'
    elif grep -Fq -- "$marker" "$fixture" 2>/dev/null; then
        printf 'present'
    else
        grep_status=$?
        if [ "$grep_status" -eq 1 ]; then printf 'absent'; else printf 'unavailable'; fi
    fi
}

# p25_child_stream_metrics <fixed-stream-name>
# Reads only one of the four fixed child stream names under TMPROOT.
# Returns availability|bytes|sha256|prefix_hex|prefix_truncated without raw data.
p25_child_stream_metrics() {
    local LC_ALL=C name="$1" path="$TMPROOT/$1"
    local availability='unavailable' bytes='NOT_MEASURED' sha='NOT_MEASURED'
    local prefix='NOT_MEASURED' truncated='NOT_MEASURED' sha_output hex_output
    local measured_bytes measured_sha measured_hex

    case "$name" in
        child-1.stdout|child-1.stderr|child-2.stdout|child-2.stderr) ;;
        *) printf 'unavailable|NOT_MEASURED|NOT_MEASURED|NOT_MEASURED|NOT_MEASURED\n'; return 0 ;;
    esac

    if [[ ! -d "$TMPROOT" || -L "$TMPROOT" ]]; then
        availability='unavailable:fixture_root'
    elif [ -L "$path" ]; then
        availability='unavailable:symlink'
    elif [ ! -e "$path" ]; then
        availability='unavailable:missing'
    elif [ ! -f "$path" ]; then
        availability='unavailable:not_regular'
    elif [ ! -r "$path" ]; then
        availability='unavailable:unreadable'
    elif ! measured_bytes="$(wc -c < "$path" 2>/dev/null)" \
        || ! [[ "${measured_bytes//[[:space:]]/}" =~ ^[0-9]+$ ]]; then
        availability='unavailable:byte_count'
    elif ! sha_output="$(sha256sum < "$path" 2>/dev/null)" \
        || ! [[ "${sha_output%%[[:space:]]*}" =~ ^[0-9a-f]{64}$ ]]; then
        availability='unavailable:digest'
    elif ! measured_hex="$(od -An -v -tx1 -N64 < "$path" 2>/dev/null)" \
        || ! [[ "$measured_hex" =~ ^[[:space:]0-9a-fA-F]*$ ]]; then
        availability='unavailable:prefix'
    else
        availability='available'
        bytes="${measured_bytes//[[:space:]]/}"
        sha="${sha_output%%[[:space:]]*}"
        prefix="$(printf '%s' "$measured_hex" | tr -d '[:space:]')"
        if (( bytes > 64 )); then truncated='yes'; else truncated='no'; fi
    fi

    printf '%s|%s|%s|%s|%s\n' "$availability" "$bytes" "$sha" "$prefix" "$truncated"
}

# p25_child_diagnostic_lines <child-1-exit> <child-2-exit> <child-1-pid> <child-2-pid>
# PID arguments are the parent-observed values captured from $! by P2.5.
p25_child_diagnostic_lines() {
    local child1_exit="$1" child2_exit="$2" child1_pid="$3" child2_pid="$4"
    local output='' child pid name metrics
    local availability bytes sha prefix truncated
    local child_index stream_index
    local -a stream_names=('child-1.stdout' 'child-1.stderr' 'child-2.stdout' 'child-2.stderr')
    local -a pid_values=("$child1_pid" "$child2_pid")

    for child_index in 1 2; do
        child="${pid_values[$((child_index - 1))]}"
        if [[ "$child" =~ ^[0-9]+$ ]]; then
            output+="child_${child_index}_pid=$child"
        else
            output+="child_${child_index}_pid=NOT_MEASURED"
        fi
        if [ "$child_index" -eq 1 ]; then
            output+=" child_${child_index}_exit=$child1_exit"
        else
            output+=" child_${child_index}_exit=$child2_exit"
        fi
        output+=$'\n'
    done

    for stream_index in 0 1 2 3; do
        name="${stream_names[$stream_index]}"
        metrics="$(p25_child_stream_metrics "$name")"
        IFS='|' read -r availability bytes sha prefix truncated <<< "$metrics"
        child="${name%%.*}"
        child="${child//-/_}"
        name="${name#*.}"
        output+="${child}_${name}_availability=$availability ${child}_${name}_bytes=$bytes ${child}_${name}_sha256=$sha ${child}_${name}_prefix_hex=$prefix ${child}_${name}_prefix_truncated=$truncated"$'\n'
    done
    printf '%s' "$output"
}

# p25_measure_test_inputs <fixture>
# Records byte identity only for this synthetic fixture and the exact test source.
p25_measure_test_inputs() {
    local fixture="$1" path name bytes sha_output sha state
    local source="$ROOT_DIR/tests/tune-0216-qa-roundtrip.bats"
    local -a paths=("$source" "$fixture" "$TMPROOT/child-1.stdout" "$TMPROOT/child-1.stderr" "$TMPROOT/child-2.stdout" "$TMPROOT/child-2.stderr")
    for path in "${paths[@]}"; do
        name="${path##*/}"
        if [ -L "$path" ]; then
            state='unavailable:symlink'
        elif [ ! -e "$path" ]; then
            state='unavailable:missing'
        elif [ ! -f "$path" ]; then
            state='unavailable:not_regular'
        elif [ ! -r "$path" ]; then
            state='unavailable:unreadable'
        elif ! bytes="$(wc -c < "$path" 2>/dev/null)" \
            || ! [[ "${bytes//[[:space:]]/}" =~ ^[0-9]+$ ]] \
            || ! sha_output="$(sha256sum < "$path" 2>/dev/null)" \
            || ! [[ "${sha_output%%[[:space:]]*}" =~ ^[0-9a-f]{64}$ ]]; then
            state='unavailable:measurement'
        else
            sha="${sha_output%%[[:space:]]*}"
            state="available:${bytes//[[:space:]]/}:$sha"
        fi
        printf '%s=%s\n' "$name" "$state"
    done
}

# p25_record_diagnostic_case <fixed-case-name> <status> <output> <before> <after>
# Runs only when a private evidence directory is explicitly supplied.
p25_record_diagnostic_case() {
    local case_name="$1" result_status="$2" result_output="$3" before="$4" after="$5"
    local evidence_dir="${P25_EVIDENCE_DIR:-}" raw_path result_path output_sha changed
    [ -n "$evidence_dir" ] || return 0
    case "$evidence_dir" in /*) ;; *) return 1 ;; esac
    case "$evidence_dir" in "$ROOT_DIR"/*) return 1 ;; esac
    [ -d "$evidence_dir" ] && [ ! -L "$evidence_dir" ] || return 1
    [[ "$case_name" =~ ^child-diagnostic-[1-4]$ ]] || return 1
    raw_path="$evidence_dir/$case_name.stdout.raw"
    result_path="$evidence_dir/$case_name.primary.json"
    printf '%s\n' "$result_output" > "$raw_path" || return 1
    chmod 600 "$raw_path" || return 1
    output_sha="$(sha256sum < "$raw_path")" || return 1
    output_sha="${output_sha%%[[:space:]]*}"
    if [ "$before" = "$after" ]; then changed=true; else changed=false; fi
    {
        printf '{\n  "case": "%s",\n  "exit": %s,\n  "diagnostic_sha256": "%s",\n  "inputs_unchanged": %s,\n' \
            "$case_name" "$result_status" "$output_sha" "$changed"
        printf '  "inputs_before": "%s",\n  "inputs_after": "%s"\n}\n' \
            "${before//$'\n'/; }" "${after//$'\n'/; }"
    } > "$result_path" || return 1
    chmod 600 "$result_path" || return 1
}

# p25_failure_diagnostic <fixture> <child-1-exit> <child-2-exit> <heading-count> <validator-exit> [<child-1-pid> <child-2-pid>]
# Emits bounded failure-only evidence; the caller uses it only on assertion failure.
p25_failure_diagnostic() {
    local LC_ALL=C fixture="$1" child1="$2" child2="$3" heading_count="$4" validator_status="$5"
    local child1_pid="${6:-}" child2_pid="${7:-}"
    local diagnostic='' metrics fixture_bytes fixture_sha snapshot_hex snapshot_bytes snapshot_truncated
    local heading marker index result
    local -a headings markers
    headings=('Q&A by /dr-prd (round 1)' 'Q&A by /dr-plan (round 2)')
    markers=('Q&A by /dr-prd (round 1)' 'Q&A by /dr-plan (round 2)' 'Q1 round 1.' 'Q2 round 2.' 'A1.' 'A2.')

    case "$fixture" in
        "$TMPROOT"/datarim/tasks/TEST-0205-init-task.md) ;;
        *) fixture='' ;;
    esac
    metrics="$(p25_failure_fixture_metrics "$fixture")"
    IFS='|' read -r fixture_bytes fixture_sha snapshot_hex snapshot_bytes snapshot_truncated <<< "$metrics"
    diagnostic+=$'P2.5 failure diagnostic (synthetic fixture only)\n'
    diagnostic+="child_1_exit=$child1 child_2_exit=$child2 validator_exit=$validator_status heading_count=$heading_count"$'\n'
    diagnostic+="$(p25_child_diagnostic_lines "$child1" "$child2" "$child1_pid" "$child2_pid")"$'\n'
    diagnostic+="fixture_bytes=$fixture_bytes fixture_sha256=$fixture_sha"$'\n'
    for index in 0 1; do
        heading="${headings[$index]}"
        result="$(p25_fixture_marker_outcome "$fixture" "$heading")"
        diagnostic+="heading_$((index + 1))=\"$heading\":$result"$'\n'
    done
    for index in 0 1 2 3 4 5; do
        marker="${markers[$index]}"
        result="$(p25_fixture_marker_outcome "$fixture" "$marker")"
        diagnostic+="marker_$((index + 1))=\"$marker\":$result"$'\n'
    done
    diagnostic+="fixture_snapshot_encoding=hex fixture_snapshot_source_bytes=$snapshot_bytes fixture_snapshot_truncated=$snapshot_truncated"$'\n'
    diagnostic+="fixture_snapshot_hex_prefix=$snapshot_hex"$'\n'
    diagnostic+="diagnostic_output_cap_bytes=4096"$'\n'

    local footer_no=$'diagnostic_output_truncated=no\n' footer_yes=$'diagnostic_output_truncated=yes\n'
    if (( ${#diagnostic} + ${#footer_no} <= 4096 )); then
        printf '%s%s' "$diagnostic" "$footer_no"
    else
        printf '%s%s' "${diagnostic:0:$((4096 - ${#footer_yes}))}" "$footer_yes"
    fi
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
    local pid1 pid2 status1 status2
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
    heading_count="$(grep -c 'Q&A by /dr-' "$file" 2>/dev/null || true)"
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
        p25_failure_diagnostic "$file" "$status1" "$status2" "$heading_count" "$validator_status" "$pid1" "$pid2"
        return 1
    fi
}

@test "P2.5 failure diagnostic identifies headings, fixed markers, fixture digest and escaped snapshot" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    mkdir -p "${fixture%/*}"
    printf '%s\n' \
        'Q&A by /dr-prd (round 1)' \
        'Q1 round 1.' \
        'A1.' \
        'SAFE' \
        'synthetic-value-must-not-appear-as-raw-text' > "$fixture"
    local expected_bytes expected_sha
    expected_bytes="$(wc -c < "$fixture")"
    expected_bytes="${expected_bytes//[[:space:]]/}"
    expected_sha="$(sha256sum < "$fixture")"
    expected_sha="${expected_sha%%[[:space:]]*}"

    run p25_failure_diagnostic "$fixture" 0 0 1 0
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'heading_1="Q&A by /dr-prd (round 1)":present'* ]] \
        && [[ "$output" == *'heading_2="Q&A by /dr-plan (round 2)":absent'* ]] \
        && [[ "$output" == *'marker_1="Q&A by /dr-prd (round 1)":present'* ]] \
        && [[ "$output" == *'marker_2="Q&A by /dr-plan (round 2)":absent'* ]] \
        && [[ "$output" == *'marker_3="Q1 round 1.":present'* ]] \
        && [[ "$output" == *'marker_4="Q2 round 2.":absent'* ]] \
        && [[ "$output" == *'marker_5="A1.":present'* ]] \
        && [[ "$output" == *'marker_6="A2.":absent'* ]] \
        && [[ "$output" == *"fixture_bytes=$expected_bytes fixture_sha256=$expected_sha"* ]] \
        && [[ "$output" == *'fixture_snapshot_encoding=hex'* ]] \
        && [[ "$output" == *'53414645'* ]] \
        && [[ "$output" == *'diagnostic_output_truncated=no'* ]] \
        && [[ "$output" != *"$fixture"* ]] \
        && [[ "$output" != *'synthetic-value-must-not-appear-as-raw-text'* ]]
}

@test "P2.5 failure diagnostic enforces the total 4096-byte cap with truncation marker" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    local diagnostic_file="$TMPROOT/diagnostic.raw" diagnostic_bytes
    mkdir -p "${fixture%/*}"
    head -c 8192 /dev/zero | tr '\000' x > "$fixture"

    p25_failure_diagnostic "$fixture" 0 0 0 0 > "$diagnostic_file"
    diagnostic_bytes="$(wc -c < "$diagnostic_file")"
    diagnostic_bytes="${diagnostic_bytes//[[:space:]]/}"
    [ "$diagnostic_bytes" -eq 4096 ] \
        && grep -Fq 'fixture_snapshot_truncated=yes' "$diagnostic_file" \
        && grep -Fq 'diagnostic_output_truncated=yes' "$diagnostic_file"
}

@test "P2.5 failure diagnostic leaves snapshot truncation unavailable when size read fails" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    local fake_bin="$TMPROOT/fake-bin"
    mkdir -p "${fixture%/*}" "$fake_bin"
    head -c 64 /dev/zero | tr '\000' x > "$fixture"
    cat > "$fake_bin/wc" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$fake_bin/wc"

    local original_path="$PATH"
    PATH="$fake_bin:$PATH"
    run p25_failure_diagnostic "$fixture" 0 0 0 0
    local diagnostic_status="$status" diagnostic_output="$output"
    PATH="$original_path"

    [ "$diagnostic_status" -eq 0 ] \
        && [[ "$diagnostic_output" == *'fixture_bytes=unavailable: byte count failed'* ]] \
        && [[ "$diagnostic_output" == *'fixture_snapshot_encoding=hex fixture_snapshot_source_bytes=64 fixture_snapshot_truncated=unavailable'* ]] \
        && [[ "$diagnostic_output" == *'fixture_snapshot_hex_prefix=7878'* ]] \
        && [[ "$diagnostic_output" == *'diagnostic_output_truncated=no'* ]]
}

@test "P2.5 failure diagnostic captures four fixed child streams as bounded metadata" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    mkdir -p "${fixture%/*}"
    write_base_init_task TEST-0205
    local one_out='child-one-stdout-private-canary' one_err='child-one-stderr-private-canary'
    local two_out='child-two-stdout-private-canary' two_err='child-two-stderr-private-canary'
    printf '%s' "$one_out" > "$TMPROOT/child-1.stdout"
    printf '%s' "$one_err" > "$TMPROOT/child-1.stderr"
    printf '%s' "$two_out" > "$TMPROOT/child-2.stdout"
    printf '%s' "$two_err" > "$TMPROOT/child-2.stderr"
    local before after status_copy output_copy
    local expected_one_out_sha expected_one_out_prefix
    local expected_one_err_sha expected_one_err_prefix
    local expected_two_out_sha expected_two_out_prefix
    local expected_two_err_sha expected_two_err_prefix
    before="$(p25_measure_test_inputs "$fixture")"
    run p25_failure_diagnostic "$fixture" 3 4 0 0 43121 43122
    status_copy="$status"; output_copy="$output"
    after="$(p25_measure_test_inputs "$fixture")"
    p25_record_diagnostic_case child-diagnostic-1 "$status_copy" "$output_copy" "$before" "$after"

    expected_one_out_sha="$(printf '%s' "$one_out" | sha256sum)"; expected_one_out_sha="${expected_one_out_sha%%[[:space:]]*}"
    expected_one_out_prefix="$(printf '%s' "$one_out" | od -An -v -tx1 -N64 | tr -d '[:space:]')"
    expected_one_err_sha="$(printf '%s' "$one_err" | sha256sum)"; expected_one_err_sha="${expected_one_err_sha%%[[:space:]]*}"
    expected_one_err_prefix="$(printf '%s' "$one_err" | od -An -v -tx1 -N64 | tr -d '[:space:]')"
    expected_two_out_sha="$(printf '%s' "$two_out" | sha256sum)"; expected_two_out_sha="${expected_two_out_sha%%[[:space:]]*}"
    expected_two_out_prefix="$(printf '%s' "$two_out" | od -An -v -tx1 -N64 | tr -d '[:space:]')"
    expected_two_err_sha="$(printf '%s' "$two_err" | sha256sum)"; expected_two_err_sha="${expected_two_err_sha%%[[:space:]]*}"
    expected_two_err_prefix="$(printf '%s' "$two_err" | od -An -v -tx1 -N64 | tr -d '[:space:]')"

    [ "$status_copy" -eq 0 ] \
        && [[ "$output_copy" == *'child_1_pid=43121 child_1_exit=3'* ]] \
        && [[ "$output_copy" == *'child_2_pid=43122 child_2_exit=4'* ]] \
        && [[ "$output_copy" == *'child_1_stdout_availability=available'* ]] \
        && [[ "$output_copy" == *'child_1_stderr_availability=available'* ]] \
        && [[ "$output_copy" == *'child_2_stdout_availability=available'* ]] \
        && [[ "$output_copy" == *'child_2_stderr_availability=available'* ]] \
        && [[ "$output_copy" == *'child_1_stdout_bytes=31'* ]] \
        && [[ "$output_copy" == *'child_1_stderr_bytes=31'* ]] \
        && [[ "$output_copy" == *'child_2_stdout_bytes=31'* ]] \
        && [[ "$output_copy" == *'child_2_stderr_bytes=31'* ]] \
        && [[ "$output_copy" == *"child_1_stdout_sha256=$expected_one_out_sha"* ]] \
        && [[ "$output_copy" == *"child_1_stdout_prefix_hex=$expected_one_out_prefix"* ]] \
        && [[ "$output_copy" == *'child_1_stdout_prefix_truncated=no'* ]] \
        && [[ "$output_copy" == *"child_1_stderr_sha256=$expected_one_err_sha"* ]] \
        && [[ "$output_copy" == *"child_1_stderr_prefix_hex=$expected_one_err_prefix"* ]] \
        && [[ "$output_copy" == *'child_1_stderr_prefix_truncated=no'* ]] \
        && [[ "$output_copy" == *"child_2_stdout_sha256=$expected_two_out_sha"* ]] \
        && [[ "$output_copy" == *"child_2_stdout_prefix_hex=$expected_two_out_prefix"* ]] \
        && [[ "$output_copy" == *'child_2_stdout_prefix_truncated=no'* ]] \
        && [[ "$output_copy" == *"child_2_stderr_sha256=$expected_two_err_sha"* ]] \
        && [[ "$output_copy" == *"child_2_stderr_prefix_hex=$expected_two_err_prefix"* ]] \
        && [[ "$output_copy" == *'child_2_stderr_prefix_truncated=no'* ]] \
        && [[ "$output_copy" == *'diagnostic_output_truncated=no'* ]] \
        && [[ "$before" == "$after" ]] \
        && [[ "$output_copy" != *"$one_out"* ]] \
        && [[ "$output_copy" != *"$one_err"* ]] \
        && [[ "$output_copy" != *"$two_out"* ]] \
        && [[ "$output_copy" != *"$two_err"* ]]
}

@test "P2.5 failure diagnostic distinguishes empty, missing, unreadable, and symlink streams" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    mkdir -p "${fixture%/*}"
    write_base_init_task TEST-0205
    : > "$TMPROOT/child-1.stdout"
    printf 'unreadable-private-canary' > "$TMPROOT/child-2.stdout"
    chmod 000 "$TMPROOT/child-2.stdout"
    printf 'symlink-private-canary' > "$TMPROOT/child-2.stderr-target"
    ln -s "$TMPROOT/child-2.stderr-target" "$TMPROOT/child-1.stderr"
    local before after status_copy output_copy
    before="$(p25_measure_test_inputs "$fixture")"
    run p25_failure_diagnostic "$fixture" 0 0 0 0 43131 43132
    status_copy="$status"; output_copy="$output"
    after="$(p25_measure_test_inputs "$fixture")"
    p25_record_diagnostic_case child-diagnostic-2 "$status_copy" "$output_copy" "$before" "$after"
    chmod 600 "$TMPROOT/child-2.stdout"

    [ "$status_copy" -eq 0 ] \
        && [[ "$output_copy" == *'child_1_stdout_availability=available child_1_stdout_bytes=0'* ]] \
        && [[ "$output_copy" == *'child_1_stdout_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'* ]] \
        && [[ "$output_copy" == *'child_1_stdout_prefix_truncated=no'* ]] \
        && [[ "$output_copy" == *'child_1_stderr_availability=unavailable:symlink'* ]] \
        && [[ "$output_copy" == *'child_1_stderr_bytes=NOT_MEASURED'* ]] \
        && [[ "$output_copy" == *'child_2_stdout_availability=unavailable:unreadable'* ]] \
        && [[ "$output_copy" == *'child_2_stdout_sha256=NOT_MEASURED'* ]] \
        && [[ "$output_copy" == *'child_2_stderr_availability=unavailable:missing'* ]] \
        && [[ "$output_copy" != *'unreadable-private-canary'* ]] \
        && [[ "$output_copy" != *'symlink-private-canary'* ]]
}

@test "P2.5 failure diagnostic keeps child metadata and explicit truncation within 4096 bytes" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    local diagnostic_file="$TMPROOT/diagnostic.raw" diagnostic_bytes prefix before after output_copy status_copy
    mkdir -p "${fixture%/*}"
    head -c 8192 /dev/zero | tr '\000' x > "$fixture"
    for stream in child-1.stdout child-1.stderr child-2.stdout child-2.stderr; do
        head -c 256 /dev/zero | tr '\000' y > "$TMPROOT/$stream"
    done
    before="$(p25_measure_test_inputs "$fixture")"
    p25_failure_diagnostic "$fixture" 0 0 0 0 43141 43142 > "$diagnostic_file"
    status_copy="$?"
    output_copy="$(cat "$diagnostic_file")"
    after="$(p25_measure_test_inputs "$fixture")"
    p25_record_diagnostic_case child-diagnostic-3 "$status_copy" "$output_copy" "$before" "$after"
    diagnostic_bytes="$(wc -c < "$diagnostic_file")"; diagnostic_bytes="${diagnostic_bytes//[[:space:]]/}"
    prefix="$(head -c 4096 "$diagnostic_file")"

    [ "$status_copy" -eq 0 ] \
        && [ "$diagnostic_bytes" -eq 4096 ] \
        && grep -Fq 'child_1_pid=43141 child_1_exit=0' "$diagnostic_file" \
        && grep -Fq 'child_2_pid=43142 child_2_exit=0' "$diagnostic_file" \
        && grep -Fq 'child_1_stdout_prefix_truncated=yes' "$diagnostic_file" \
        && grep -Fq 'fixture_snapshot_truncated=yes' "$diagnostic_file" \
        && grep -Fq 'diagnostic_output_truncated=yes' "$diagnostic_file" \
        && [[ "$prefix" != *'child-1.stdout'* ]]
}

@test "P2.5 failure diagnostic preserves fixed-field propagation and synthetic inputs" {
    local fixture="$TMPROOT/datarim/tasks/TEST-0205-init-task.md"
    mkdir -p "${fixture%/*}"
    write_base_init_task TEST-0205
    printf 'field-propagation-canary' > "$TMPROOT/child-1.stdout"
    local before source_before source_after status_copy output_copy
    before="$(p25_measure_test_inputs "$fixture")"
    source_before="$(sha256sum < "$ROOT_DIR/tests/tune-0216-qa-roundtrip.bats")"; source_before="${source_before%%[[:space:]]*}"
    run p25_failure_diagnostic "$fixture" 7 8 1 9 43151 43152
    status_copy="$status"; output_copy="$output"
    source_after="$(sha256sum < "$ROOT_DIR/tests/tune-0216-qa-roundtrip.bats")"; source_after="${source_after%%[[:space:]]*}"
    p25_record_diagnostic_case child-diagnostic-4 "$status_copy" "$output_copy" "$before" "$(p25_measure_test_inputs "$fixture")"

    [ "$status_copy" -eq 0 ] \
        && [[ "$output_copy" == *'child_1_exit=7 child_2_exit=8 validator_exit=9 heading_count=1'* ]] \
        && [[ "$output_copy" == *'child_1_pid=43151 child_1_exit=7'* ]] \
        && [[ "$output_copy" == *'child_2_pid=43152 child_2_exit=8'* ]] \
        && [[ "$output_copy" == *'child_1_stdout_availability=available'* ]] \
        && [[ "$output_copy" == *'child_1_stderr_availability=unavailable:missing'* ]] \
        && [[ "$output_copy" == *'child_1_stdout_prefix_hex='* ]] \
        && [[ "$output_copy" != *'field-propagation-canary'* ]] \
        && [ "$source_before" = "$source_after" ] \
        && [[ "$before" == "$(p25_measure_test_inputs "$fixture")" ]]
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

@test "P2.7 cleanup releases the lock after temp cleanup itself fails" {
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

    # flock path: lock releases on FD close (may leave empty .qa-lock file).
    # mkdir fallback: cleanup must still rmdir the directory lock after rm fails.
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"simulated init-task read failure"* ]] \
        && [[ "$output" == *"simulated temp cleanup failure"* ]] \
        && grep -qF "$tasks_dir/.TEST-0207.qa.append." "$rm_log" \
        && cmp -s "$original" "$init_file" \
        && [ ! -d "$tasks_dir/.TEST-0207.qa-lock" ] \
        && {
            if command -v flock >/dev/null 2>&1; then
                # Subsequent acquire must succeed — proves flock was released.
                "$APPEND" --root "$TMPROOT" --task TEST-0207 --stage do --round 1 \
                    --question-file "$q" --answer-file "$a" \
                    --decided-by operator \
                    --summary "Lock must be free after failed cleanup." \
                    >/dev/null 2>&1
            else
                grep -qF "$tasks_dir/.TEST-0207.qa-lock" "$rmdir_log"
            fi
        }
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
