#!/usr/bin/env bats
#
# TUNE-0254 — cta-format ↔ snapshot-writer integration:
#   (a) cta-format.md carries § Snapshot Emission terminal subsection
#   (b) golden fixture parses cleanly + can be wrapped as snapshot body
#   (c) writer failure surfaces stderr warning (fail-closed)

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SKILL="${REPO_ROOT}/skills/cta-format/SKILL.md"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"
FIXTURE="${BATS_TEST_DIRNAME}/cta-format/fixtures/snapshot-emission-l3-plan.md"

@test "cta-format.md carries '## Snapshot Emission' subsection (V-AC-15)" {
    run grep -F '## Snapshot Emission' "$SKILL"
    [ "$status" -eq 0 ]
}

@test "cta-format.md references stage-snapshot-writer skill" {
    run grep -F 'skills/stage-snapshot-writer/SKILL.md' "$SKILL"
    [ "$status" -eq 0 ]
}

@test "golden snapshot-emission fixture exists with primary CTA marker" {
    [ -f "$FIXTURE" ]
    run grep -F '**рекомендуется**' "$FIXTURE"
    [ "$status" -eq 0 ]
}

@test "fixture body can be wrapped as snapshot — writer succeeds" {
    local tmproot="$BATS_TEST_TMPDIR/fake-repo"
    local opts="$BATS_TEST_TMPDIR/opts.txt"
    mkdir -p "$tmproot/datarim"
    printf '/dr-do TUNE-0254 | implement\n' > "$opts"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
    run write_stage_snapshot \
        --root "$tmproot" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$opts" --body-file "$FIXTURE"
    [ "$status" -eq 0 ]
    grep -q '\*\*рекомендуется\*\*' "$tmproot/datarim/snapshots/TUNE-0254.snapshot.md"
}

@test "writer with bad TASK-ID exits 1 (caller MUST surface, fail-closed)" {
    local opts="$BATS_TEST_TMPDIR/opts.txt"
    printf '/dr-do | x\n' > "$opts"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
    run write_stage_snapshot \
        --root "$BATS_TEST_TMPDIR" --task 'bad id' --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$opts" --body-file "$FIXTURE"
    [ "$status" -eq 1 ]
}
