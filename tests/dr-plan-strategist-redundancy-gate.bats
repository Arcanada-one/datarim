#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    HELPER="$REPO_ROOT/dev-tools/check-strategist-gate-record.sh"
    COMMAND="$REPO_ROOT/commands/dr-plan.md"
    STRATEGIST="$REPO_ROOT/agents/strategist.md"
    TASK_ID="TUNE-0141"
    INVOCATION_ID="plan-20260720T011722Z"
    DIGEST="1005d94539506a705895eb61caa2da20c53d55d75b0ae493a96ca46b633f8444"
    TEST_ROOT="$BATS_TEST_TMPDIR/workspace-$BATS_TEST_NUMBER"
    TASK_DIR="$TEST_ROOT/datarim/.auto/strategist-gate/$TASK_ID"
    RECORD_REL="datarim/.auto/strategist-gate/$TASK_ID/$INVOCATION_ID.record"
    RECORD="$TEST_ROOT/$RECORD_REL"
    REAL_STAT_BIN="$(command -v stat)"
    mkdir -p "$TASK_DIR"
    chmod 700 "$TASK_DIR"
}

make_swapping_stat() {
    swap_kind="$1"
    wrapper_dir="$BATS_TEST_TMPDIR/stat-wrapper-$BATS_TEST_NUMBER-$swap_kind"
    mkdir -p "$wrapper_dir"
    printf '%s\n' 0 >"$wrapper_dir/count"
    cat >"$wrapper_dir/stat" <<'EOF'
#!/bin/sh
count=$(cat "$SWAP_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$SWAP_COUNT"
if [ "$count" -eq 5 ]; then
    case "$SWAP_KIND" in
        record)
            mv "$SWAP_RECORD" "$SWAP_RECORD.old"
            cp "$SWAP_REPLACEMENT" "$SWAP_RECORD"
            chmod 600 "$SWAP_RECORD"
            ;;
        directory)
            mv "$SWAP_TASK_DIR" "$SWAP_TASK_DIR.old"
            mkdir -p "$SWAP_TASK_DIR"
            chmod 700 "$SWAP_TASK_DIR"
            cp "$SWAP_REPLACEMENT" "$SWAP_RECORD"
            chmod 600 "$SWAP_RECORD"
            ;;
    esac
fi
exec "$REAL_STAT_BIN" "$@"
EOF
    chmod 755 "$wrapper_dir/stat"
    SWAP_WRAPPER_DIR="$wrapper_dir"
    SWAP_COUNT_FILE="$wrapper_dir/count"
}

write_record() {
    cat >"$RECORD" <<EOF
schema_version=1
task_id=$TASK_ID
invocation_id=$INVOCATION_ID
scope_digest=$DIGEST
complexity=L3
classification=non_matching
positive_scope_test=fail
no_new_behavior_test=fail
scope_evidence=datarim/tasks/$TASK_ID-init-task.md:21,datarim/prd/PRD-$TASK_ID.md:47
invocation_reason=complexity_gate
strategist_invoked=yes
verdict=NOT_APPLICABLE
worth_building=not_applicable
rationale=not_applicable
most_efficient_path=not_applicable
safety_assessment=not_applicable
gate_status=not_applicable
route=proceed
EOF
    chmod 600 "$RECORD"
}

run_helper() {
    run "$HELPER" \
        --root "$TEST_ROOT" \
        --record "$RECORD_REL" \
        --task "$TASK_ID" \
        --complexity L3 \
        --invocation "$INVOCATION_ID" \
        --scope-digest "$DIGEST"
}

run_helper_at_complexity() {
    selected_complexity="$1"
    run "$HELPER" \
        --root "$TEST_ROOT" \
        --record "$RECORD_REL" \
        --task "$TASK_ID" \
        --complexity "$selected_complexity" \
        --invocation "$INVOCATION_ID" \
        --scope-digest "$DIGEST"
}

replace_field() {
    field="$1"
    value="$2"
    awk -F= -v key="$field" -v replacement="$value" '
        $1 == key { print key "=" replacement; next }
        { print }
    ' "$RECORD" >"$RECORD.next"
    mv "$RECORD.next" "$RECORD"
    chmod 600 "$RECORD"
}

