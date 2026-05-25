#!/usr/bin/env bats
#
# TUNE-0254 — check-stage-snapshot-on-exit.sh schema validator.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
VALIDATOR="${REPO_ROOT}/dev-tools/check-stage-snapshot-on-exit.sh"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim/snapshots"
    export SNAP="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
}

_write_valid_snapshot() {
    cat > "$SNAP" <<'SNAP'
---
task_id: TUNE-0254
artifact: stage-snapshot
schema_version: 1
stage: plan
command: /dr-plan
captured_at: 2026-05-21T00:00:00Z
captured_by: agent
recommended_next: /dr-do
options:
  - "/dr-do TUNE-0254 | implement"
size_bytes: 100
truncated: false
---

body
SNAP
}

@test "well-formed snapshot → exit 0" {
    _write_valid_snapshot
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "missing task_id field → exit 2" {
    _write_valid_snapshot
    # strip task_id line via sed; portable form
    sed -i.bak '/^task_id:/d' "$SNAP" && rm -f "${SNAP}.bak"
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "missing stage field → exit 2" {
    _write_valid_snapshot
    sed -i.bak '/^stage:/d' "$SNAP" && rm -f "${SNAP}.bak"
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "missing recommended_next field → exit 2" {
    _write_valid_snapshot
    sed -i.bak '/^recommended_next:/d' "$SNAP" && rm -f "${SNAP}.bak"
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "missing snapshot file → exit 1" {
    run "$VALIDATOR" --task TUNE-9999 --root "$TMPROOT"
    [ "$status" -eq 1 ]
}

@test "self-test mode → exit 0" {
    run "$VALIDATOR" --self-test
    [ "$status" -eq 0 ]
}
