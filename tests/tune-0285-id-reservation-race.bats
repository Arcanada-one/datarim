#!/usr/bin/env bats
# tune-0285-id-reservation-race.bats
#
# TUNE-0285 — `/dr-init` race-window hardening.
#
# Verifies the atomic reservation marker added to next-free-id.sh that closes
# the workspace-shared TOCTOU race documented in reflection-TUNE-0280 § 1:
# two parallel /dr-init sessions must never select the same task ID even when
# neither has written its first artifact yet.
#
# Group R — reservation mechanics (functional).
# Group T — contract: mechanism + reversibility documented.

HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"
CMDS_DIR="${BATS_TEST_DIRNAME}/../commands"

RES_DIR_REL="datarim/.id-reservations"
R01_DIAGNOSTIC_TOTAL_LIMIT=66176
R01_TRACE_BYTES_PER_CHILD=32768
R01_TRACE_RECORD_BYTES=512
R01_TRACE_DATA_RECORDS=63
R01_TRACE_OBSERVED_RECORDS=65
R01_DIAGNOSTIC_FRAME_LIMIT=640
R01_TRACE_BUFFER=''
R01_FRAME_BUFFER=''
R01_DIAGNOSTIC_BUFFER=''

_r01_trace_record_is_valid() {
    local line="$1" LC_ALL=C
    local events='(reserve_dir_create|gc_age|gc_remove|gc_remove_result|claim_probe|candidate_probe|initial_mkdir|stale_age|stale_predicate|reclaim_decision|reclaim_remove|reclaim_remove_result|reclaim_mkdir|stamp_epoch|stamp_pid|publish_marker|stdout_attempt|release_remove|release_remove_result)'
    local candidate='(TUNE-[0-9]{4}|unknown)'
    local identity='([0-9]+:[0-9]+|unknown)'
    local epoch='([0-9]+|unknown)'
    local age='(-?[0-9]+|unknown)'
    local ttl='([0-9]+|unknown)'
    local operation_rc='([0-9]+|unknown)'
    local decisions='(none|created|fresh|stale|absent|lost|claimed_names|claimed_live|claimed_tasks|claimed_backlog|claimed_init_lock|claimed_reservation|unclaimed|published|attempt|failed|released|succeeded|unknown)'
    local monotonic='([0-9]+|unknown)'
    local schema="^([1-9][0-9]*)\\|([0-9]+)\\|${events}\\|${candidate}\\|${identity}\\|${identity}\\|${identity}\\|${epoch}\\|${age}\\|${ttl}\\|${operation_rc}\\|${decisions}\\|${monotonic}$"
    (( ${#line} + 1 <= R01_TRACE_RECORD_BYTES )) || return 1
    [[ "$line" =~ $schema ]]
}

_r01_buffer_trace_record() {
    local line="$1" LC_ALL=C
    local bytes=$((${#line} + 1))
    (( bytes <= R01_TRACE_RECORD_BYTES )) || return 1
    (( ${#R01_TRACE_BUFFER} + bytes <= R01_TRACE_BYTES_PER_CHILD )) || return 1
    R01_TRACE_BUFFER+="${line}"$'\n'
    return 0
}

_r01_buffer_frame_line() {
    local line="$1" LC_ALL=C
    local bytes=$((${#line} + 1))
    (( ${#R01_FRAME_BUFFER} + bytes <= R01_DIAGNOSTIC_FRAME_LIMIT )) || return 1
    R01_FRAME_BUFFER+="${line}"$'\n'
    return 0
}

_r01_append_frame_line() {
    local line="$1"
    _r01_buffer_frame_line "$line" || return 1
    R01_DIAGNOSTIC_BUFFER+="${line}"$'\n'
}

_r01_stderr_summary() {
    local stderr_file="$1" stderr_text warning_re LC_ALL=C
    if [[ ! -e "$stderr_file" ]]; then
        printf 'unavailable'
        return 0
    fi
    if [[ ! -s "$stderr_file" ]]; then
        printf 'empty'
        return 0
    fi
    warning_re='^WARNING: ID (TUNE-[0-9]{4}) (already claimed \(parallel-session race\)|reserved by a parallel session) — auto-bumping to next free ID$'
    # Read at most 256 bytes. Long or unknown stderr is summarized without
    # retaining any of its content.
    IFS= read -r -N 256 stderr_text < "$stderr_file" || :
    (( ${#stderr_text} < 256 )) || { printf 'other-omitted'; return 0; }
    stderr_text="${stderr_text%$'\n'}"
    if [[ "$stderr_text" =~ $warning_re ]]; then
        printf 'warning:%s' "${BASH_REMATCH[1]}"
    else
        printf 'other-omitted'
    fi
}

_r01_append_trace_block() {
    local trace_file="$1" child="$2" record seen=0 emitted=0 omitted=0 state=complete
    local original_buffer="$R01_TRACE_BUFFER" read_status
    R01_TRACE_BUFFER=''
    if [[ -f "$trace_file" && -r "$trace_file" ]]; then
        if while (( seen < R01_TRACE_OBSERVED_RECORDS )); do
            record=''
            if IFS= read -r record; then read_status=0; else read_status=1; fi
            [[ -n "$record" || $read_status -eq 0 ]] || break
            seen=$((seen + 1))
            if (( emitted >= R01_TRACE_DATA_RECORDS )) || (( read_status != 0 )); then
                omitted=$((omitted + 1))
                if (( read_status != 0 )); then state=unknown; else state=capped; fi
            elif _r01_trace_record_is_valid "$record"; then
                if _r01_buffer_trace_record "$record"; then
                    emitted=$((emitted + 1))
                else
                    omitted=$((omitted + 1))
                    state=capped
                fi
            else
                omitted=$((omitted + 1))
            fi
            (( read_status == 0 )) || break
        done < "$trace_file" 2>/dev/null; then
            :
        else
            R01_TRACE_BUFFER="$original_buffer"
            omitted=0
            state=unavailable
        fi
        if (( seen == R01_TRACE_OBSERVED_RECORDS )); then state=capped; fi
    else
        state=unavailable
    fi
    _R01_TRACE_OMITTED="$omitted"
    _R01_TRACE_STATE="$state"
    if (( omitted > 0 )) || [[ "$state" != complete ]]; then
        local overflow_line="overflow|omitted=${omitted}|state=${state}"
        _r01_buffer_trace_record "$overflow_line" || {
            R01_TRACE_BUFFER="$original_buffer"
            return 1
        }
    fi
    return 0
}

_r01_emit_failure_diagnostics() {
    local id1="$1" status1="$2" err1="$3" trace1="$4"
    local id2="$5" status2="$6" err2="$7" trace2="$8"
    local summary_id1="$id1" summary_id2="$id2" summary_status1="$status1" summary_status2="$status2"
    local stderr1 stderr2 LC_ALL=C

    [[ "$summary_id1" =~ ^TUNE-[0-9]{4}$ ]] || summary_id1=unknown
    [[ "$summary_id2" =~ ^TUNE-[0-9]{4}$ ]] || summary_id2=unknown
    if [[ ! "$summary_status1" =~ ^(0|[1-9][0-9]{0,2})$ ]] || (( summary_status1 > 255 )); then summary_status1=unknown; fi
    if [[ ! "$summary_status2" =~ ^(0|[1-9][0-9]{0,2})$ ]] || (( summary_status2 > 255 )); then summary_status2=unknown; fi
    stderr1="$(_r01_stderr_summary "$err1")"
    stderr2="$(_r01_stderr_summary "$err2")"

    R01_TRACE_BUFFER=''
    _r01_append_trace_block "$trace1" 1 || return 0
    local omitted1="$_R01_TRACE_OMITTED"
    local state1="$_R01_TRACE_STATE"
    local trace1_block="$R01_TRACE_BUFFER"
    R01_TRACE_BUFFER=''
    _r01_append_trace_block "$trace2" 2 || return 0
    local omitted2="$_R01_TRACE_OMITTED"
    local state2="$_R01_TRACE_STATE"
    local trace2_block="$R01_TRACE_BUFFER"

    R01_FRAME_BUFFER=''
    R01_DIAGNOSTIC_BUFFER=''
    _r01_append_frame_line 'R01_DIAGNOSTIC/1' || return 0
    _r01_append_frame_line "child=1 id=${summary_id1} exit=${summary_status1} stderr=${stderr1} trace_omitted=${omitted1} trace_state=${state1}" || return 0
    _r01_append_frame_line 'trace=1:begin' || return 0
    R01_DIAGNOSTIC_BUFFER+="${trace1_block}"
    _r01_append_frame_line 'trace=1:end' || return 0
    _r01_append_frame_line "child=2 id=${summary_id2} exit=${summary_status2} stderr=${stderr2} trace_omitted=${omitted2} trace_state=${state2}" || return 0
    _r01_append_frame_line 'trace=2:begin' || return 0
    R01_DIAGNOSTIC_BUFFER+="${trace2_block}"
    _r01_append_frame_line 'trace=2:end' || return 0
    _r01_append_frame_line 'R01_DIAGNOSTIC_END' || return 0
    (( ${#R01_DIAGNOSTIC_BUFFER} <= R01_DIAGNOSTIC_TOTAL_LIMIT )) || return 0

    # One bounded, best-effort write to Bats' failure stream. A broken FD3 is
    # intentionally unable to alter the result of the original assertion.
    if printf '%s' "$R01_DIAGNOSTIC_BUFFER" 2>/dev/null >&3; then :; else :; fi
    return 0
}

setup() {
    FIXTURE_DIR="$(mktemp -d)"
    mkdir -p "${FIXTURE_DIR}/datarim"
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    # Ledger-presence guard: the helper now fails CLOSED on a root carrying
    # neither datarim/tasks.md nor datarim/backlog.md. An empty ledger keeps
    # every fixture semantically identical (no rows) while satisfying it.
    : > "${FIXTURE_DIR}/datarim/tasks.md"
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

# ── Group R — reservation mechanics ──────────────────────────────────────────

# R01: the two-session race — two concurrent invocations against one root MUST
# return DISTINCT IDs. This is the core defect TUNE-0285 closes.
@test "R01: two concurrent invocations return distinct IDs" {
    OUT1="$(mktemp)"; OUT2="$(mktemp)"
    ERR1="${FIXTURE_DIR}/child-1.stderr"; ERR2="${FIXTURE_DIR}/child-2.stderr"
    TRACE1="${FIXTURE_DIR}/child-1.trace"; TRACE2="${FIXTURE_DIR}/child-2.trace"
    _D5_TUNE0285_TRACE=1 bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${OUT1}" 2>"${ERR1}" 9>"${TRACE1}" &
    P1=$!
    _D5_TUNE0285_TRACE=1 bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${OUT2}" 2>"${ERR2}" 9>"${TRACE2}" &
    P2=$!
    if wait "${P1}"; then STATUS1=0; else STATUS1=$?; fi
    if wait "${P2}"; then STATUS2=0; else STATUS2=$?; fi
    ID1="$(cat "${OUT1}")"; ID2="$(cat "${OUT2}")"
    if [[ -n "${D5_TUNE0285_EVIDENCE_DIR:-}" ]]; then
        mkdir -p "${D5_TUNE0285_EVIDENCE_DIR}"
        cp "${OUT1}" "${D5_TUNE0285_EVIDENCE_DIR}/child-1.stdout"
        cp "${OUT2}" "${D5_TUNE0285_EVIDENCE_DIR}/child-2.stdout"
        cp "${ERR1}" "${D5_TUNE0285_EVIDENCE_DIR}/child-1.stderr"
        cp "${ERR2}" "${D5_TUNE0285_EVIDENCE_DIR}/child-2.stderr"
        cp "${TRACE1}" "${D5_TUNE0285_EVIDENCE_DIR}/child-1.trace"
        cp "${TRACE2}" "${D5_TUNE0285_EVIDENCE_DIR}/child-2.trace"
        printf '%s\n' "$STATUS1" > "${D5_TUNE0285_EVIDENCE_DIR}/child-1.exit"
        printf '%s\n' "$STATUS2" > "${D5_TUNE0285_EVIDENCE_DIR}/child-2.exit"
    fi
    rm -f "${OUT1}" "${OUT2}"
    [ "$STATUS1" -eq 0 ]
    [ "$STATUS2" -eq 0 ]
    # The allocator may emit one established contention warning; diagnostics
    # stay on the separate trace FD, and any other stderr remains a failure.
    for ERR_FILE in "${ERR1}" "${ERR2}"; do
        awk '
            NR == 1 && /^WARNING: ID TUNE-[0-9][0-9][0-9][0-9] (already claimed \(parallel-session race\)|reserved by a parallel session) — auto-bumping to next free ID$/ { next }
            { exit 1 }
            END { if (NR > 1) exit 1 }
        ' "${ERR_FILE}"
    done
    [ -s "${TRACE1}" ]
    [ -s "${TRACE2}" ]
    [ "$(wc -l < "${TRACE1}")" -le 64 ]
    [ "$(wc -l < "${TRACE2}")" -le 64 ]
    awk -F'|' 'length($0) > 512 || NF != 13 || $13 !~ /^([0-9]+|unknown)$/ { exit 1 }' "${TRACE1}"
    awk -F'|' 'length($0) > 512 || NF != 13 || $13 !~ /^([0-9]+|unknown)$/ { exit 1 }' "${TRACE2}"
    grep -q '|stdout_attempt|' "${TRACE1}"
    grep -q '|stdout_attempt|' "${TRACE2}"
    # Both must be well-formed and different
    [[ "${ID1}" =~ ^TUNE-[0-9]{4}$ ]]
    [[ "${ID2}" =~ ^TUNE-[0-9]{4}$ ]]
    if [[ "${ID1}" == "${ID2}" ]]; then
        _r01_emit_failure_diagnostics "$ID1" "$STATUS1" "${ERR1}" "${TRACE1}" \
            "$ID2" "$STATUS2" "${ERR2}" "${TRACE2}"
    fi
    [ "${ID1}" != "${ID2}" ]
}

@test "R01 diagnostic output is bounded, whole-record validated, and failure-only" {
    OUT1="${FIXTURE_DIR}/child-1.stdout"
    OUT2="${FIXTURE_DIR}/child-2.stdout"
    ERR1="${FIXTURE_DIR}/child-1.stderr"
    ERR2="${FIXTURE_DIR}/child-2.stderr"
    TRACE1="${FIXTURE_DIR}/child-1.trace"
    TRACE2="${FIXTURE_DIR}/child-2.trace"
    DIAGNOSTIC="${FIXTURE_DIR}/diagnostic.fd3"
    CALLER_STDOUT="${FIXTURE_DIR}/diagnostic.stdout"
    CALLER_STDERR="${FIXTURE_DIR}/diagnostic.stderr"
    printf 'TUNE-0001\n' > "$OUT1"
    printf 'TUNE-0001\n' > "$OUT2"
    printf 'WARNING: ID TUNE-0001 reserved by a parallel session — auto-bumping to next free ID\n' > "$ERR1"
    printf 'PRIVATE_PATH=/hidden/fixture\n' > "$ERR2"
    printf '1|123|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|100\n' > "$TRACE1"
    printf 'malformed|PRIVATE_PATH=/hidden/fixture\n' >> "$TRACE1"
    printf '2|123|secret_event|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|101\n' >> "$TRACE1"
    printf '3|123|initial_mkdir|TUNE-0001|../hidden|1:3|1:4|unknown|unknown|1800|0|created|102\n' >> "$TRACE1"
    printf '4|123|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|NOW\n' >> "$TRACE1"
    printf '5|123|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|103|extra\n' >> "$TRACE1"
    printf '%0513d\n' 7 >> "$TRACE1"
    : > "$TRACE2"
    for ((record=1; record<=65; record++)); do
        printf '%s|124|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|%s\n' \
            "$record" "$record" >> "$TRACE2"
    done
    if _r01_emit_failure_diagnostics TUNE-0001 0 "$ERR1" "$TRACE1" TUNE-0001 0 "$ERR2" "$TRACE2" \
        > "$CALLER_STDOUT" 2> "$CALLER_STDERR" 3> "$DIAGNOSTIC"; then
        EMIT_STATUS=0
    else
        EMIT_STATUS=$?
    fi
    [ "$EMIT_STATUS" -eq 0 ] \
        && [ ! -s "$CALLER_STDOUT" ] \
        && [ ! -s "$CALLER_STDERR" ] \
        && grep -q '^child=1 id=TUNE-0001 exit=0 stderr=warning:TUNE-0001 trace_omitted=6 trace_state=complete$' "$DIAGNOSTIC" \
        && grep -q '^child=2 id=TUNE-0001 exit=0 stderr=other-omitted trace_omitted=2 trace_state=capped$' "$DIAGNOSTIC" \
        && grep -q '^overflow|omitted=6|state=complete$' "$DIAGNOSTIC" \
        && grep -q '^overflow|omitted=2|state=capped$' "$DIAGNOSTIC" \
        && grep -q '^1|123|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|100$' "$DIAGNOSTIC" \
        && { record_count="$(grep -c '^[0-9]' "$DIAGNOSTIC")"; [ "$record_count" -eq 64 ] || { printf 'expected 64 emitted trace rows, got %s\n' "$record_count"; cat "$DIAGNOSTIC"; return 1; }; } \
        && ! grep -q 'PRIVATE_PATH\|/hidden/fixture\|malformed\|secret_event\|NOW\|extra' "$DIAGNOSTIC" \
        && [ "$(wc -c < "$DIAGNOSTIC")" -le "$R01_DIAGNOSTIC_TOTAL_LIMIT" ]
}

@test "R01 trace summary counts only observed omissions and labels unreadable input" {
    TRACE="${FIXTURE_DIR}/trace-summary.trace"
    R01_TRACE_BUFFER=''
    for ((record=1; record<=64; record++)); do
        printf '%s|124|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|%s\n' \
            "$record" "$record" >> "$TRACE"
    done
    _r01_append_trace_block "$TRACE" 1
    [ "$_R01_TRACE_OMITTED" -eq 1 ]
    [ "$_R01_TRACE_STATE" = capped ]
    [ "$(grep -c '^[0-9]' <<< "$R01_TRACE_BUFFER")" -eq 63 ]
    grep -q '^overflow|omitted=1|state=capped$' <<< "$R01_TRACE_BUFFER"

    printf '65|124|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|65\n' >> "$TRACE"
    R01_TRACE_BUFFER=''
    _r01_append_trace_block "$TRACE" 1
    [ "$_R01_TRACE_OMITTED" -eq 2 ]
    [ "$_R01_TRACE_STATE" = capped ]
    [ "$(grep -c '^[0-9]' <<< "$R01_TRACE_BUFFER")" -eq 63 ]
    grep -q '^overflow|omitted=2|state=capped$' <<< "$R01_TRACE_BUFFER"

    printf '66|124|not-valid-and-beyond-observation|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|66\n' >> "$TRACE"
    R01_TRACE_BUFFER=''
    _r01_append_trace_block "$TRACE" 1
    [ "$_R01_TRACE_OMITTED" -eq 2 ]
    [ "$_R01_TRACE_STATE" = capped ]

    mkdir "${FIXTURE_DIR}/unreadable-trace-directory"
    R01_TRACE_BUFFER=''
    _r01_append_trace_block "${FIXTURE_DIR}/unreadable-trace-directory" 1
    [ "$_R01_TRACE_OMITTED" -eq 0 ]
    [ "$_R01_TRACE_STATE" = unavailable ]
    grep -q '^overflow|omitted=0|state=unavailable$' <<< "$R01_TRACE_BUFFER"
}

@test "R01 diagnostic sink failure does not replace the distinct-ID assertion" {
    ERR="${FIXTURE_DIR}/broken-fd3.stderr"
    TRACE="${FIXTURE_DIR}/broken-fd3.trace"
    printf 'TUNE-0001\n' > "${FIXTURE_DIR}/child.stdout"
    : > "${FIXTURE_DIR}/child.stderr"
    printf '1|123|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|100\n' > "$TRACE"
    if (
        _r01_emit_failure_diagnostics TUNE-0001 0 "${FIXTURE_DIR}/child.stderr" "$TRACE" \
            TUNE-0001 0 "${FIXTURE_DIR}/child.stderr" "$TRACE" 3>&-
        [ TUNE-0001 != TUNE-0001 ]
    ) > /dev/null 2> "$ERR"; then
        ASSERTION_STATUS=0
    else
        ASSERTION_STATUS=$?
    fi
    [ "$ASSERTION_STATUS" -eq 1 ] && [ ! -s "$ERR" ]
}

@test "R01 monotonic clock records shared values and stops sampling when unavailable" {
    SPY_BIN="${FIXTURE_DIR}/clock-spy"
    mkdir -p "$SPY_BIN"
    cat > "${SPY_BIN}/perl" <<'EOF'
#!/usr/bin/env bash
if [[ "${D5_PERL_FAIL:-0}" == "1" ]]; then
    exit 1
fi
value=0
[[ -r "$D5_CLOCK_COUNTER" ]] && read -r value < "$D5_CLOCK_COUNTER"
value=$((value + 1))
printf '%s\n' "$value" > "$D5_CLOCK_COUNTER"
printf '%s\n' "$value"
EOF
    chmod +x "${SPY_BIN}/perl"

    VALID_ROOT="${FIXTURE_DIR}/clock-valid"
    FALLBACK_ROOT="${FIXTURE_DIR}/clock-fallback"
    mkdir -p "${VALID_ROOT}/datarim" "${FALLBACK_ROOT}/datarim"
    : > "${VALID_ROOT}/datarim/tasks.md"
    : > "${FALLBACK_ROOT}/datarim/tasks.md"
    VALID_OUT="${FIXTURE_DIR}/clock-valid.stdout"
    VALID_ERR="${FIXTURE_DIR}/clock-valid.stderr"
    VALID_TRACE="${FIXTURE_DIR}/clock-valid.trace"
    VALID_COUNTER="${FIXTURE_DIR}/clock-valid.counter"
    FALLBACK_OUT="${FIXTURE_DIR}/clock-fallback.stdout"
    FALLBACK_ERR="${FIXTURE_DIR}/clock-fallback.stderr"
    FALLBACK_TRACE="${FIXTURE_DIR}/clock-fallback.trace"
    if _D5_TUNE0285_TRACE=1 D5_PERL_FAIL=0 D5_CLOCK_COUNTER="${VALID_COUNTER}" PATH="${SPY_BIN}:${PATH}" \
        bash "${HELPER}" TUNE "${VALID_ROOT}" > "$VALID_OUT" 2> "$VALID_ERR" 9> "$VALID_TRACE"; then
        VALID_STATUS=0
    else
        VALID_STATUS=$?
    fi
    if _D5_TUNE0285_TRACE=1 D5_PERL_FAIL=1 D5_CLOCK_COUNTER="${FIXTURE_DIR}/unused-counter" PATH="${SPY_BIN}:${PATH}" \
        bash "${HELPER}" TUNE "${FALLBACK_ROOT}" > "$FALLBACK_OUT" 2> "$FALLBACK_ERR" 9> "$FALLBACK_TRACE"; then
        FALLBACK_STATUS=0
    else
        FALLBACK_STATUS=$?
    fi
    [ "$VALID_STATUS" -eq 0 ] \
        && [ "$FALLBACK_STATUS" -eq 0 ] \
        && [ "$(cat "$VALID_OUT")" = "TUNE-0001" ] \
        && [ "$(cat "$FALLBACK_OUT")" = "TUNE-0001" ] \
        && [ ! -s "$VALID_ERR" ] \
        && [ ! -s "$FALLBACK_ERR" ] \
        && cmp -s "$VALID_OUT" "$FALLBACK_OUT" \
        && cmp -s "$VALID_ERR" "$FALLBACK_ERR" \
        && awk -F'|' 'NF != 13 || $13 !~ /^[0-9]+$/ || (NR > 1 && $13 <= previous) { exit 1 } { previous=$13 } END { if (NR == 0) exit 1 }' "$VALID_TRACE" \
        && [ ! -s "$FALLBACK_TRACE" ]
}

@test "R08: diagnostic-off path does not read filesystem identities" {
    STAT_REAL="$(command -v stat)"
    PERL_REAL="$(command -v perl)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    STAT_CALLED="${FIXTURE_DIR}/stat-called"
    MONOTONIC_CALLED="${FIXTURE_DIR}/monotonic-called"
    OUT="${FIXTURE_DIR}/disabled.stdout"
    ERR="${FIXTURE_DIR}/disabled.stderr"
    mkdir -p "${SPY_BIN}"
    cat > "${SPY_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
: > "$D5_STAT_CALLED"
exec "$D5_STAT_REAL" "$@"
EOF
    chmod +x "${SPY_BIN}/stat"
    cat > "${SPY_BIN}/perl" <<'EOF'
#!/usr/bin/env bash
: > "$D5_MONOTONIC_CALLED"
exec "$D5_PERL_REAL" "$@"
EOF
    chmod +x "${SPY_BIN}/perl"
    unset _D5_TUNE0285_TRACE
    if PATH="${SPY_BIN}:${PATH}" D5_STAT_CALLED="${STAT_CALLED}" D5_STAT_REAL="${STAT_REAL}" \
        D5_MONOTONIC_CALLED="${MONOTONIC_CALLED}" D5_PERL_REAL="${PERL_REAL}" \
        bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0001" ]
    [ ! -s "${ERR}" ]
    [ ! -e "${STAT_CALLED}" ]
    [ ! -e "${MONOTONIC_CALLED}" ]
}

@test "R09: a closed diagnostic sink cannot change allocation result" {
    OUT="${FIXTURE_DIR}/closed-sink.stdout"
    ERR="${FIXTURE_DIR}/closed-sink.stderr"
    if _D5_TUNE0285_TRACE=1 bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" \
        >"${OUT}" 2>"${ERR}" 9>&-; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0001" ]
    [ ! -s "${ERR}" ]
}

@test "R10: a full trace cap stops later identity stats" {
    LOW_CAP_HELPER="${FIXTURE_DIR}/next-free-id-low-cap.sh"
    STAT_REAL="$(command -v stat)"
    PERL_REAL="$(command -v perl)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    STAT_CALLS="${FIXTURE_DIR}/stat-calls"
    MONOTONIC_CALLS="${FIXTURE_DIR}/monotonic-calls"
    OUT="${FIXTURE_DIR}/cap.stdout"
    ERR="${FIXTURE_DIR}/cap.stderr"
    TRACE="${FIXTURE_DIR}/cap.trace"
    sed 's/^_D5_TRACE_EVENT_LIMIT=64$/_D5_TRACE_EVENT_LIMIT=4/' "${HELPER}" > "${LOW_CAP_HELPER}"
    [ "$(grep -c '^_D5_TRACE_EVENT_LIMIT=4$' "${LOW_CAP_HELPER}")" -eq 1 ]
    chmod +x "${LOW_CAP_HELPER}"
    mkdir -p "${SPY_BIN}"
    cat > "${SPY_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
printf 'stat\n' >> "$D5_STAT_CALLS"
exec "$D5_STAT_REAL" "$@"
EOF
    chmod +x "${SPY_BIN}/stat"
    cat > "${SPY_BIN}/perl" <<'EOF'
#!/usr/bin/env bash
printf 'clock\n' >> "$D5_MONOTONIC_CALLS"
exec "$D5_PERL_REAL" "$@"
EOF
    chmod +x "${SPY_BIN}/perl"
    : > "${STAT_CALLS}"
    : > "${MONOTONIC_CALLS}"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_STAT_CALLS="${STAT_CALLS}" D5_STAT_REAL="${STAT_REAL}" \
        D5_MONOTONIC_CALLS="${MONOTONIC_CALLS}" D5_PERL_REAL="${PERL_REAL}" \
        bash "${LOW_CAP_HELPER}" "TUNE" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}" 9>"${TRACE}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0001" ]
    [ ! -s "${ERR}" ]
    [ "$(wc -l < "${TRACE}")" -eq 4 ]
    [ "$(sed -n '1p' "${TRACE}" | cut -d'|' -f3)" = "reserve_dir_create" ]
    [ "$(sed -n '2p' "${TRACE}" | cut -d'|' -f3)" = "stale_predicate" ]
    [ "$(sed -n '3p' "${TRACE}" | cut -d'|' -f3)" = "claim_probe" ]
    [ "$(sed -n '4p' "${TRACE}" | cut -d'|' -f3)" = "candidate_probe" ]
    ! grep -qE '\|(initial_mkdir|reclaim_mkdir)\|' "${TRACE}"
    stat_count="$(wc -l < "${STAT_CALLS}")"
    clock_count="$(wc -l < "${MONOTONIC_CALLS}")"
    [ "$stat_count" -eq 2 ] || { printf 'expected 2 stat probes, observed %s\n' "$stat_count" >&2; return 1; }
    [ "$clock_count" -eq 9 ] || { printf 'expected 9 clock checks, observed %s\n' "$clock_count" >&2; return 1; }
    [ "$(wc -l < "${TRACE}")" -eq 4 ]
    if [[ -n "${D5_TUNE0285_EVIDENCE_DIR:-}" ]]; then
        cp "${TRACE}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.trace"
        cp "${STAT_CALLS}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.stat-calls"
        cp "${OUT}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.stdout"
        cp "${ERR}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.stderr"
    fi
}

@test "R01 soft sampling cutoff stops probes at the exact five-second boundary" {
    SPY_BIN="${FIXTURE_DIR}/soft-cutoff-bin"
    STAT_REAL="$(command -v stat)"
    PERL_CALLS="${FIXTURE_DIR}/soft-cutoff-clock-calls"
    STAT_CALLS="${FIXTURE_DIR}/soft-cutoff-stat-calls"
    OUT="${FIXTURE_DIR}/soft-cutoff.stdout"
    ERR="${FIXTURE_DIR}/soft-cutoff.stderr"
    TRACE="${FIXTURE_DIR}/soft-cutoff.trace"
    mkdir -p "$SPY_BIN"
    cat > "${SPY_BIN}/perl" <<'EOF'
#!/usr/bin/env bash
count=0
[[ -r "$D5_PERL_CALLS" ]] && read -r count < "$D5_PERL_CALLS"
count=$((count + 1))
printf '%s\n' "$count" > "$D5_PERL_CALLS"
case "$count" in
    1) printf '0\n' ;;
    2) printf '5000000000\n' ;;
    *) printf '5000000001\n' ;;
esac
EOF
    cat > "${SPY_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
printf 'stat\n' >> "$D5_STAT_CALLS"
exec "$D5_STAT_REAL" "$@"
EOF
    chmod +x "${SPY_BIN}/perl" "${SPY_BIN}/stat"
    : > "$PERL_CALLS"
    : > "$STAT_CALLS"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_PERL_CALLS="$PERL_CALLS" \
        D5_STAT_CALLS="$STAT_CALLS" D5_STAT_REAL="$STAT_REAL" \
        bash "${HELPER}" TUNE "${FIXTURE_DIR}" > "$OUT" 2> "$ERR" 9> "$TRACE"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "$OUT")" = TUNE-0001 ]
    [ ! -s "$ERR" ]
    [ ! -s "$TRACE" ]
    [ "$(cat "$PERL_CALLS")" -eq 2 ]
    [ "$(wc -l < "$STAT_CALLS")" -eq 1 ]
}

@test "R01 summary obeys exact child and framing byte budgets without partial records" {
    TRACE="${FIXTURE_DIR}/max-records.trace"
    DIAGNOSTIC="${FIXTURE_DIR}/max-records.fd3"
    ERR="${FIXTURE_DIR}/max-records.stderr"
    R01_TRACE_BUFFER=''
    long_pid="$(printf '%0438d' 1)"
    record="1|${long_pid}|initial_mkdir|TUNE-0001|1:2|1:3|1:4|unknown|unknown|1800|0|created|100"
    [ "$((${#record} + 1))" -eq 512 ]
    : > "$TRACE"
    for ((index=1; index<=65; index++)); do
        printf '%s\n' "$record" >> "$TRACE"
    done
    _r01_append_trace_block "$TRACE" 1
    [ "$(grep -c '^[0-9]' <<< "$R01_TRACE_BUFFER")" -eq 63 ]
    [ "${#R01_TRACE_BUFFER}" -le "$R01_TRACE_BYTES_PER_CHILD" ]
    grep -q '^overflow|omitted=2|state=capped$' <<< "$R01_TRACE_BUFFER"
    awk 'length($0) + 1 > 512 { exit 1 }' <<< "$R01_TRACE_BUFFER"

    printf 'WARNING: ID TUNE-0001 reserved by a parallel session — auto-bumping to next free ID\n' > "$ERR"
    if _r01_emit_failure_diagnostics TUNE-0001 0 "$ERR" "$TRACE" \
        TUNE-0001 73 "$ERR" "$TRACE" 3> "$DIAGNOSTIC"; then
        EMIT_STATUS=0
    else
        EMIT_STATUS=$?
    fi
    [ "$EMIT_STATUS" -eq 0 ]
    [ "$(wc -c < "$DIAGNOSTIC")" -le "$R01_DIAGNOSTIC_TOTAL_LIMIT" ]
    [ "$(wc -c < "$DIAGNOSTIC")" -gt 64000 ]
    grep -q '^child=1 id=TUNE-0001 exit=0 stderr=warning:TUNE-0001' "$DIAGNOSTIC"
    grep -q '^child=2 id=TUNE-0001 exit=73 stderr=warning:TUNE-0001' "$DIAGNOSTIC"
    grep -q '^overflow|omitted=2|state=capped$' "$DIAGNOSTIC"
}

@test "R11: failed reservation-directory mkdir is unknown and preserves allocation" {
    REAL_MKDIR="$(command -v mkdir)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    FAIL_PATH="${FIXTURE_DIR}/${RES_DIR_REL}"
    OUT="${FIXTURE_DIR}/mkdir-failure.stdout"
    ERR="${FIXTURE_DIR}/mkdir-failure.stderr"
    TRACE="${FIXTURE_DIR}/mkdir-failure.trace"
    mkdir -p "${FAIL_PATH}" "${SPY_BIN}"
    cat > "${SPY_BIN}/mkdir" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-p" && "$2" == "$D5_FAIL_MKDIR_PATH" ]]; then
    exit 73
fi
exec "$D5_REAL_MKDIR" "$@"
EOF
    chmod +x "${SPY_BIN}/mkdir"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_REAL_MKDIR="${REAL_MKDIR}" D5_FAIL_MKDIR_PATH="${FAIL_PATH}" \
        bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}" 9>"${TRACE}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0001" ]
    [ ! -s "${ERR}" ]
    awk -F'|' '$3 == "reserve_dir_create" && $11 == "73" && $12 == "unknown" { good++ }
        END { exit !(good == 1) }' "${TRACE}"
}

@test "R12: failed release rm is unknown and preserves release result" {
    REAL_RM="$(command -v rm)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    TARGET="${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    OUT="${FIXTURE_DIR}/release-failure.stdout"
    ERR="${FIXTURE_DIR}/release-failure.stderr"
    TRACE="${FIXTURE_DIR}/release-failure.trace"
    mkdir -p "${TARGET}" "${SPY_BIN}"
    cat > "${SPY_BIN}/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-rf" && "$2" == "$D5_FAIL_RM_PATH" ]]; then
    exit 73
fi
exec "$D5_REAL_RM" "$@"
EOF
    chmod +x "${SPY_BIN}/rm"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_REAL_RM="${REAL_RM}" D5_FAIL_RM_PATH="${TARGET}" \
        bash "${HELPER}" --release "TUNE-0001" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}" 9>"${TRACE}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ ! -s "${OUT}" ]
    [ ! -s "${ERR}" ]
    [ -d "${TARGET}" ]
    awk -F'|' '$3 == "release_remove_result" && $11 == "73" && $12 == "unknown" { good++ }
        END { exit !(good == 1) }' "${TRACE}"
}

@test "R13: generic marker mkdir failure is not labeled as contention" {
    REAL_MKDIR="$(command -v mkdir)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    TARGET="${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    FAILED_ONCE="${FIXTURE_DIR}/mkdir-failed-once"
    OUT="${FIXTURE_DIR}/marker-mkdir-failure.stdout"
    ERR="${FIXTURE_DIR}/marker-mkdir-failure.stderr"
    TRACE="${FIXTURE_DIR}/marker-mkdir-failure.trace"
    mkdir -p "${SPY_BIN}"
    cat > "${SPY_BIN}/mkdir" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "$D5_FAIL_MKDIR_PATH" && ! -e "$D5_MKDIR_FAILED_ONCE" ]]; then
    : > "$D5_MKDIR_FAILED_ONCE"
    exit 73
fi
exec "$D5_REAL_MKDIR" "$@"
EOF
    chmod +x "${SPY_BIN}/mkdir"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_REAL_MKDIR="${REAL_MKDIR}" \
        D5_FAIL_MKDIR_PATH="${TARGET}" D5_MKDIR_FAILED_ONCE="${FAILED_ONCE}" \
        bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}" 9>"${TRACE}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    if [[ -n "${D5_TUNE0285_EVIDENCE_DIR:-}" ]]; then
        cp "${OUT}" "${D5_TUNE0285_EVIDENCE_DIR}/child.stdout"
        cp "${ERR}" "${D5_TUNE0285_EVIDENCE_DIR}/child.stderr"
        cp "${TRACE}" "${D5_TUNE0285_EVIDENCE_DIR}/child.trace"
        printf '%s\n' "$STATUS" > "${D5_TUNE0285_EVIDENCE_DIR}/child.exit"
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0001" ]
    [ ! -s "${ERR}" ]
    awk -F'|' '$3 == "initial_mkdir" && $11 == "73" && $12 == "unknown" { good++ }
        END { exit !(good == 1) }' "${TRACE}"
    ! awk -F'|' '$3 == "initial_mkdir" && $12 == "lost" { found=1 } END { exit !found }' "${TRACE}"
    if [[ -n "${D5_TUNE0285_EVIDENCE_DIR:-}" ]]; then
        cp "${TRACE}" "${D5_TUNE0285_EVIDENCE_DIR}/marker-mkdir-failure.trace"
        cp "${OUT}" "${D5_TUNE0285_EVIDENCE_DIR}/marker-mkdir-failure.stdout"
        cp "${ERR}" "${D5_TUNE0285_EVIDENCE_DIR}/marker-mkdir-failure.stderr"
        printf '%s\n' "$STATUS" > "${D5_TUNE0285_EVIDENCE_DIR}/marker-mkdir-failure.exit"
    fi
}

@test "R14: failed initial and reclaim mkdir decisions stay unknown with allocator result intact" {
    REAL_MKDIR="$(command -v mkdir)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    TARGET="${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    ATTEMPTS="${FIXTURE_DIR}/mkdir-attempts"
    OUT="${FIXTURE_DIR}/reclaim-mkdir-failure.stdout"
    ERR="${FIXTURE_DIR}/reclaim-mkdir-failure.stderr"
    TRACE="${FIXTURE_DIR}/reclaim-mkdir-failure.trace"
    mkdir -p "${SPY_BIN}"
    cat > "${SPY_BIN}/mkdir" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "$D5_FAIL_MKDIR_PATH" ]]; then
    attempt=0
    [[ -f "$D5_MKDIR_ATTEMPTS" ]] && read -r attempt < "$D5_MKDIR_ATTEMPTS"
    attempt=$((attempt + 1))
    printf '%s\n' "$attempt" > "$D5_MKDIR_ATTEMPTS"
    case "$attempt" in
        1) exit 73 ;;
        2) exit 74 ;;
    esac
fi
exec "$D5_REAL_MKDIR" "$@"
EOF
    chmod +x "${SPY_BIN}/mkdir"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_REAL_MKDIR="${REAL_MKDIR}" \
        D5_FAIL_MKDIR_PATH="${TARGET}" D5_MKDIR_ATTEMPTS="${ATTEMPTS}" \
        bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}" 9>"${TRACE}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0002" ]
    [ "$(cat "${ERR}")" = "WARNING: ID TUNE-0001 reserved by a parallel session — auto-bumping to next free ID" ]
    if [[ -n "${D5_TUNE0285_EVIDENCE_DIR:-}" ]]; then
        cp "${TRACE}" "${D5_TUNE0285_EVIDENCE_DIR}/reclaim-mkdir-failure.trace"
        cp "${OUT}" "${D5_TUNE0285_EVIDENCE_DIR}/reclaim-mkdir-failure.stdout"
        cp "${ERR}" "${D5_TUNE0285_EVIDENCE_DIR}/reclaim-mkdir-failure.stderr"
        printf '%s\n' "$STATUS" > "${D5_TUNE0285_EVIDENCE_DIR}/reclaim-mkdir-failure.exit"
    fi
    awk -F'|' '$3 == "initial_mkdir" && $11 == "73" && $12 == "unknown" { initial++ }
        $3 == "reclaim_mkdir" && $11 == "74" && $12 == "unknown" { reclaim++ }
        $3 == "initial_mkdir" && $11 != 0 && $12 ~ /^(created|lost|reclaimed|released)$/ { bad++ }
        $3 == "reclaim_mkdir" && $11 != 0 && $12 ~ /^(created|lost|reclaimed|released)$/ { bad++ }
        END { exit !(initial == 1 && reclaim == 1 && bad == 0) }' "${TRACE}"
}

# R02: a FRESH reservation marker is treated as claimed → selection auto-bumps.
# The auto-bump warning goes to stderr, so capture stdout separately (the
# bump warning would otherwise pollute bats `run` $output).
@test "R02: fresh reservation marker forces an auto-bump" {
    mkdir -p "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    date +%s > "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001/epoch"
    OUT="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${OUT}" 2>/dev/null
    STATUS=$?
    CHOSEN="$(cat "${OUT}")"; rm -f "${OUT}"
    [ "$STATUS" -eq 0 ]
    [ "$CHOSEN" = "TUNE-0002" ]
}

# R03: explicit --release removes the marker; the ID is selectable again.
@test "R03: --release frees a reserved ID" {
    # First selection reserves TUNE-0001
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]
    [ -d "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001" ]
    # Release it
    run bash "${HELPER}" --release "TUNE-0001" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ ! -d "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001" ]
    # Now TUNE-0001 is selectable again (no real-surface claim exists)
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]
}

# R04: a STALE reservation (epoch older than TTL) is reclaimed, not blocking.
@test "R04: stale reservation is reclaimed (default TTL)" {
    mkdir -p "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    echo "1" > "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001/epoch"  # epoch=1 → ancient
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]
}

# R05: DATARIM_ID_RESERVATION_TTL override is honoured.
@test "R05: TTL env var controls staleness threshold" {
    NOW="$(date +%s)"
    mkdir -p "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    echo "$(( NOW - 5 ))" > "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001/epoch"  # 5s old

    # Tiny TTL → 5s counts as stale → reclaim → TUNE-0001
    run env DATARIM_ID_RESERVATION_TTL=1 bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]

    # Re-seed (first run consumed it) and test the fresh path with a large TTL.
    # A large TTL keeps the 5s-old marker fresh → auto-bump (warning → stderr).
    mkdir -p "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001"
    echo "$(( NOW - 5 ))" > "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001/epoch"
    OUT="$(mktemp)"
    env DATARIM_ID_RESERVATION_TTL=100000 bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${OUT}" 2>/dev/null
    STATUS=$?
    CHOSEN="$(cat "${OUT}")"; rm -f "${OUT}"
    [ "$STATUS" -eq 0 ]
    [ "$CHOSEN" = "TUNE-0002" ]
}

# R06: the reservation store is created and only the selected ID is reserved.
@test "R06: selecting reserves exactly the chosen ID, no leaks" {
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0001" ]
    [ -d "${FIXTURE_DIR}/${RES_DIR_REL}/TUNE-0001" ]
    # Exactly one marker directory exists
    count="$(find "${FIXTURE_DIR}/${RES_DIR_REL}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    [ "${count}" = "1" ]
}

# R07: --release validates the ID argument (no path traversal).
@test "R07: --release rejects a malformed ID" {
    run bash "${HELPER}" --release "../../etc" "${FIXTURE_DIR}"
    [ "$status" -ne 0 ]
    echo "$output" | grep -iE "invalid id"
}

# ── Group T — documentation contract ─────────────────────────────────────────

@test "T01: next-free-id.sh header documents the reservation mechanism" {
    grep -iE "reservation|\.id-reservations" "${HELPER}"
}

@test "T02: next-free-id.sh documents reversibility (release / TTL)" {
    grep -iE "release|TTL|stale" "${HELPER}"
}

@test "T03: dr-init.md documents the reservation/lock mechanism" {
    grep -iE "reservation|\.id-reservations" "${CMDS_DIR}/dr-init.md"
}

@test "T04: dr-init.md documents reversibility of the reservation" {
    grep -iE "release|--release|reversible|TTL|expire" "${CMDS_DIR}/dr-init.md"
}