@test "[validator] help is available and missing arguments use exit 64" {
    run "$HELPER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--scope-digest"* ]]

    run "$HELPER" --task "$TASK_ID"
    [ "$status" -eq 64 ]

    run "$HELPER" $'--token=secret\033[31m\nforged'
    [ "$status" -eq 64 ]
    [ "$output" = "check-strategist-gate-record: unknown flag" ]
}

@test "[validator] valid L3 non-matching record preserves the normal route" {
    write_record
    run_helper
    [ "$status" -eq 0 ]
    [ "$output" = $'result=normal_route\nreason=not_applicable' ]
}

@test "[validator] valid L2 redundancy-only GO advances" {
    write_record
    replace_field complexity L2
    replace_field classification redundancy_only
    replace_field positive_scope_test pass
    replace_field no_new_behavior_test pass
    replace_field invocation_reason redundancy_gate
    replace_field verdict GO
    replace_field worth_building yes
    replace_field rationale "removal is worth doing"
    replace_field most_efficient_path "delete the unused survivor"
    replace_field safety_assessment "rollback remains available"
    replace_field gate_status pass
    run "$HELPER" --root "$TEST_ROOT" --record "$RECORD_REL" --task "$TASK_ID" \
        --complexity L2 --invocation "$INVOCATION_ID" --scope-digest "$DIGEST"
    [ "$status" -eq 0 ]
    [ "$output" = $'result=advance\nreason=strategist_go' ]
}

@test "[validator] valid NO_GO PIVOT and INCOMPLETE records block" {
    for verdict_worth in "NO_GO no" "PIVOT conditional" "INCOMPLETE conditional"; do
        write_record
        replace_field classification redundancy_only
        replace_field positive_scope_test pass
        replace_field no_new_behavior_test pass
        replace_field invocation_reason both
        read -r selected_verdict selected_worth <<<"$verdict_worth"
        replace_field verdict "$selected_verdict"
        replace_field worth_building "$selected_worth"
        replace_field rationale "strategist did not approve"
        replace_field most_efficient_path "return to product definition"
        replace_field safety_assessment "no later gate is bypassed"
        replace_field gate_status block
        replace_field route return_to_prd
        run_helper
        [ "$status" -eq 1 ]
        [ "${lines[0]}" = "result=block" ]
    done
}

@test "[validator] ambiguous predicate pairs are complete but non-advancing" {
    for pair in "unknown unknown" "unknown pass" "pass unknown"; do
        write_record
        read -r selected_positive selected_behavior <<<"$pair"
        replace_field classification ambiguous
        replace_field positive_scope_test "$selected_positive"
        replace_field no_new_behavior_test "$selected_behavior"
        replace_field invocation_reason both
        replace_field verdict INCOMPLETE
        replace_field worth_building conditional
        replace_field rationale "scope evidence is unresolved"
        replace_field most_efficient_path "return to product definition"
        replace_field safety_assessment "do not advance"
        replace_field gate_status block
        replace_field route return_to_prd
        run_helper
        [ "$status" -eq 1 ]
    done
}

@test "[validator] every allowed non-matching predicate pair preserves routing" {
    for pair in "fail fail" "fail pass" "fail unknown" "pass fail" "unknown fail"; do
        write_record
        read -r selected_positive selected_behavior <<<"$pair"
        replace_field positive_scope_test "$selected_positive"
        replace_field no_new_behavior_test "$selected_behavior"
        run_helper
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "result=normal_route" ]
    done
}

