#!/usr/bin/env bats
# ai-quality-wire-shape-mirror-smoke-gate.bats — markdown-smoke test.
#
# Provenance: documentation/how-to/evolution-log.md (Wire-Shape Mirror via
# Cited File-Line rule). A client / SDK / adapter task mirrors a source wire
# shape; citing each mirrored field/type/enum by <file>:<line> in the plan and
# grepping every cited symbol at plan time catches shape drift before code
# generation, deterministically and near-free. This test asserts the gate text
# was added to skills/ai-quality/SKILL.md in the documented shape. Light —
# markdown-smoke-level, not functional coverage (the gate is a workflow
# instruction consumed by an LLM agent, not an executable script).

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL_FILE="$REPO_DIR/skills/ai-quality/SKILL.md"

@test "T1: ai-quality/SKILL.md exists" {
  [ -f "$SKILL_FILE" ]
}

@test "T2: new section heading present" {
  grep -qF '## Wire-Shape Mirror via Cited File-Line in the Plan' "$SKILL_FILE"
}

@test "T3: plan-time <file>:<line> citation rule present (acceptance: citation present in plan)" {
  grep -qF 'cite each mirrored field, type, or enum by `<file>:<line>` in the plan' "$SKILL_FILE"
}

@test "T4: symbol-existence grep at plan time, before code generation, documented" {
  grep -qF 'grep every cited symbol at plan time' "$SKILL_FILE"
  grep -qF 'before code generation' "$SKILL_FILE"
}

@test "T5: the mirror is 1:1 (wire-shape match) documented" {
  grep -qF 'the mirror is 1:1' "$SKILL_FILE"
  grep -qF 'wire-shape' "$SKILL_FILE"
}

@test "T6: cross-references the sibling line-reference smoke check" {
  grep -qF 'Task-Description Line-Reference Smoke Check' "$SKILL_FILE"
}

@test "T7: section body is English-only (no Cyrillic)" {
  ! grep -RPn $'[Ѐ-ӿ]' "$SKILL_FILE"
}

@test "T8: file stays history-agnostic gate-clean (no bare TASK-ID leaked into shipped skill)" {
  run "$REPO_DIR/scripts/task-id-gate.sh" "$SKILL_FILE"
  [ "$status" -eq 0 ]
}
