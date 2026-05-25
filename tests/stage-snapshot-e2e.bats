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
