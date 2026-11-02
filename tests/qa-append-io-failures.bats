#!/usr/bin/env bats
# Focused final-replacement error reporting for append-init-task-qa.sh.

ROOT_DIR="$BATS_TEST_DIRNAME/.."
APPEND="$ROOT_DIR/dev-tools/append-init-task-qa.sh"

setup_file() {
    if [[ -z "${QA_APPEND_EVIDENCE_DIR:-}" ]]; then
        QA_APPEND_EVIDENCE_DIR="${BATS_FILE_TMPDIR}/qa-append-io-failure-evidence"
        export QA_APPEND_EVIDENCE_DIR
        mkdir -p -- "$QA_APPEND_EVIDENCE_DIR" || return 2
        chmod 700 -- "$QA_APPEND_EVIDENCE_DIR" || return 2
    fi
}

setup() {
    umask 077
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks" "$TMPROOT/fake-bin"
    printf 'original init-task bytes\n' > "$TMPROOT/datarim/tasks/TEST-8101-init-task.md"
    printf 'Synthetic question.\n' > "$TMPROOT/question.txt"
    printf 'Synthetic answer.\n' > "$TMPROOT/answer.txt"
    cp "$TMPROOT/datarim/tasks/TEST-8101-init-task.md" "$TMPROOT/original.md"
    cp "$TMPROOT/question.txt" "$TMPROOT/question.original"
    cp "$TMPROOT/answer.txt" "$TMPROOT/answer.original"
}

teardown() {
    rm -rf "$TMPROOT"
}

assert_no_owned_artifacts() {
    local task_id="$1" tasks_dir="$TMPROOT/datarim/tasks"
    [ ! -d "$tasks_dir/.${task_id}.qa-lock" ] \
        && ! compgen -G "$tasks_dir/.${task_id}.qa.append.*" >/dev/null
}

sha256_file() {
    local line
    line="$(sha256sum < "$1")" || return 1
    printf '%s' "${line%% *}"
}

record_invocation() {
    local label="$1" pid="$2" started="$3" ended="$4" status="$5" \
        helper_before="$6" helper_after="$7" init_before="$8" init_after="$9" \
        inputs_before="${10}" inputs_after="${11}"
    local output_dir="${QA_APPEND_EVIDENCE_DIR:-$TMPROOT/evidence}"
    shift 11
    mkdir -p "$output_dir"
    cp "$TMPROOT/$label.stdout" "$output_dir/$label.stdout"
    cp "$TMPROOT/$label.stderr" "$output_dir/$label.stderr"
    {
        printf 'case=%s\nhelper_pid=%s\nstarted_utc=%s\nended_utc=%s\nexit=%s\n' \
            "$label" "$pid" "$started" "$ended" "$status"
        printf 'cwd=%q\n' "$PWD"
        printf 'helper_sha256_before=%s\nhelper_sha256_after=%s\n' "$helper_before" "$helper_after"
        printf 'init_sha256_before=%s\ninit_sha256_after=%s\n' "$init_before" "$init_after"
        printf 'inputs_sha256_before=%s\ninputs_sha256_after=%s\n' "$inputs_before" "$inputs_after"
        local index=0 argument
        for argument in "$@"; do
            printf 'argv_%02d=%q\n' "$index" "$argument"
            index=$((index + 1))
        done
    } > "$output_dir/$label.meta"
    chmod 600 "$output_dir/$label.stdout" "$output_dir/$label.stderr" "$output_dir/$label.meta"
}