@test "[validator] every complexity and invocation-reason truth-table row is executable" {
    for complexity_reason in "L1 redundancy_gate" "L2 redundancy_gate" "L3 both" "L4 both"; do
        read -r selected_complexity selected_reason <<<"$complexity_reason"

        write_record
        replace_field complexity "$selected_complexity"
        replace_field classification redundancy_only
        replace_field positive_scope_test pass
        replace_field no_new_behavior_test pass
        replace_field invocation_reason "$selected_reason"
        replace_field verdict GO
        replace_field worth_building yes
        replace_field rationale "the reduction is worth doing"
        replace_field most_efficient_path "remove the unused surface"
        replace_field safety_assessment "rollback remains available"
        replace_field gate_status pass
        run_helper_at_complexity "$selected_complexity"
        [ "$status" -eq 0 ]

        for verdict_worth in "NO_GO no" "PIVOT conditional" "INCOMPLETE conditional"; do
            read -r selected_verdict selected_worth <<<"$verdict_worth"
            replace_field verdict "$selected_verdict"
            replace_field worth_building "$selected_worth"
            replace_field gate_status block
            replace_field route return_to_prd
            run_helper_at_complexity "$selected_complexity"
            [ "$status" -eq 1 ]
        done

        replace_field classification ambiguous
        replace_field positive_scope_test unknown
        replace_field no_new_behavior_test pass
        replace_field verdict INCOMPLETE
        replace_field worth_building conditional
        run_helper_at_complexity "$selected_complexity"
        [ "$status" -eq 1 ]
    done

    for normal_tuple in \
        "L1 none no" "L1 redundancy_gate yes" \
        "L2 none no" "L2 redundancy_gate yes" \
        "L3 complexity_gate yes" "L3 both yes" \
        "L4 complexity_gate yes" "L4 both yes"; do
        read -r selected_complexity selected_reason selected_invoked <<<"$normal_tuple"
        write_record
        replace_field complexity "$selected_complexity"
        replace_field invocation_reason "$selected_reason"
        replace_field strategist_invoked "$selected_invoked"
        run_helper_at_complexity "$selected_complexity"
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "result=normal_route" ]
    done
}

@test "[validator] missing duplicate and unknown keys are malformed" {
    for key in schema_version task_id invocation_id scope_digest complexity \
        classification positive_scope_test no_new_behavior_test scope_evidence \
        invocation_reason strategist_invoked verdict worth_building rationale \
        most_efficient_path safety_assessment gate_status route; do
        write_record
        sed "/^${key}=/d" "$RECORD" >"$RECORD.next" && mv "$RECORD.next" "$RECORD"
        chmod 600 "$RECORD"
        run_helper
        [ "$status" -eq 2 ]
    done

    write_record
    printf '%s\n' 'route=proceed' >>"$RECORD"
    run_helper
    [ "$status" -eq 2 ]

    write_record
    printf '%s\n' 'extra_key=no' >>"$RECORD"
    run_helper
    [ "$status" -eq 2 ]
}

@test "[validator] task invocation digest and complexity bindings are exact" {
    write_record
    replace_field task_id TUNE-9999
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field invocation_id plan-other
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field scope_digest aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field complexity L2
    run_helper
    [ "$status" -eq 2 ]
}

@test "[validator] unsafe task and invocation components fail before path access" {
    write_record
    for bad_task in ../TUNE-0141 /TUNE-0141 -TUNE-0141 TUNE/0141 $'TUNE-0141\t'; do
        run "$HELPER" --root "$TEST_ROOT" --record "$RECORD_REL" --task "$bad_task" \
            --complexity L3 --invocation "$INVOCATION_ID" --scope-digest "$DIGEST"
        [ "$status" -eq 64 ]
    done
    long_invocation="i$(printf '%0100d' 0)"
    for bad_invocation in ../plan /plan -plan plan/id "$long_invocation" $'plan\tbad'; do
        run "$HELPER" --root "$TEST_ROOT" --record "$RECORD_REL" --task "$TASK_ID" \
            --complexity L3 --invocation "$bad_invocation" --scope-digest "$DIGEST"
        [ "$status" -eq 64 ]
    done
}

@test "[validator] out-of-root and non-canonical record paths are rejected" {
    write_record
    run "$HELPER" --root "$TEST_ROOT" --record "../$RECORD_REL" --task "$TASK_ID" \
        --complexity L3 --invocation "$INVOCATION_ID" --scope-digest "$DIGEST"
    [ "$status" -eq 2 ]

    run "$HELPER" --root "$TEST_ROOT" --record "/tmp/$INVOCATION_ID.record" --task "$TASK_ID" \
        --complexity L3 --invocation "$INVOCATION_ID" --scope-digest "$DIGEST"
    [ "$status" -eq 2 ]
}

