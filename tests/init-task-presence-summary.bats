#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CHECK="$REPO_ROOT/dev-tools/check-init-task-presence.sh"

setup() {
    umask 077
    WORK="$(mktemp -d "$BATS_TMPDIR/init-summary-XXXXXX")"
    mkdir -p "$WORK/datarim/tasks"
    export WORK
    FIXTURE_PATH="$WORK/datarim/tasks/TEST-0001-init-task.md"
    EVIDENCE_DIR="${INIT_TASK_EVIDENCE_DIR:-${TMPDIR:-/tmp}/datarim-init-task-summary-evidence-${USER:-user}-$$}"
    mkdir -p "$EVIDENCE_DIR"
    chmod 700 "$EVIDENCE_DIR"
    CASE_NUMBER=0
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

write_init_task() {
    local id="$1" mode="${2:-valid}" file
    file="$WORK/datarim/tasks/${id}-init-task.md"
    FIXTURE_PATH="$file"
    {
        printf '%s\n' '---'
        if [ "$mode" = "hostile" ]; then
            printf '%s\n' 'task_id: PRIVATE_SENTINEL_7fa2d1'
        else
            printf '%s\n' "task_id: $id"
        fi
        printf '%s\n' 'artifact: init-task' 'schema_version: 1' 'captured_at: 2026-11-02'
        if [ "$mode" != "missing-field" ]; then printf '%s\n' 'captured_by: /dr-init'; fi
        printf '%s\n' 'operator: synthetic' 'status: canonical' '---' ''
        if [ "$mode" != "missing-brief" ]; then
            printf '%s\n' '## Operator brief (verbatim)' '' 'Synthetic brief.' ''
        fi
        if [ "$mode" != "missing-append" ]; then
            printf '%s\n' '## Append-log (operator amendments)' '' '_(empty)_'
        fi
        if [ "$mode" = "bad-qa" ]; then
            printf '%s\n' '' '### 2026-11-02 — Q&A by /dr-do (round 1)' '' '**Question (verbatim, asked by agent):**'
        fi
        if [ "$mode" = "hostile" ]; then
            printf '%s\n' '' 'Private fixture value: PRIVATE_SENTINEL_7fa2d1'
        fi
    } > "$file"
}

hash_or_missing() {
    local path="$1"
    if [ -f "$path" ]; then
        sha256sum "$path" | awk '{print $1}'
    else
        printf '%s' MISSING
    fi
}

# Run the real CLI and persist process/raw/hash custody before the test asserts.
invoke_cli() {
    local label="$1"; shift
    CASE_NUMBER=$((CASE_NUMBER + 1))
    local stem="$EVIDENCE_DIR/${BATS_TEST_NAME//[^A-Za-z0-9_.-]/_}-${CASE_NUMBER}"
    CASE_OUT="$stem.stdout"
    CASE_ERR="$stem.stderr"
    CASE_STATUS_FILE="$stem.exit"
    local metadata="$stem.process.txt" start_utc end_utc pid status run_cwd="${CLI_CWD:-$REPO_ROOT}"
    local cli_check="${CLI_CHECK_OVERRIDE:-$CHECK}"
    local fixture="${FIXTURE_PATH:-$WORK/datarim/tasks/TEST-0001-init-task.md}"
    local source_before test_before fixture_before source_after test_after fixture_after
    source_before="$(hash_or_missing "$cli_check")"
    test_before="$(hash_or_missing "$BATS_TEST_FILENAME")"
    fixture_before="$(hash_or_missing "$fixture")"
    start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -n "${CLI_PATH_OVERRIDE:-}" ]; then
        (cd "$run_cwd" && env PATH="$CLI_PATH_OVERRIDE" "$cli_check" "$@") >"$CASE_OUT" 2>"$CASE_ERR" &
    else
        (cd "$run_cwd" && "$cli_check" "$@") >"$CASE_OUT" 2>"$CASE_ERR" &
    fi
    pid=$!
    if wait "$pid"; then status=0; else status=$?; fi
    end_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    source_after="$(hash_or_missing "$cli_check")"
    test_after="$(hash_or_missing "$BATS_TEST_FILENAME")"
    fixture_after="$(hash_or_missing "$fixture")"
    {
        printf '%s\n' \
            "case=$label" "pid=$pid" "start_utc=$start_utc" "end_utc=$end_utc" \
            "cwd=$run_cwd" "exit=$status" 'argv_begin'
        printf '  %q\n' "$cli_check" "$@"
        printf '%s\n' 'argv_end' \
            "source_sha256_before=$source_before" "source_sha256_after=$source_after" \
            "test_sha256_before=$test_before" "test_sha256_after=$test_after" \
            "fixture_sha256_before=$fixture_before" "fixture_sha256_after=$fixture_after"
    } > "$metadata"
    printf '%s\n' "$status" > "$CASE_STATUS_FILE"
    chmod 600 "$CASE_OUT" "$CASE_ERR" "$CASE_STATUS_FILE" "$metadata"
    CASE_STATUS="$status"
}

