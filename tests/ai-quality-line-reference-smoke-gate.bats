#!/usr/bin/env bats
# ai-quality-line-reference-smoke-gate.bats — markdown-smoke test for TUNE-0173.
#
# Source: reflection-TUNE-0163.md Class A Proposal 1 — a task description
# citing a <file>:<line> reference can drift stale by the time /dr-do reads
# it (zero grep matches). This test asserts the smoke-check gate text was
# added to skills/ai-quality/SKILL.md in the documented shape. Light per the
# backlog item — markdown-smoke-level, not functional coverage (the gate is
# a workflow instruction consumed by an LLM agent, not an executable script).

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL_FILE="$REPO_DIR/skills/ai-quality/SKILL.md"

@test "T1: ai-quality/SKILL.md exists" {
  [ -f "$SKILL_FILE" ]
}

@test "T2: new section heading present" {
  grep -qF '## Task-Description Line-Reference Smoke Check' "$SKILL_FILE"
}

@test "T3: smoke-check command shape (grep -n against <file>) documented" {
  grep -qF "grep -n '<expected-content>' <file>" "$SKILL_FILE"
}

@test "T4: diagnostic message shape (line-not-found) documented" {
  grep -qF 'line-not-found: expected "<X>" at line N, found zero matches in <file>' "$SKILL_FILE"
}

@test "T5: both /dr-do startup and mid-implementation trigger points documented" {
  grep -qF '/dr-do` startup' "$SKILL_FILE"
  grep -qF 'mid-implementation' "$SKILL_FILE"
}

@test "T6: recurrence rationale documented as history-agnostic prose (no bare task-ID)" {
  grep -qF 'recurring twice' "$SKILL_FILE"
}

@test "T7: section body is English-only (no Cyrillic)" {
  ! grep -RPn $'[Ѐ-ӿ]' "$SKILL_FILE"
}

@test "T8: file stays history-agnostic gate-clean (no bare TASK-ID leaked into shipped skill)" {
  run "$REPO_DIR/scripts/task-id-gate.sh" "$SKILL_FILE"
  [ "$status" -eq 0 ]
}