@test "replacement refusal returns I/O failure and preserves source and inputs" {
    local task_id=TEST-8101 marker="$TMPROOT/mv-called" original_sha input_sha helper_sha
    local started ended pid status init_after input_after helper_after
    cat > "$TMPROOT/fake-bin/mv" <<'EOF'
#!/bin/sh
printf 'called\n' > "$MV_MARKER"
exit 73
EOF
    chmod 700 "$TMPROOT/fake-bin/mv"
    original_sha="$(sha256_file "$TMPROOT/original.md")"
    input_sha="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_sha="$(sha256_file "$APPEND")"

    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PATH="$TMPROOT/fake-bin:$PATH" MV_MARKER="$marker" \
        "$APPEND" \
        --root "$TMPROOT" --task "$task_id" --stage qa --round 1 \
        --question-file "$TMPROOT/question.txt" \
        --answer-file "$TMPROOT/answer.txt" \
        --decided-by operator --summary "Synthetic replacement refusal." \
        > "$TMPROOT/refusal.stdout" 2> "$TMPROOT/refusal.stderr" &
    pid=$!
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    init_after="$(sha256_file "$TMPROOT/datarim/tasks/${task_id}-init-task.md")"
    input_after="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_after="$(sha256_file "$APPEND")"
    record_invocation refusal "$pid" "$started" "$ended" "$status" \
        "$helper_sha" "$helper_after" "$original_sha" "$init_after" \
        "$input_sha" "$input_after" \
        "$APPEND" --root "$TMPROOT" --task "$task_id" --stage qa --round 1 \
        --question-file "$TMPROOT/question.txt" --answer-file "$TMPROOT/answer.txt" \
        --decided-by operator --summary "Synthetic replacement refusal."
    local diagnostic
    diagnostic="$(cat "$TMPROOT/refusal.stderr")"

    [ "$status" -eq 1 ] \
        && [ ! -s "$TMPROOT/refusal.stdout" ] \
        && [[ "$diagnostic" == *"failed to replace init-task file"* ]] \
        && [ "${#diagnostic}" -lt 256 ] \
        && [[ "$diagnostic" != *"appended successfully"* ]] \
        && [ -f "$marker" ] \
        && cmp -s "$TMPROOT/original.md" "$TMPROOT/datarim/tasks/${task_id}-init-task.md" \
        && [ "$original_sha" = "$init_after" ] \
        && [ "$input_sha" = "$input_after" ] \
        && [ "$helper_sha" = "$helper_after" ] \
        && assert_no_owned_artifacts "$task_id"
}

@test "successful replacement preserves the existing Q&A block format" {
    local task_id=TEST-8102 actual="$TMPROOT/datarim/tasks/TEST-8102-init-task.md"
    local expected="$TMPROOT/expected.md"
    printf 'original init-task bytes\n' > "$actual"
    cp "$actual" "$TMPROOT/original.md"
    cp "$TMPROOT/question.txt" "$TMPROOT/question.original"
    cp "$TMPROOT/answer.txt" "$TMPROOT/answer.original"

    local started ended pid status init_before input_before helper_before
    init_before="$(sha256_file "$actual")"
    input_before="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_before="$(sha256_file "$APPEND")"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "$APPEND" \
        --root "$TMPROOT" --task "$task_id" --stage qa --round 1 \
        --question-file "$TMPROOT/question.txt" \
        --answer-file "$TMPROOT/answer.txt" \
        --decided-by operator --summary "Synthetic success." \
        --timestamp 2026-11-02T11:00:00Z \
        > "$TMPROOT/success.stdout" 2> "$TMPROOT/success.stderr" &
    pid=$!
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record_invocation success "$pid" "$started" "$ended" "$status" \
        "$helper_before" "$(sha256_file "$APPEND")" "$init_before" \
        "$(sha256_file "$actual")" "$input_before" \
        "$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")" \
        "$APPEND" --root "$TMPROOT" --task "$task_id" --stage qa --round 1 \
        --question-file "$TMPROOT/question.txt" --answer-file "$TMPROOT/answer.txt" \
        --decided-by operator --summary "Synthetic success." --timestamp 2026-11-02T11:00:00Z

    printf '%s\n' \
        'original init-task bytes' \
        '' \
        '### 2026-11-02T11:00:00Z — Q&A by /dr-qa (round 1)' \
        '' \
        '**Question (verbatim, asked by agent):**' \
        '' \
        'Synthetic question.' \
        '' \
        '**Answer (verbatim, by operator):**' \
        '' \
        'Synthetic answer.' \
        '' \
        '**Decided by:** operator' \
        '' \
        '**Summary (how it changes initial conditions):**' \
        '' \
        'Synthetic success.' \
        '' \
        '**Conflict with existing wish:** none' \
        '' > "$expected"

    [ "$status" -eq 0 ] \
        && [ ! -s "$TMPROOT/success.stdout" ] \
        && [ ! -s "$TMPROOT/success.stderr" ] \
        && cmp -s "$expected" "$actual" \
        && cmp -s "$TMPROOT/question.original" "$TMPROOT/question.txt" \
        && cmp -s "$TMPROOT/answer.original" "$TMPROOT/answer.txt" \
        && assert_no_owned_artifacts "$task_id"
}