@test "[validator] wrong mode symlink and symlinked intermediate component are rejected" {
    write_record
    chmod 644 "$RECORD"
    run_helper
    [ "$status" -eq 2 ]

    write_record
    mv "$RECORD" "$RECORD.target"
    ln -s "$RECORD.target" "$RECORD"
    run_helper
    [ "$status" -eq 2 ]

    alt_root="$BATS_TEST_TMPDIR/alt-$BATS_TEST_NUMBER"
    mkdir -p "$alt_root/.auto/strategist-gate/$TASK_ID"
    chmod 700 "$alt_root/.auto/strategist-gate/$TASK_ID"
    mv "$TEST_ROOT/datarim" "$TEST_ROOT/datarim.real"
    ln -s "$alt_root" "$TEST_ROOT/datarim"
    run_helper
    [ "$status" -eq 2 ]
}

@test "[validator] task directory must be current-user-owned mode 0700" {
    write_record
    chmod 755 "$TASK_DIR"
    run_helper
    [ "$status" -eq 2 ]
}

@test "[validator] wrong ownership is rejected when the fixture can change owner" {
    [ "$(id -u)" -eq 0 ] || skip "requires root to construct a wrong-owner fixture"
    write_record
    chown 65534 "$TASK_DIR"
    run_helper
    [ "$status" -eq 2 ]
}

@test "[validator] descriptor and task-directory swaps are rejected" {
    for swap_kind in record directory; do
        write_record
        replacement="$BATS_TEST_TMPDIR/replacement-$BATS_TEST_NUMBER-$swap_kind.record"
        cp "$RECORD" "$replacement"
        chmod 600 "$replacement"
        make_swapping_stat "$swap_kind"
        run env \
            PATH="$SWAP_WRAPPER_DIR:$PATH" \
            REAL_STAT_BIN="$REAL_STAT_BIN" \
            SWAP_COUNT="$SWAP_COUNT_FILE" \
            SWAP_KIND="$swap_kind" \
            SWAP_RECORD="$RECORD" \
            SWAP_REPLACEMENT="$replacement" \
            SWAP_TASK_DIR="$TASK_DIR" \
            "$HELPER" --root "$TEST_ROOT" --record "$RECORD_REL" --task "$TASK_ID" \
            --complexity L3 --invocation "$INVOCATION_ID" --scope-digest "$DIGEST"
        [ "$status" -eq 2 ]
    done
}

@test "[validator] invalid evidence paths and line references are rejected" {
    for evidence in "/tmp/x:1" "../tasks/x:1" "-option:1" "--option:1" \
        "datarim/tasks/TUNE-9999-init-task.md:1" "datarim/tasks/$TASK_ID-init-task.md:0"; do
        write_record
        replace_field scope_evidence "$evidence"
        run_helper
        [ "$status" -eq 2 ]
    done
}

@test "[validator] controls UTF-8 oversized values and secret-like payloads are rejected" {
    write_record
    sed '/^rationale=/d' "$RECORD" >"$RECORD.next"
    printf 'rationale=not_app\0licable\n' >>"$RECORD.next"
    mv "$RECORD.next" "$RECORD"
    chmod 600 "$RECORD"
    run_helper
    [ "$status" -eq 2 ]

    write_record
    sed '/^rationale=/d' "$RECORD" >"$RECORD.next"
    printf 'rationale=not_app\0licable' >>"$RECORD.next"
    mv "$RECORD.next" "$RECORD"
    chmod 600 "$RECORD"
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field rationale $'bad\tvalue'
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field rationale "café"
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field rationale "$(printf '%0501d' 0)"
    run_helper
    [ "$status" -eq 2 ]

    for payload in "token=abc" "password: abc" "Authorization: Bearer abc" \
        "eyJhbGciOiJIUzI1NiJ9.payload.signature" "-----BEGIN PRIVATE KEY-----" \
        "api_key=abc" "route=/dr-do" "(route=/dr-do)" "next_step=/dr-do" \
        "Next Step: /dr-do" "see(../secrets)" "path=/etc/passwd" \
        "operator@example.com" "+1 (555) 123-4567"; do
        write_record
        replace_field rationale "$payload"
        run_helper
        [ "$status" -eq 2 ]
    done
}

