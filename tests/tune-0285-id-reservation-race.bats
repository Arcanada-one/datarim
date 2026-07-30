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
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

# ── Group R — reservation mechanics ──────────────────────────────────────────

# R01: the two-session race — two concurrent invocations against one root MUST
# return DISTINCT IDs. This is the core defect TUNE-0285 closes.
@test "R01: two concurrent invocations return distinct IDs" {
    OUT1="$(mktemp)"; OUT2="$(mktemp)"
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${OUT1}" 2>/dev/null &
    P1=$!
    bash "${HELPER}" "TUNE" "${FIXTURE_DIR}" > "${OUT2}" 2>/dev/null &
    P2=$!
    wait "${P1}"; wait "${P2}"
    ID1="$(cat "${OUT1}")"; ID2="$(cat "${OUT2}")"
    rm -f "${OUT1}" "${OUT2}"
    # Both must be well-formed and different
    [[ "${ID1}" =~ ^TUNE-[0-9]{4}$ ]]
    [[ "${ID2}" =~ ^TUNE-[0-9]{4}$ ]]
    [ "${ID1}" != "${ID2}" ]
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
