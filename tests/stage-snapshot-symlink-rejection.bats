#!/usr/bin/env bats
#
# TUNE-0254 F9 — consumer-side symlink rejection.
#
# Writer-side T-7 mitigation pre-unlinks symlinks at the final path before
# atomic rename. Consumer-side was asymmetric: validator did not check for
# symlinks at all, so a malicious co-agent in a shared workspace could
# replace datarim/snapshots/{ID}.snapshot.md with a symlink to a sensitive
# file (e.g. /etc/passwd) and the replay-prompt would inline its content.
#
# Fix: dev-tools/check-stage-snapshot-on-exit.sh rejects symlinks at the
# snapshot path with exit 2 (malformed). Consumer /dr-continue Step 2.5
# fallbacks silently to legacy behaviour on validator non-zero, so reject
# == "no replay" which is the safe default.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
VALIDATOR="${REPO_ROOT}/dev-tools/check-stage-snapshot-on-exit.sh"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim/snapshots"
}

write_valid_snapshot() {
    local path="$1"
    cat > "$path" <<'SNAP'
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
  - "/dr-do TUNE-0254 | go"
size_bytes: 100
truncated: false
---

body
SNAP
}

@test "F9: validator rejects symlinked snapshot path (exit 2 malformed)" {
    local real="$BATS_TEST_TMPDIR/secret.md"
    cat > "$real" <<'EOF'
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
  - "/dr-do TUNE-0254 | go"
size_bytes: 100
truncated: false
---

attacker-controlled body that would otherwise pass strict schema check
EOF
    # Replace snapshot path with a symlink to the attacker file.
    ln -s "$real" "$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"

    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "F9: validator rejects symlinked snapshot path in presence mode too" {
    local real="$BATS_TEST_TMPDIR/secret.md"
    write_valid_snapshot "$real"
    ln -s "$real" "$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"

    run "$VALIDATOR" --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "F9: regular file passes (regression guard — fix must not break happy path)" {
    write_valid_snapshot "$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"

    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "F9: missing snapshot still returns exit 1 (not conflated with symlink rejection)" {
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$TMPROOT"
    [ "$status" -eq 1 ]
}
