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
    awk -F'|' 'length($0) > 512 || NF != 12 { exit 1 }' "${TRACE1}"
    awk -F'|' 'length($0) > 512 || NF != 12 { exit 1 }' "${TRACE2}"
    grep -q '|stdout_attempt|' "${TRACE1}"
    grep -q '|stdout_attempt|' "${TRACE2}"
    # Both must be well-formed and different
    [[ "${ID1}" =~ ^TUNE-[0-9]{4}$ ]]
    [[ "${ID2}" =~ ^TUNE-[0-9]{4}$ ]]
    [ "${ID1}" != "${ID2}" ]
}

@test "R08: diagnostic-off path does not read filesystem identities" {
    STAT_REAL="$(command -v stat)"
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    STAT_CALLED="${FIXTURE_DIR}/stat-called"
    OUT="${FIXTURE_DIR}/disabled.stdout"
    ERR="${FIXTURE_DIR}/disabled.stderr"
    mkdir -p "${SPY_BIN}"
    cat > "${SPY_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
: > "$D5_STAT_CALLED"
exec "$D5_STAT_REAL" "$@"
EOF
    chmod +x "${SPY_BIN}/stat"
    unset _D5_TUNE0285_TRACE
    if PATH="${SPY_BIN}:${PATH}" D5_STAT_CALLED="${STAT_CALLED}" D5_STAT_REAL="${STAT_REAL}" \
        bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" >"${OUT}" 2>"${ERR}"; then
        STATUS=0
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 0 ]
    [ "$(cat "${OUT}")" = "TUNE-0001" ]
    [ ! -s "${ERR}" ]
    [ ! -e "${STAT_CALLED}" ]
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
    SPY_BIN="${FIXTURE_DIR}/spy-bin"
    STAT_CALLS="${FIXTURE_DIR}/stat-calls"
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
    : > "${STAT_CALLS}"
    if _D5_TUNE0285_TRACE=1 PATH="${SPY_BIN}:${PATH}" D5_STAT_CALLS="${STAT_CALLS}" D5_STAT_REAL="${STAT_REAL}" \
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
    [ "$(wc -l < "${STAT_CALLS}")" -eq 2 ]
    if [[ -n "${D5_TUNE0285_EVIDENCE_DIR:-}" ]]; then
        cp "${TRACE}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.trace"
        cp "${STAT_CALLS}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.stat-calls"
        cp "${OUT}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.stdout"
        cp "${ERR}" "${D5_TUNE0285_EVIDENCE_DIR}/cap.stderr"
    fi
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