assert_missing_value_parser_option() {
    local option="$1" label="${1#--}" case_dir="$QA_APPEND_EVIDENCE_DIR"
    local fixture="$TMPROOT/datarim/tasks/TEST-8101-init-task.md"
    local source_before source_after fixture_before fixture_after
    local started ended pid status raw_stdout raw_stderr meta

    case_dir="$case_dir/$label"
    mkdir -p "$case_dir"
    chmod 700 "$case_dir"
    source_before="$(sha256_file "$APPEND")"
    fixture_before="$(sha256_file "$fixture") $(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    raw_stdout="$TMPROOT/$label.stdout"
    raw_stderr="$TMPROOT/$label.stderr"
    meta="$case_dir/invocation.meta"

    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "$APPEND" "$option" > "$raw_stdout" 2> "$raw_stderr" &
    pid=$!
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    source_after="$(sha256_file "$APPEND")"
    fixture_after="$(sha256_file "$fixture") $(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"

    cp "$raw_stdout" "$case_dir/stdout.raw"
    cp "$raw_stderr" "$case_dir/stderr.raw"
    {
        printf 'case=terminal-missing-value\noption=%q\n' "$option"
        printf 'helper_pid=%s\nbats_test_shell_pid=%s\nbats_test_shell_ppid=%s\n' \
            "$pid" "$BASHPID" "$PPID"
        printf 'started_utc=%s\nended_utc=%s\nexit=%s\ncwd=%q\n' \
            "$started" "$ended" "$status" "$PWD"
        printf 'source_sha256_before=%s\nsource_sha256_after=%s\n' "$source_before" "$source_after"
        printf 'fixture_sha256_before=%s\nfixture_sha256_after=%s\n' "$fixture_before" "$fixture_after"
        printf 'stdout_bytes=%s\nstderr_bytes=%s\nstdout_sha256=%s\nstderr_sha256=%s\n' \
            "$(wc -c < "$case_dir/stdout.raw" | tr -d '[:space:]')" \
            "$(wc -c < "$case_dir/stderr.raw" | tr -d '[:space:]')" \
            "$(sha256_file "$case_dir/stdout.raw")" "$(sha256_file "$case_dir/stderr.raw")"
        printf 'argv_00=%q\nargv_01=%q\n' "$APPEND" "$option"
    } > "$meta"
    chmod 600 "$case_dir/stdout.raw" "$case_dir/stderr.raw" "$meta"

    [ "$status" -eq 2 ] \
        && [ ! -s "$case_dir/stdout.raw" ] \
        && grep -Fq -- "$option requires a value" "$case_dir/stderr.raw" \
        && [ "$source_before" = "$source_after" ] \
        && [ "$fixture_before" = "$fixture_after" ]
}

@test "missing value parser: --root returns usage exit 2" {
    assert_missing_value_parser_option --root
}

@test "missing value parser: --task returns usage exit 2" {
    assert_missing_value_parser_option --task
}

@test "missing value parser: --stage returns usage exit 2" {
    assert_missing_value_parser_option --stage
}

@test "missing value parser: --round returns usage exit 2" {
    assert_missing_value_parser_option --round
}

@test "missing value parser: --question-file returns usage exit 2" {
    assert_missing_value_parser_option --question-file
}

@test "missing value parser: --answer-file returns usage exit 2" {
    assert_missing_value_parser_option --answer-file
}

@test "missing value parser: --decided-by returns usage exit 2" {
    assert_missing_value_parser_option --decided-by
}

@test "missing value parser: --rationale-file returns usage exit 2" {
    assert_missing_value_parser_option --rationale-file
}

@test "missing value parser: --summary returns usage exit 2" {
    assert_missing_value_parser_option --summary
}

@test "missing value parser: --asked-by returns usage exit 2" {
    assert_missing_value_parser_option --asked-by
}

@test "missing value parser: --conflict-with returns usage exit 2" {
    assert_missing_value_parser_option --conflict-with
}

@test "missing value parser: --conflict-detail-file returns usage exit 2" {
    assert_missing_value_parser_option --conflict-detail-file
}

@test "missing value parser: --timestamp returns usage exit 2" {
    assert_missing_value_parser_option --timestamp
}

