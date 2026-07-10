#!/usr/bin/env bats
#
# TUNE-0118 — /dr-status pull-mode "what's next?" oracle:
#   (1) Pull-mode Oracle section present in commands/dr-status.md
#   (2) trigger contract: TASK-ID + free-form question activates pull-mode
#   (3) snapshot-first resolution reuses the /dr-next snapshot contract
#       (check-stage-snapshot-on-exit.sh + recommended_next) — no divergent opinion
#   (4) silent stage-fallback when snapshot absent (no warning noise)
#   (5) stage -> next-command mapping table present
#   (6) read-only: never writes/refreshes the snapshot
#   (7) English-only body still passes and doc-refs stay clean

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CMD="${REPO_ROOT}/commands/dr-status.md"

@test "dr-status.md carries a Pull-mode Oracle section (TUNE-0118)" {
    grep -q '## Pull-mode Oracle' "$CMD"
}

@test "oracle trigger requires BOTH a TASK-ID and a free-form question" {
    grep -q 'TASK-ID plus a free-form question' "$CMD"
    grep -q "what's next?" "$CMD"
}

@test "oracle resolution reuses the snapshot validator (consistency with /dr-next)" {
    grep -F 'check-stage-snapshot-on-exit.sh' "$CMD" >/dev/null
}

@test "oracle recommendation derives from snapshot recommended_next field" {
    grep -F 'recommended_next' "$CMD" >/dev/null
}

@test "oracle cites the dr-next snapshot replay consumer contract" {
    grep -F 'dr-next-snapshot-replay/SKILL.md' "$CMD" >/dev/null
}

@test "oracle has a silent stage-fallback when snapshot is absent" {
    grep -qi 'silent fallback' "$CMD"
    grep -q 'stage-fallback' "$CMD"
}

@test "oracle documents a Stage -> next-command mapping table" {
    grep -q 'Stage → next-command mapping' "$CMD"
    grep -F '/dr-archive {TASK-ID}' "$CMD" >/dev/null
    grep -F '/dr-verify {TASK-ID}' "$CMD" >/dev/null
}

@test "oracle is read-only — never writes or refreshes the snapshot" {
    grep -q 'READ-ONLY: it never writes' "$CMD"
}

@test "Read section lists the snapshot path for pull-mode" {
    grep -F 'datarim/snapshots/{TASK-ID}.snapshot.md' "$CMD" >/dev/null
}

@test "CTA routing logic has a pull-mode oracle branch" {
    grep -q 'Pull-mode oracle (TASK-ID + free-form question)' "$CMD"
}

@test "intro documents both push-mode and pull-mode" {
    grep -q 'push-mode' "$CMD"
    grep -q 'pull-mode oracle' "$CMD"
}
