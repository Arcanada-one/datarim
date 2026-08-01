#!/usr/bin/env bats
#
# TUNE-0259 — end-to-end smoke for write_stage_snapshot + validator chain.
#
# Exercises the full happy path against a synthetic repo root:
#   1. compose body + options tempfiles
#   2. invoke write_stage_snapshot (sourced from scripts/lib/snapshot-writer.sh)
#   3. assert snapshot file exists at the canonical path
#   4. validate frontmatter via dev-tools/check-stage-snapshot-on-exit.sh
#   5. confirm CTA body content is preserved (replay-prompt precondition)
#   6. kill-switch DATARIM_DISABLE_SNAPSHOT=1 makes the writer a no-op

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"
WRITER_WRAPPER="${REPO_ROOT}/dev-tools/snapshot-writer-wrapper.sh"
VALIDATOR="${REPO_ROOT}/dev-tools/check-stage-snapshot-on-exit.sh"
TASK_ID="TUNE-9999"

setup() {
    FAKE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/fake-repo.XXXX")"
    mkdir -p "${FAKE_ROOT}/datarim/snapshots"
    BODY_TMP="$(mktemp "${BATS_TEST_TMPDIR}/body.XXXX")"
    OPTIONS_TMP="$(mktemp "${BATS_TEST_TMPDIR}/opts.XXXX")"
    cat > "${BODY_TMP}" <<'EOB'
Implementation TUNE-0259 готово — Variant 2 wiring applied.

---
**Next Steps (CTA)**

#: 1
Option: /dr-qa TUNE-0259
Purpose: **рекомендуется** — multi-layer verification.
EOB
    printf '/dr-qa TUNE-0259 | multi-layer verification\n' > "${OPTIONS_TMP}"
}

@test "E2E happy path — snapshot written and validates" {
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    run write_stage_snapshot \
        --root "${FAKE_ROOT}" \
        --task "${TASK_ID}" \
        --stage do \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" \
        --body-file "${BODY_TMP}"
    [ "$status" -eq 0 ]
    [ -f "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md" ]
}

@test "E2E — validator passes against the just-written snapshot" {
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    write_stage_snapshot \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"
    run bash "${VALIDATOR}" --validate-frontmatter --task "${TASK_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 0 ]
}

@test "E2E — snapshot body preserves CTA primary marker (replay precondition)" {
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    write_stage_snapshot \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"
    run grep -F '**рекомендуется**' "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    [ "$status" -eq 0 ]
}

@test "E2E — kill switch DATARIM_DISABLE_SNAPSHOT=1 makes writer a no-op" {
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    DATARIM_DISABLE_SNAPSHOT=1 run write_stage_snapshot \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"
    [ "$status" -eq 0 ]
    [ ! -f "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md" ]
}

@test "E2E — frontmatter carries the bound stage literal 'do'" {
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    write_stage_snapshot \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"
    run grep -E '^stage: do$' "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    [ "$status" -eq 0 ]
}

@test "E2E — frontmatter terminator never glues to a normal body" {
    run bash "${WRITER_WRAPPER}" \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"
    [ "$status" -eq 0 ]
    local snapshot="${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    run grep -q '^---Implementation' "${snapshot}"
    [ "$status" -eq 1 ]
    grep -q '^---$' "${snapshot}"
    grep -q '^Implementation TUNE-0259' "${snapshot}"
}

@test "E2E wrapper — ordinary body without a leading newline stays unglued" {
    local ordinary_body="${BATS_TEST_TMPDIR}/ordinary-body.txt"
    printf '%s' 'Implementation TUNE-0259 ordinary first line' > "${ordinary_body}"

    run bash "${WRITER_WRAPPER}" \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${ordinary_body}"
    [ "$status" -eq 0 ]

    local snapshot="${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    run grep -F -q -- '---Implementation TUNE-0259 ordinary first line' "${snapshot}"
    [ "$status" -eq 1 ]
}

@test "E2E — declared size_bytes equals exact snapshot bytes" {
    run bash "${WRITER_WRAPPER}" \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"
    [ "$status" -eq 0 ]
    local snapshot="${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    local declared actual
    declared="$(sed -n 's/^size_bytes: //p' "${snapshot}")"
    actual="$(wc -c < "${snapshot}" | tr -d ' ')"
    [ "${declared}" -eq "${actual}" ]
}

@test "E2E — wrapper reports exact four-digit snapshot size" {
    local four_digit_body="${BATS_TEST_TMPDIR}/four-digit-body.txt"
    python3 -c 'print("X" * 1000, end="")' > "${four_digit_body}"
    [ "$(wc -c < "${four_digit_body}" | tr -d ' ')" -eq 1000 ]

    run bash "${WRITER_WRAPPER}" \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${four_digit_body}"
    [ "$status" -eq 0 ]

    local snapshot="${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    local declared actual
    declared="$(sed -n 's/^size_bytes: //p' "${snapshot}")"
    actual="$(wc -c < "${snapshot}" | tr -d ' ')"
    [ "${actual}" -ge 1000 ]
    [ "${declared}" -eq "${actual}" ]
}

