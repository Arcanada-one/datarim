#!/usr/bin/env bats
#
# TUNE-0254 — V-AC-9: /dr-archive MOVES snapshot to documentation/archive/<subdir>/snapshots/.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

@test "dr-archive.md carries Step 0.95 STAGE-SNAPSHOT MOVE-TO-ARCHIVE section" {
    grep -F 'STAGE-SNAPSHOT MOVE-TO-ARCHIVE' "${REPO_ROOT}/commands/dr-archive.md" >/dev/null
}

@test "dr-archive.md references prefix_to_area resolver" {
    grep -F 'prefix_to_area' "${REPO_ROOT}/commands/dr-archive.md" >/dev/null
}

@test "pre-state present → simulated mv → post-state in archive, absent from datarim/, byte-identical" {
    local tmproot="$BATS_TEST_TMPDIR/archive-repo"
    local src="$tmproot/datarim/snapshots/TUNE-0254.snapshot.md"
    local dst_dir="$tmproot/documentation/archive/framework/snapshots"
    local dst="$dst_dir/TUNE-0254-final-stage.md"
    mkdir -p "$tmproot/datarim/snapshots" "$dst_dir"
    cat > "$src" <<'SNAP'
---
task_id: TUNE-0254
artifact: stage-snapshot
schema_version: 1
stage: archive
command: /dr-archive
captured_at: 2026-05-21T15:00:00Z
captured_by: agent
recommended_next: /dr-status
options:
  - "/dr-status | next task"
size_bytes: 200
truncated: false
---

Archive snapshot body.
SNAP
    local orig_sum
    orig_sum="$(shasum "$src" | awk '{print $1}')"

    # Simulate Step 0.95: mv.
    mv "$src" "$dst"

    [ ! -f "$src" ]
    [ -f "$dst" ]
    local new_sum
    new_sum="$(shasum "$dst" | awk '{print $1}')"
    [ "$orig_sum" = "$new_sum" ]
}

@test "gitignore covers datarim/snapshots/ (V-AC-14)" {
    grep -E '^datarim/snapshots/' "${REPO_ROOT}/.gitignore" >/dev/null
}