assert_line_guard_refuses() {
    local option="$1" bad_value="$2" label="$3" task_id=TEST-8101
    local actual="$TMPROOT/datarim/tasks/${task_id}-init-task.md"
    local source_before source_after fixture_before fixture_after input_before input_after
    local helper_before helper_after started ended pid status diagnostic raw_value_present
    local -a args=(
        --root "$TMPROOT" --task "$task_id" --stage qa --round 1
        --question-file "$TMPROOT/question.txt" --answer-file "$TMPROOT/answer.txt"
        --decided-by operator --summary "Synthetic summary."
    )
    args+=("$option" "$bad_value")
    source_before="$(sha256_file "$APPEND")"
    fixture_before="$(sha256_file "$actual")"
    input_before="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_before="$source_before"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "$APPEND" "${args[@]}" > "$TMPROOT/$label.stdout" 2> "$TMPROOT/$label.stderr" &
    pid=$!
    if wait "$pid"; then status=0; else status=$?; fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    source_after="$(sha256_file "$APPEND")"
    fixture_after="$(sha256_file "$actual")"
    input_after="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_after="$(sha256_file "$APPEND")"
    record_invocation "$label" "$pid" "$started" "$ended" "$status" \
        "$helper_before" "$helper_after" "$fixture_before" "$fixture_after" \
        "$input_before" "$input_after" "$APPEND" "${args[@]}"
    diagnostic="$(cat "$TMPROOT/$label.stderr")"
    if [[ "$diagnostic" == *"$bad_value"* ]]; then raw_value_present=true; else raw_value_present=false; fi

    [ "$status" -eq 2 ] \
        && [ ! -s "$TMPROOT/$label.stdout" ] \
        && grep -Fq -- "$option must be one line without control characters" "$TMPROOT/$label.stderr" \
        && [ "$raw_value_present" = false ] \
        && [ "${#diagnostic}" -lt 2048 ] \
        && [ "$source_before" = "$source_after" ] \
        && [ "$fixture_before" = "$fixture_after" ] \
        && [ "$input_before" = "$input_after" ] \
        && assert_no_owned_artifacts "$task_id"
}

@test "one-line guard: rejects summary LF" {
    assert_line_guard_refuses --summary $'first\nsecond' summary-lf
}

@test "one-line guard: rejects asked-by CR" {
    assert_line_guard_refuses --asked-by $'agent\rforged' asked-by-cr
}

@test "one-line guard: rejects timestamp ESC" {
    assert_line_guard_refuses --timestamp $'2026-11-02T11:00:00Z\033[31m' timestamp-esc
}

@test "one-line guard: rejects summary TAB" {
    assert_line_guard_refuses --summary $'safe\tforged' summary-tab
}

@test "one-line guard: rejects asked-by UTF-8 C1 U+0085" {
    assert_line_guard_refuses --asked-by $'agent\xc2\x85forged' asked-by-c1
}

@test "one-line guard: rejects timestamp UTF-8 C1 U+009F" {
    assert_line_guard_refuses --timestamp $'2026-11-02T11:00:00Z\xc2\x9fforged' timestamp-c1
}

