#!/usr/bin/env bats
# Focused CLI contract tests for check-skill-layout.sh --summary-json.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-skill-layout.sh"

setup() {
    TMPROOT="${BATS_TEST_TMPDIR}/synthetic-root"
    OUT="${BATS_TEST_TMPDIR}/stdout"
    ERR="${BATS_TEST_TMPDIR}/stderr"
    mkdir -p "${TMPROOT}/skills"
}

write_skill() {
    local name="$1" frontmatter_name="$2"
    mkdir -p "${TMPROOT}/skills/${name}"
    cat >"${TMPROOT}/skills/${name}/SKILL.md" <<SKILL
---
name: ${frontmatter_name}
description: synthetic fixture
---
synthetic body
SKILL
}

run_cli() {
    local status=0
    "${SCRIPT}" "$@" >"${OUT}" 2>"${ERR}" || status=$?
    RUN_STATUS="${status}"
}

assert_summary() {
    local expected="$1"
    local actual
    actual="$(cat "${OUT}")"
    [ "${actual}" = "${expected}" ] \
        && [ "$(wc -l <"${OUT}")" -eq 1 ] \
        && [ ! -s "${ERR}" ]
}

@test "valid layout reports one measured directory and leaves inputs unchanged" {
    write_skill "alpha" "alpha"
    local source_before fixture_before
    source_before="$(sha256sum "${SCRIPT}")"
    fixture_before="$(sha256sum "${TMPROOT}/skills/alpha/SKILL.md")"

    run_cli --root "${TMPROOT}" --summary-json

    [ "${RUN_STATUS}" -eq 0 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED"}' \
        && [ "${source_before}" = "$(sha256sum "${SCRIPT}")" ] \
        && [ "${fixture_before}" = "$(sha256sum "${TMPROOT}/skills/alpha/SKILL.md")" ]
}

@test "empty existing skills directory reports measured zero" {
    run_cli --summary-json --root "${TMPROOT}"

    [ "${RUN_STATUS}" -eq 0 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":0,"checked_count_status":"MEASURED"}'
}

@test "reserved system namespace is skipped without changing the count" {
    mkdir -p "${TMPROOT}/skills/.system/bundled" "${TMPROOT}/skills/alpha"
    printf '%s\n' 'not a skill fixture' >"${TMPROOT}/skills/.system/bundled/README.md"
    write_skill "alpha" "alpha"

    run_cli --root "${TMPROOT}" --summary-json

    [ "${RUN_STATUS}" -eq 0 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED"}'
}

@test "invalid directory name is reduced to a fixed summary" {
    mkdir -p "${TMPROOT}/skills/Private-Name-Sentinel"

    run_cli --summary-json --root "${TMPROOT}"

    [ "${RUN_STATUS}" -eq 1 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_LAYOUT_INVALID"],"checked_count":1,"checked_count_status":"MEASURED"}' \
        && ! grep -qF 'Private-Name-Sentinel' "${OUT}" \
        && ! grep -qF 'Private-Name-Sentinel' "${ERR}"
}

@test "missing SKILL.md path is not serialized" {
    mkdir -p "${TMPROOT}/skills/private-skill-sentinel"

    run_cli --root "${TMPROOT}" --summary-json

    [ "${RUN_STATUS}" -eq 1 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_LAYOUT_INVALID"],"checked_count":1,"checked_count_status":"MEASURED"}' \
        && ! grep -qF 'private-skill-sentinel' "${OUT}" \
        && ! grep -qF 'private-skill-sentinel' "${ERR}"
}

@test "frontmatter values are not serialized" {
    write_skill "alpha" "FRONTMATTER_SECRET_SENTINEL"

    run_cli --summary-json --root "${TMPROOT}"

    [ "${RUN_STATUS}" -eq 1 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_LAYOUT_INVALID"],"checked_count":1,"checked_count_status":"MEASURED"}' \
        && ! grep -qF 'FRONTMATTER_SECRET_SENTINEL' "${OUT}" \
        && ! grep -qF 'FRONTMATTER_SECRET_SENTINEL' "${ERR}"
}

@test "flat coexistence refusal reports the existing measured failure" {
    write_skill "alpha" "alpha"
    printf '%s\n' 'synthetic flat file' >"${TMPROOT}/skills/alpha.md"

    run_cli --root "${TMPROOT}" --summary-json

    [ "${RUN_STATUS}" -eq 1 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_LAYOUT_INVALID"],"checked_count":1,"checked_count_status":"MEASURED"}'
}

@test "allow-flat-coexistence keeps the pass and count while suppressing prose" {
    write_skill "alpha" "alpha"
    printf '%s\n' 'synthetic flat file' >"${TMPROOT}/skills/alpha.md"

    run_cli --summary-json --allow-flat-coexistence --root "${TMPROOT}"

    [ "${RUN_STATUS}" -eq 0 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED"}' \
        && ! grep -qF 'OK-HYBRID' "${OUT}"
}

@test "missing skills root reports the fixed unavailable code without its path" {
    local missing_root="${BATS_TEST_TMPDIR}/PRIVATE_ROOT_SENTINEL"
    mkdir -p "${missing_root}"

    run_cli --root "${missing_root}" --summary-json

    [ "${RUN_STATUS}" -eq 2 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":2,"diagnostic_codes":["SKILLS_ROOT_UNAVAILABLE"],"checked_count":null,"checked_count_status":"NOT_MEASURED"}' \
        && ! grep -qF 'PRIVATE_ROOT_SENTINEL' "${OUT}" \
        && ! grep -qF 'PRIVATE_ROOT_SENTINEL' "${ERR}"
}

@test "no-flag successful output and exit remain unchanged" {
    write_skill "alpha" "alpha"
    local expected
    printf -v expected '\n=== Summary ===\nchecked=1 skill directories under %s/skills\nRESULT: PASS (V-AC-2 layout)' "${TMPROOT}"

    run_cli --root "${TMPROOT}"

    [ "${RUN_STATUS}" -eq 0 ] \
        && [ "$(cat "${OUT}")" = "${expected}" ] \
        && [ "$(wc -l <"${OUT}")" -eq 4 ] \
        && [ ! -s "${ERR}" ]
}

@test "no-flag failing output and exit remain unchanged" {
    write_skill "alpha" "alpha"
    printf '%s\n' 'synthetic flat file' >"${TMPROOT}/skills/alpha.md"
    local expected
    printf -v expected 'FAIL (alpha): flat .md coexists with directory (%s/skills/alpha.md)\n\n=== Summary ===\nchecked=1 skill directories under %s/skills\nRESULT: FAIL' "${TMPROOT}" "${TMPROOT}"

    run_cli --root "${TMPROOT}"

    [ "${RUN_STATUS}" -eq 1 ] \
        && [ "$(cat "${OUT}")" = "${expected}" ] \
        && [ "$(wc -l <"${OUT}")" -eq 5 ] \
        && [ ! -s "${ERR}" ]
}

@test "unknown arguments stay outside the summary contract" {
    run_cli --summary-json --root "${TMPROOT}" --unknown-sentinel

    [ "${RUN_STATUS}" -eq 2 ] \
        && [ ! -s "${OUT}" ] \
        && grep -qF 'unknown arg: --unknown-sentinel' "${ERR}"
}

@test "help stays a usage response even when summary mode was requested" {
    run_cli --summary-json --help

    [ "${RUN_STATUS}" -eq 0 ] \
        && grep -qF -- '--summary-json' "${OUT}" \
        && grep -qF 'Usage: check-skill-layout.sh' "${OUT}" \
        && ! grep -qF 'DatarimSkillLayoutValidationSummary/v1' "${OUT}" \
        && [ ! -s "${ERR}" ]
}

@test "missing root argument remains outside the summary contract" {
    run_cli --root
    local default_status="${RUN_STATUS}" default_stderr
    default_stderr="$(cat "${ERR}")"

    run_cli --summary-json --root

    [ "${RUN_STATUS}" -eq "${default_status}" ] \
        && [ "$(cat "${ERR}")" = "${default_stderr}" ] \
        && [ ! -s "${OUT}" ] \
        && [ -s "${ERR}" ]
}


@test "IFS preserves whitespace and tabs in synthetic root and frontmatter" {
    local tab_root="${BATS_TEST_TMPDIR}/root with space"$'\t'"and-tab"
    TMPROOT="${tab_root}"
    local skill_file="${TMPROOT}/skills/alpha/SKILL.md"
    mkdir -p "${TMPROOT}/skills/alpha"
    printf '%s\n' '---' $'name:\talpha' $'description:\tspace and\ttab' '---' 'synthetic body' >"${skill_file}"

    local source_before fixture_before expected_default
    source_before="$(sha256sum "${SCRIPT}")"
    fixture_before="$(sha256sum "${skill_file}")"
    printf -v expected_default '\n=== Summary ===\nchecked=1 skill directories under %s/skills\nRESULT: PASS (V-AC-2 layout)' "${TMPROOT}"

    run_cli --root "${TMPROOT}"
    [ "${RUN_STATUS}" -eq 0 ] \
        && [ "$(cat "${OUT}")" = "${expected_default}" ] \
        && [ ! -s "${ERR}" ] \
        && [ "${source_before}" = "$(sha256sum "${SCRIPT}")" ] \
        && [ "${fixture_before}" = "$(sha256sum "${skill_file}")" ]

    run_cli --root "${TMPROOT}" --summary-json
    [ "${RUN_STATUS}" -eq 0 ] \
        && assert_summary '{"schema":"DatarimSkillLayoutValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED"}' \
        && ! grep -qF "${tab_root}" "${OUT}" \
        && [ "${source_before}" = "$(sha256sum "${SCRIPT}")" ] \
        && [ "${fixture_before}" = "$(sha256sum "${skill_file}")" ]
}