@test "[validator] contradictory truth-table tuples are rejected" {
    write_record
    replace_field classification redundancy_only
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field positive_scope_test unknown
    replace_field no_new_behavior_test pass
    run_helper
    [ "$status" -eq 2 ]

    write_record
    replace_field invocation_reason both
    replace_field strategist_invoked no
    run_helper
    [ "$status" -eq 2 ]
}

@test "[validator] complexity matrix rejects L1 complexity_gate and L3 none" {
    write_record
    replace_field complexity L1
    run "$HELPER" --root "$TEST_ROOT" --record "$RECORD_REL" --task "$TASK_ID" \
        --complexity L1 --invocation "$INVOCATION_ID" --scope-digest "$DIGEST"
    [ "$status" -eq 2 ]

    write_record
    replace_field invocation_reason none
    replace_field strategist_invoked no
    run_helper
    [ "$status" -eq 2 ]
}

@test "[contract] dr-plan mandates semantic classification strategist dispatch and validated logging" {
    grep -qF 'redundancy_only' "$COMMAND"
    grep -qF 'non_matching' "$COMMAND"
    grep -qF 'ambiguous' "$COMMAND"
    grep -qF 'keyword' "$COMMAND"
    grep -qF 'exactly one strategist invocation' "$COMMAND"
    grep -qF 'atomic no-clobber' "$COMMAND"
    grep -qF 'check-strategist-gate-record.sh' "$COMMAND"
    grep -qF 'persist the exact validated' "$COMMAND"
    grep -qF 'return_to_prd' "$COMMAND"
    grep -qF 'separate parent-owned decision' "$COMMAND"
    grep -qF 'non-advancing even though the specialized helper returns' "$COMMAND"
}

@test "[contract] strategist proposes assessment only and cannot route or write" {
    grep -qF 'Closed redundancy-gate response' "$STRATEGIST"
    grep -qF 'intentional redundancy' "$STRATEGIST"
    grep -qF 'most_efficient_path' "$STRATEGIST"
    grep -qF 'must not write' "$STRATEGIST"
    grep -qF 'must not select' "$STRATEGIST"
}

@test "[contract] strategist GO unlocks Step 4 without weakening later hard gates" {
    step3_line="$(grep -n '^3\.  \*\*Strategist Gate' "$COMMAND" | cut -d: -f1)"
    step4_line="$(grep -n '^4\.  \*\*Detailed Design' "$COMMAND" | cut -d: -f1)"
    [ -n "$step3_line" ]
    [ -n "$step4_line" ]
    [ "$step3_line" -lt "$step4_line" ]
    grep -qF 'unlocks Step 4 only' "$COMMAND"
    grep -qF 'AUTOMATIC SPEC-GRAPH VALIDATION' "$COMMAND"
    grep -qF '## Post-Step Self-Verification Hook (Automatic)' "$COMMAND"
    grep -qF 'Stage Snapshot Emission' "$COMMAND"
}

@test "[docs] shipped references describe the same mandatory redundancy gate" {
    for file in \
        CLAUDE.md \
        README.md \
        documentation/explanation/pipeline.md \
        documentation/reference/agents.md \
        documentation/reference/commands.md \
        documentation/tutorials/getting-started.md \
        skills/visual-maps/utility-and-dependencies.md; do
        grep -Eqi 'redundancy|reductive' "$REPO_ROOT/$file"
        grep -Eqi 'strategist' "$REPO_ROOT/$file"
    done
    grep -qF 'check-strategist-gate-record.sh' \
        "$REPO_ROOT/documentation/reference/commands.md"
    grep -qF 'architectural-superseding probe' \
        "$REPO_ROOT/documentation/tutorials/getting-started.md"
}