@test "one-line guard: preserves printable UTF-8 summary and asked-by" {
    local task_id=TEST-8102 actual="$TMPROOT/datarim/tasks/TEST-8102-init-task.md"
    local expected="$TMPROOT/expected.md"
    local summary='Сводка ↔ проверка — OK' asked_by='Елена · QA ↔ D5'
    local timestamp=2026-11-02T11:45:00Z
    printf 'original init-task bytes\n' > "$actual"
    local source_before source_after fixture_before fixture_after input_before input_after
    local helper_before helper_after started ended pid status
    local -a args=(
        --root "$TMPROOT" --task "$task_id" --stage qa --round 1
        --question-file "$TMPROOT/question.txt" --answer-file "$TMPROOT/answer.txt"
        --decided-by operator --summary "$summary" --asked-by "$asked_by"
        --timestamp "$timestamp"
    )
    source_before="$(sha256_file "$APPEND")"
    fixture_before="$(sha256_file "$actual")"
    input_before="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_before="$source_before"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    "$APPEND" "${args[@]}" > "$TMPROOT/utf8-printable.stdout" 2> "$TMPROOT/utf8-printable.stderr" &
    pid=$!
    if wait "$pid"; then status=0; else status=$?; fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    source_after="$(sha256_file "$APPEND")"
    fixture_after="$(sha256_file "$actual")"
    input_after="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_after="$(sha256_file "$APPEND")"
    record_invocation utf8-printable "$pid" "$started" "$ended" "$status" \
        "$helper_before" "$helper_after" "$fixture_before" "$fixture_after" \
        "$input_before" "$input_after" "$APPEND" "${args[@]}"
    printf '%s\n' \
        'original init-task bytes' \
        '' \
        "### ${timestamp} — Q&A by /dr-qa (round 1)" \
        '' \
        "**Question (verbatim, asked by ${asked_by}):**" \
        '' \
        'Synthetic question.' \
        '' \
        '**Answer (verbatim, by operator):**' \
        '' \
        'Synthetic answer.' \
        '' \
        '**Decided by:** operator' \
        '' \
        '**Summary (how it changes initial conditions):**' \
        '' \
        "$summary" \
        '' \
        '**Conflict with existing wish:** none' \
        '' > "$expected"

    [ "$status" -eq 0 ] \
        && [ ! -s "$TMPROOT/utf8-printable.stdout" ] \
        && [ ! -s "$TMPROOT/utf8-printable.stderr" ] \
        && cmp -s "$expected" "$actual" \
        && cmp -s "$TMPROOT/question.original" "$TMPROOT/question.txt" \
        && cmp -s "$TMPROOT/answer.original" "$TMPROOT/answer.txt" \
        && [ "$source_before" = "$source_after" ] \
        && [ "$input_before" = "$input_after" ] \
        && assert_no_owned_artifacts "$task_id"
}

assert_line_guard_tool_failure() {
    local fail_pattern="$1" bad_value="$2" label="$3" task_id="$4"
    local actual="$TMPROOT/datarim/tasks/${task_id}-init-task.md"
    local marker="$TMPROOT/$label.grep-marker" real_grep source_before source_after
    local fixture_before fixture_after input_before input_after helper_before helper_after
    local started ended pid status diagnostic
    local -a args=(
        --root "$TMPROOT" --task "$task_id" --stage qa --round 1
        --question-file "$TMPROOT/question.txt" --answer-file "$TMPROOT/answer.txt"
        --decided-by operator --summary "$bad_value"
    )

    printf 'original init-task bytes\n' > "$actual"
    real_grep="$(command -v grep)"
    cat > "$TMPROOT/fake-bin/grep" <<'EOF'
#!/usr/bin/env bash
if [[ "${LINEGUARD_FAIL_PATTERN:-}" == ascii && "${2-}" == '[[:cntrl:]]' ]]; then
    printf 'ascii\n' > "$LINEGUARD_GREP_MARKER"
    exit 2
fi
c1_pattern=$'\xc2[\x80-\x9f]'
if [[ "${LINEGUARD_FAIL_PATTERN:-}" == c1 && "${2-}" == "$c1_pattern" ]]; then
    printf 'c1\n' > "$LINEGUARD_GREP_MARKER"
    exit 2
fi
exec "$LINEGUARD_REAL_GREP" "$@"
EOF
    chmod 700 "$TMPROOT/fake-bin/grep"

    source_before="$(sha256_file "$APPEND")"
    fixture_before="$(sha256_file "$actual")"
    input_before="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_before="$source_before"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PATH="$TMPROOT/fake-bin:$PATH" \
        LINEGUARD_FAIL_PATTERN="$fail_pattern" \
        LINEGUARD_GREP_MARKER="$marker" LINEGUARD_REAL_GREP="$real_grep" \
        "$APPEND" "${args[@]}" \
        > "$TMPROOT/$label.stdout" 2> "$TMPROOT/$label.stderr" &
    pid=$!
    if wait "$pid"; then status=0; else status=$?; fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    source_after="$(sha256_file "$APPEND")"
    fixture_after="$(sha256_file "$actual")"
    input_after="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    helper_after="$source_after"
    record_invocation "$label" "$pid" "$started" "$ended" "$status" \
        "$helper_before" "$helper_after" "$fixture_before" "$fixture_after" \
        "$input_before" "$input_after" \
        env "PATH=$TMPROOT/fake-bin:$PATH" "LINEGUARD_FAIL_PATTERN=$fail_pattern" \
        "LINEGUARD_GREP_MARKER=$marker" "LINEGUARD_REAL_GREP=$real_grep" \
        "$APPEND" "${args[@]}"
    diagnostic="$(cat "$TMPROOT/$label.stderr")"

    [ "$status" -eq 1 ] \
        && [ ! -s "$TMPROOT/$label.stdout" ] \
        && [ "$diagnostic" = 'ERROR: failed to inspect --summary for control characters' ] \
        && [ "$(cat "$marker")" = "$fail_pattern" ] \
        && [ "$(wc -l < "$marker" | tr -d '[:space:]')" -eq 1 ] \
        && [ "$source_before" = "$source_after" ] \
        && [ "$fixture_before" = "$fixture_after" ] \
        && [ "$input_before" = "$input_after" ] \
        && assert_no_owned_artifacts "$task_id"
}

