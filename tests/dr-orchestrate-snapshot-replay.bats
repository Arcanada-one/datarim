#!/usr/bin/env bats
#
# TUNE-0254 — dr-orchestrate snapshot-first resume (V-AC-8).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CMD="${REPO_ROOT}/commands/dr-orchestrate.md"
VALIDATOR="${REPO_ROOT}/dev-tools/check-stage-snapshot-on-exit.sh"

@test "dr-orchestrate.md carries Snapshot-First Resume section (V-AC-8)" {
    grep -q 'Snapshot-First Resume' "$CMD"
}

@test "dr-orchestrate.md references check-stage-snapshot-on-exit.sh validator" {
    grep -F 'check-stage-snapshot-on-exit.sh' "$CMD" >/dev/null
}

@test "dr-orchestrate.md mentions --hint forwarding to subagent_resolver.sh" {
    grep -E -- '--hint' "$CMD" >/dev/null
}

@test "resume-with-snapshot: validator → exit 0 → recommended_next available" {
    local tmproot="$BATS_TEST_TMPDIR/orchestrate-repo"
    mkdir -p "$tmproot/datarim/snapshots"
    cat > "$tmproot/datarim/snapshots/TUNE-0254.snapshot.md" <<'SNAP'
---
task_id: TUNE-0254
artifact: stage-snapshot
schema_version: 1
stage: plan
command: /dr-plan
captured_at: 2026-05-21T00:00:00Z
captured_by: agent
recommended_next: /dr-verify
options:
  - "/dr-verify TUNE-0254 | tri-layer verification"
  - "/dr-status | escape hatch"
size_bytes: 200
truncated: false
---

Snapshot body that orchestrator will see.
SNAP
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$tmproot"
    [ "$status" -eq 0 ]
    # Consumer parses recommended_next from frontmatter and feeds as --hint.
    grep -q '^recommended_next: /dr-verify$' "$tmproot/datarim/snapshots/TUNE-0254.snapshot.md"
}

@test "resume-without-snapshot: validator exit 1 → orchestrator falls through (no hint)" {
    local tmproot="$BATS_TEST_TMPDIR/empty-orchestrate"
    mkdir -p "$tmproot/datarim/snapshots"
    run "$VALIDATOR" --task TUNE-9999 --root "$tmproot"
    [ "$status" -eq 1 ]
}
