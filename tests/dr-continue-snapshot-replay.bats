#!/usr/bin/env bats
#
# TUNE-0254/TUNE-0298 — next snapshot replay:
#   (1) Step 2.5 present in commands/dr-next.md and references validator + replay skill
#   (2) replay-prompt template carries CTA + bilingual autonomy + done before:
#   (3) fallback when snapshot absent — silent (no warning lines)

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CMD="${REPO_ROOT}/commands/dr-next.md"
REPLAY="${REPO_ROOT}/skills/dr-next-snapshot-replay.md"
VALIDATOR="${REPO_ROOT}/dev-tools/check-stage-snapshot-on-exit.sh"

@test "dr-next.md carries SNAPSHOT-FIRST READ step (V-AC-5)" {
    grep -q 'SNAPSHOT-FIRST READ' "$CMD"
}

@test "dr-next.md references check-stage-snapshot-on-exit.sh validator" {
    grep -F 'check-stage-snapshot-on-exit.sh' "$CMD" >/dev/null
}

@test "dr-next.md references replay skill (skills/dr-next-snapshot-replay.md)" {
    grep -F 'dr-next-snapshot-replay.md' "$CMD" >/dev/null
}

@test "replay skill carries canonical RU autonomy line (V-AC-11 RU)" {
    grep -q 'ищи способ исследовать все проблемы' "$REPLAY"
}

@test "replay skill carries canonical EN autonomy line (V-AC-11 EN)" {
    grep -q 'Find a way to investigate all problems' "$REPLAY"
}

@test "replay skill prompt template includes 'done before:' literal" {
    grep -q 'done before:' "$REPLAY"
}

@test "replay-prompt template has 'done before:' below both autonomy lines" {
    python3 - "$REPLAY" <<'PY'
import sys, re
content = open(sys.argv[1]).read()
m = re.search(
    r"<recommended-CTA>\s*\n\s*\n.*ищи способ исследовать все проблемы.*\n.*Find a way to investigate all problems.*\n\s*\ndone before:\s*\n<snapshot body>",
    content,
    re.DOTALL,
)
assert m, "canonical replay-prompt template not found"
PY
}

@test "fallback (no snapshot) — validator exit 1 means consumer falls through silently" {
    local tmproot="$BATS_TEST_TMPDIR/empty-repo"
    mkdir -p "$tmproot/datarim/snapshots"
    run "$VALIDATOR" --task TUNE-9999 --root "$tmproot"
    [ "$status" -eq 1 ]
    # Per V-AC-7 — validator exit 1 is the gate; consumer skips replay-prompt.
}

@test "stale snapshot — exit 0 still returns ok (consumer compares mtime upstream)" {
    local tmproot="$BATS_TEST_TMPDIR/stale-repo"
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
recommended_next: /dr-do
options:
  - "/dr-do TUNE-0254 | go"
size_bytes: 100
truncated: false
---

stale body
SNAP
    run "$VALIDATOR" --validate-frontmatter --task TUNE-0254 --root "$tmproot"
    [ "$status" -eq 0 ]
}

@test "replay skill documents ≥3 worked examples (V-AC-12)" {
    local count
    count="$(grep -c '^### Example' "$REPLAY")"
    [ "$count" -ge 3 ]
}