@test "line guard execution error: ASCII scan failure returns I/O refusal" {
    assert_line_guard_tool_failure ascii $'synthetic\tvalue' ascii-grep-error TEST-8201
}

@test "line guard execution error: C1 scan failure returns I/O refusal" {
    assert_line_guard_tool_failure c1 $'synthetic\xc2\x85value' c1-grep-error TEST-8202
}

@test "line guard scan remains compatible with printable UTF-8" {
    local task_id=TEST-8203 actual="$TMPROOT/datarim/tasks/TEST-8203-init-task.md"
    local expected="$TMPROOT/expected.md" helper_before helper_after init_before init_after
    local input_before input_after started ended pid status real_grep
    local summary='Résumé — café'
    local -a args=(
        --root "$TMPROOT" --task "$task_id" --stage qa --round 1
        --question-file "$TMPROOT/question.txt" --answer-file "$TMPROOT/answer.txt"
        --decided-by operator --summary "$summary" --timestamp 2026-11-02T13:30:00Z
    )

    printf 'original init-task bytes\n' > "$actual"
    cat > "$TMPROOT/fake-bin/grep" <<'EOF'
#!/usr/bin/env bash
exec "$LINEGUARD_REAL_GREP" "$@"
EOF
    chmod 700 "$TMPROOT/fake-bin/grep"
    real_grep="$(command -v grep)"
    helper_before="$(sha256_file "$APPEND")"
    init_before="$(sha256_file "$actual")"
    input_before="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PATH="$TMPROOT/fake-bin:$PATH" LINEGUARD_REAL_GREP="$real_grep" \
        "$APPEND" "${args[@]}" \
        > "$TMPROOT/printable-utf8-tool-shim.stdout" \
        2> "$TMPROOT/printable-utf8-tool-shim.stderr" &
    pid=$!
    if wait "$pid"; then status=0; else status=$?; fi
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    helper_after="$(sha256_file "$APPEND")"
    init_after="$(sha256_file "$actual")"
    input_after="$(sha256_file "$TMPROOT/question.txt") $(sha256_file "$TMPROOT/answer.txt")"
    record_invocation printable-utf8-tool-shim "$pid" "$started" "$ended" "$status" \
        "$helper_before" "$helper_after" "$init_before" "$init_after" \
        "$input_before" "$input_after" \
        env "PATH=$TMPROOT/fake-bin:$PATH" "LINEGUARD_REAL_GREP=$real_grep" \
        "$APPEND" "${args[@]}"
    printf '%s\n' \
        'original init-task bytes' '' \
        '### 2026-11-02T13:30:00Z — Q&A by /dr-qa (round 1)' '' \
        '**Question (verbatim, asked by agent):**' '' \
        'Synthetic question.' '' \
        '**Answer (verbatim, by operator):**' '' \
        'Synthetic answer.' '' \
        '**Decided by:** operator' '' \
        '**Summary (how it changes initial conditions):**' '' \
        "$summary" '' \
        '**Conflict with existing wish:** none' '' > "$expected"

    [ "$status" -eq 0 ] \
        && [ ! -s "$TMPROOT/printable-utf8-tool-shim.stdout" ] \
        && [ ! -s "$TMPROOT/printable-utf8-tool-shim.stderr" ] \
        && cmp -s "$expected" "$actual" \
        && [ "$helper_before" = "$helper_after" ] \
        && [ "$input_before" = "$input_after" ] \
        && assert_no_owned_artifacts "$task_id"
}