assert_case_immutable() {
    local metadata="${CASE_OUT%.stdout}.process.txt"
    [ "$(sed -n 's/^source_sha256_before=//p' "$metadata")" = "$(sed -n 's/^source_sha256_after=//p' "$metadata")" ] \
        && [ "$(sed -n 's/^test_sha256_before=//p' "$metadata")" = "$(sed -n 's/^test_sha256_after=//p' "$metadata")" ] \
        && [ "$(sed -n 's/^fixture_sha256_before=//p' "$metadata")" = "$(sed -n 's/^fixture_sha256_after=//p' "$metadata")" ]
}

@test "valid task emits the fixed measured summary" {
    write_init_task TEST-0001
    invoke_cli valid --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 0 ] \
        && [ "$(cat "$CASE_OUT")" = '{"schema":"DatarimInitTaskValidationSummary/v1","result":"VALID","exit_code":0,"diagnostic_codes":[],"error_count":0,"error_count_status":"MEASURED"}' ] \
        && [ ! -s "$CASE_ERR" ] \
        && [ "$(sed -n 's/^source_sha256_before=//p' "${CASE_OUT%.stdout}.process.txt")" = "$(sed -n 's/^source_sha256_after=//p' "${CASE_OUT%.stdout}.process.txt")" ] \
        && [ "$(sed -n 's/^fixture_sha256_before=//p' "${CASE_OUT%.stdout}.process.txt")" = "$(sed -n 's/^fixture_sha256_after=//p' "${CASE_OUT%.stdout}.process.txt")" ]
}

@test "explicit root accepts spaces tabs and printable Unicode" {
    local original_work="$WORK"
    WORK="$WORK/root with space"$'\t'"and Ω"
    mkdir -p "$WORK/datarim/tasks"
    write_init_task TEST-0001
    invoke_cli spaced-root --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 0 ] \
        && [[ "$(cat "$CASE_OUT")" == *'"result":"VALID"'* ]] \
        && WORK="$original_work"
}

@test "missing task reports unavailable with unknown count" {
    invoke_cli missing --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 1 ] \
        && [ "$(cat "$CASE_OUT")" = '{"schema":"DatarimInitTaskValidationSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":1,"diagnostic_codes":["INIT_TASK_FILE_UNAVAILABLE"],"error_count":null,"error_count_status":"NOT_MEASURED"}' ] \
        && [ ! -s "$CASE_ERR" ]
}

@test "existing malformed artifact reports its measured error count" {
    write_init_task TEST-0001 missing-append
    invoke_cli invalid --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 1 ] \
        && [ "$(cat "$CASE_OUT")" = '{"schema":"DatarimInitTaskValidationSummary/v1","result":"INVALID","exit_code":1,"diagnostic_codes":["INIT_TASK_INVALID"],"error_count":1,"error_count_status":"MEASURED"}' ] \
        && [ ! -s "$CASE_ERR" ]
}