@test "E2E wrapper — declared size converges across the 999-to-1000 boundary" {
    local captured_at="2026-07-30T00:00:00Z"
    local probe="${BATS_TEST_TMPDIR}/boundary-frontmatter.md"
    local boundary_body="${BATS_TEST_TMPDIR}/boundary-body.txt"

    # The cap-width probe is four digits. Choosing the body so the pre-fix
    # command-substitution path declared 999 forces the 3→4 digit transition.
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    _snapshot_render_frontmatter \
        "${TASK_ID}" do /dr-do "${captured_at}" agent /dr-qa \
        "${OPTIONS_TMP}" 8192 true > "${probe}"
    local probe_bytes body_bytes
    probe_bytes="$(wc -c < "${probe}" | tr -d ' ')"
    body_bytes=$((1002 - probe_bytes))
    [ "${body_bytes}" -gt 0 ]
    python3 -c "print('X' * ${body_bytes}, end='')" > "${boundary_body}"
    [ "$(wc -c < "${boundary_body}" | tr -d ' ')" -eq "${body_bytes}" ]

    run bash "${WRITER_WRAPPER}" \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${boundary_body}" \
        --captured-at "${captured_at}"
    [ "$status" -eq 0 ]

    local snapshot="${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md"
    local declared actual
    declared="$(sed -n 's/^size_bytes: //p' "${snapshot}")"
    actual="$(wc -c < "${snapshot}" | tr -d ' ')"
    [ "${declared}" -eq "${actual}" ]
    [ "${actual}" -ge 1000 ]
}

@test "E2E — exact-size renderer converges across the 9999 to 10000 decimal-width boundary" {
    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
    local probe="${BATS_TEST_TMPDIR}/fixed-point-probe.md"
    local rendered="${BATS_TEST_TMPDIR}/fixed-point-rendered.md"
    local captured_at="2026-07-30T00:00:00Z"

    _snapshot_render_frontmatter \
        "${TASK_ID}" do /dr-do "${captured_at}" agent /dr-qa \
        "${OPTIONS_TMP}" 9999 false > "${probe}"

    local frontmatter_bytes body_bytes declared actual
    frontmatter_bytes="$(wc -c < "${probe}" | tr -d ' ')"
    body_bytes=$((10000 - frontmatter_bytes))
    [ "${body_bytes}" -gt 0 ]

    declared="$(_snapshot_render_exact_frontmatter \
        "${TASK_ID}" do /dr-do "${captured_at}" agent /dr-qa \
        "${OPTIONS_TMP}" "${body_bytes}" 9999 false "${rendered}")"
    actual=$(( $(wc -c < "${rendered}" | tr -d ' ') + body_bytes ))

    [ "${declared}" -eq 10001 ]
    [ "${declared}" -eq "${actual}" ]
    grep -q '^size_bytes: 10001$' "${rendered}"
}

@test "E2E — oversized options fail closed before publishing any snapshot" {
    local huge_options="${BATS_TEST_TMPDIR}/huge-options.txt"
    python3 -c 'print("/dr-qa TUNE-9999 | " + "X" * 9000)' > "${huge_options}"

    run bash "${WRITER_WRAPPER}" \
        --root "${FAKE_ROOT}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${huge_options}" --body-file "${BODY_TMP}"

    [ "$status" -eq 1 ]
    [[ "$output" == *"exceeds 8192-byte cap"* ]]
    [ ! -e "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md" ]
    [ ! -d "${FAKE_ROOT}/datarim/snapshots/.lock.${TASK_ID}" ]
}

@test "E2E — I/O failure cleanup treats root as data and removes the acquired lock" {
    local canary="${BATS_TEST_TMPDIR}/TUNE0546_CANARY"
    local literal_payload='$(touch${IFS}TUNE0546_CANARY)'
    local hostile_root="${BATS_TEST_TMPDIR}/root-${literal_payload}"
    local fake_bin="${BATS_TEST_TMPDIR}/fake-bin"
    mkdir -p "${hostile_root}/datarim/snapshots" "${fake_bin}"
    printf '#!/usr/bin/env bash\nexit 74\n' > "${fake_bin}/cp"
    chmod +x "${fake_bin}/cp"

    run env PATH="${fake_bin}:${PATH}" bash -c '
        cd "$1"
        shift
        exec "$@"
    ' _ "${BATS_TEST_TMPDIR}" bash "${WRITER_WRAPPER}" \
        --root "${hostile_root}" --task "${TASK_ID}" --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "${OPTIONS_TMP}" --body-file "${BODY_TMP}"

    [ "$status" -ne 0 ]
    [ ! -e "${canary}" ]
    [ ! -d "${hostile_root}/datarim/snapshots/.lock.${TASK_ID}" ]
    [ ! -e "${hostile_root}/datarim/snapshots/${TASK_ID}.snapshot.md" ]
}