@test "missing required field and heading stay in the measured invalid profile" {
    write_init_task TEST-0001 missing-field
    invoke_cli missing-field --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 1 ] \
        && [ "$(cat "$CASE_OUT")" = '{"schema":"DatarimInitTaskValidationSummary/v1","result":"INVALID","exit_code":1,"diagnostic_codes":["INIT_TASK_INVALID"],"error_count":1,"error_count_status":"MEASURED"}' ] \
        && write_init_task TEST-0001 missing-brief \
        && invoke_cli missing-heading --task TEST-0001 --root "$WORK" --summary-json \
        && [ "$CASE_STATUS" -eq 1 ] \
        && [ "$(cat "$CASE_OUT")" = '{"schema":"DatarimInitTaskValidationSummary/v1","result":"INVALID","exit_code":1,"diagnostic_codes":["INIT_TASK_INVALID"],"error_count":1,"error_count_status":"MEASURED"}' ]
}

@test "malformed Q&A block remains an invalid measured result" {
    write_init_task TEST-0001 bad-qa
    invoke_cli bad-qa --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 1 ] \
        && [[ "$(cat "$CASE_OUT")" == *'"result":"INVALID"'*'"diagnostic_codes":["INIT_TASK_INVALID"]'*'"error_count_status":"MEASURED"'* ]]
}

@test "Q&A validator tool failure is not normalized into a JSON result" {
    write_init_task TEST-0001
    local shim="$WORK/no-awk"
    mkdir -p "$shim"
    printf '%s\n' '#!/bin/sh' 'exit 42' > "$shim/awk"
    chmod 700 "$shim/awk"
    CLI_PATH_OVERRIDE="$shim:/usr/bin:/bin" invoke_cli awk-unavailable --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 2 ] \
        && ! grep -q '"schema"' "$CASE_OUT" \
        && [ "$(cat "$CASE_STATUS_FILE")" = 2 ]
}

@test "summary suppresses report prose and hostile validation values" {
    write_init_task TEST-0001 hostile
    invoke_cli hostile --task TEST-0001 --root "$WORK" --report --summary-json
    [ "$CASE_STATUS" -eq 1 ] \
        && [ ! -s "$CASE_ERR" ] \
        && ! grep -q 'PRIVATE_SENTINEL_7fa2d1\|TEST-0001\|init-summary-' "$CASE_OUT" \
        && [[ "$(cat "$CASE_OUT")" == *'"result":"INVALID"'* ]]
}

@test "summary rejects advisory all mode and missing task values outside JSON mode" {
    invoke_cli all-summary --all --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 2 ] \
        && ! grep -q '"schema"' "$CASE_OUT" \
        && invoke_cli missing-value --task --summary-json \
        && [ "$CASE_STATUS" -eq 2 ] \
        && ! grep -q '"schema"' "$CASE_OUT" \
        && invoke_cli absent-task-value --task \
        && [ "$CASE_STATUS" -eq 2 ] \
        && invoke_cli missing-root --task TEST-0001 --root \
        && [ "$CASE_STATUS" -eq 2 ] \
        && invoke_cli missing-date --all --today \
        && [ "$CASE_STATUS" -eq 2 ] \
        && invoke_cli unknown --task TEST-0001 --root "$WORK" --not-an-option \
        && [ "$CASE_STATUS" -eq 2 ] \
        && ! grep -q '"schema"' "$CASE_OUT"
}

@test "help advertises the optional summary flag" {
    invoke_cli help --help
    [ "$CASE_STATUS" -eq 0 ] && grep -q -- '--summary-json' "$CASE_OUT"
}

@test "no-flag task and advisory-all behavior retain their existing exit and output" {
    write_init_task TEST-0001
    invoke_cli default-task --task TEST-0001 --root "$WORK"
    [ "$CASE_STATUS" -eq 0 ] \
        && [ ! -s "$CASE_OUT" ] \
        && [ ! -s "$CASE_ERR" ] \
        && CLI_CWD="$WORK" invoke_cli default-root-task --task TEST-0001 \
        && [ "$CASE_STATUS" -eq 0 ] \
        && [ ! -s "$CASE_OUT" ] \
        && write_init_task TEST-0001 missing-append \
        && invoke_cli default-report --task TEST-0001 --root "$WORK" --report \
        && [ "$CASE_STATUS" -eq 1 ] \
        && grep -q 'validation error(s)' "$CASE_OUT" \
        && grep -q 'missing required heading' "$CASE_ERR" \
        && printf '%s\n' '---' 'task_id: TEST-0002' 'status: in_progress' 'created: 2026-11-02' '---' > "$WORK/datarim/tasks/TEST-0002-task-description.md" \
        && FIXTURE_PATH="$WORK/datarim/tasks/TEST-0002-task-description.md" \
        && CLI_CWD="$WORK" invoke_cli advisory-all --all --today 2026-11-02 \
        && [ "$CASE_STATUS" -eq 0 ] \
        && [ "$(cat "$CASE_OUT")" = 'info: TEST-0002 init-task missing (task age 0d; rolling 30d soft window)' ] \
        && [ ! -s "$CASE_ERR" ]
}

@test "heading grep execution error exits internally without a JSON result" {
    write_init_task TEST-0001
    local shim="$WORK/grep-heading-error"
    mkdir -p "$shim"
    cat > "$shim/grep" <<'SH'
#!/bin/sh
if [ "${1:-}" = "-q" ] && [ "${2:-}" = '^## Append-log' ]; then
    exit 42
fi
exec /usr/bin/grep "$@"
SH
    chmod 700 "$shim/grep"
    CLI_PATH_OVERRIDE="$shim:/usr/bin:/bin" invoke_cli heading-grep-error --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 2 ] \
        && [ ! -s "$CASE_OUT" ] \
        && [ "$(cat "$CASE_STATUS_FILE")" = 2 ] \
        && assert_case_immutable
}

@test "frontmatter extraction execution error exits internally without a JSON result" {
    write_init_task TEST-0001
    local shim="$WORK/awk-extraction-error"
    mkdir -p "$shim"
    printf '%s\n' '#!/bin/sh' 'exit 42' > "$shim/awk"
    chmod 700 "$shim/awk"
    CLI_PATH_OVERRIDE="$shim:/usr/bin:/bin" invoke_cli frontmatter-awk-error --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 2 ] \
        && [ ! -s "$CASE_OUT" ] \
        && [ "$(cat "$CASE_STATUS_FILE")" = 2 ] \
        && assert_case_immutable
}

@test "Q&A diagnostic count execution error exits internally without a JSON result" {
    write_init_task TEST-0001 bad-qa
    local shim="$WORK/grep-count-error"
    mkdir -p "$shim"
    cat > "$shim/grep" <<'SH'
#!/bin/sh
if [ "${1:-}" = "-c" ]; then
    exit 42
fi
exec /usr/bin/grep "$@"
SH
    chmod 700 "$shim/grep"
    CLI_PATH_OVERRIDE="$shim:/usr/bin:/bin" invoke_cli qa-count-grep-error --task TEST-0001 --root "$WORK" --summary-json
    [ "$CASE_STATUS" -eq 2 ] \
        && [ ! -s "$CASE_OUT" ] \
        && [ "$(cat "$CASE_STATUS_FILE")" = 2 ] \
        && assert_case_immutable
}

@test "missing-heading no-summary output matches the frozen contract" {
    write_init_task TEST-0001 missing-brief || return 1
    local expected_err="$WORK/expected.stderr"
    invoke_cli current-no-summary --task TEST-0001 --root "$WORK" || return 1
    [ "$CASE_STATUS" -eq 1 ] || return 1
    [ ! -s "$CASE_OUT" ] || return 1
    printf "ERROR: %s: missing required heading '## Operator brief (verbatim)'\n" "$FIXTURE_PATH" > "$expected_err" || return 1
    cmp -s "$expected_err" "$CASE_ERR" || return 1
    assert_case_immutable || return 1
}
