#!/usr/bin/env bats
# test_content_consilium_judge.bats — TDD tests for content_consilium_judge.sh
#
# Tests cover:
#   1. Default (production) path: per-criterion score matrix + rationale + traceability
#   2. Test-mode path (DR_JUDGE_TEST_MODE=1): word-count proxy fixture, clearly labelled
#   3. G1 gate: no coworker write/ask delegation in judge script
#   4. 2-of-3 degraded mode
#   5. Traceability: winner traceable to per-criterion matrix (not word-count composite)

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
JUDGE="$SCRIPT_DIR/scripts/content_consilium_judge.sh"

setup() {
  export RUN_DIR
  RUN_DIR="$(mktemp -d)"

  # Write three stub drafts of varying quality
  cat > "$RUN_DIR/draft-A.md" << 'DRAFT'
Testing is the cornerstone of reliable software. Without tests, every change
becomes a gamble. Automated tests provide a safety net that lets developers
refactor with confidence, catch regressions early, and ship faster.
DRAFT

  cat > "$RUN_DIR/draft-B.md" << 'DRAFT'
Tests are important. They help find bugs. You should write tests for your code.
DRAFT

  cat > "$RUN_DIR/draft-C.md" << 'DRAFT'
The discipline of testing transforms software development from an art of hope
into an engineering practice. Every test is a specification, a guard, and
documentation rolled into one. Teams that test well ship better software.
DRAFT

  # Minimal run-log
  cat > "$RUN_DIR/run-log.jsonl" << 'LOG'
{"vendor_slot":"A","status":"ok","elapsed_s":12}
{"vendor_slot":"B","status":"ok","elapsed_s":8}
{"vendor_slot":"C","status":"ok","elapsed_s":15}
LOG

  # Minimal criteria config with 3 named criteria
  export CRITERIA_CONFIG
  CRITERIA_CONFIG="$(mktemp)"
  cat > "$CRITERIA_CONFIG" << 'YAML'
criteria:
  - id: specificity
    weight: 2
    description: "Uses concrete examples and specific claims"
  - id: naturalness
    weight: 2
    description: "Reads as natural human prose"
  - id: length_fit
    weight: 1
    description: "Appropriate length for the brief"
YAML
}

teardown() {
  rm -rf "$RUN_DIR" "$CRITERIA_CONFIG"
}

# ---------------------------------------------------------------------------
# Group 1: Default (production) path — per-criterion score matrix
# ---------------------------------------------------------------------------

@test "production: judge produces judge-decision.md" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/judge-decision.md" ]
}

@test "production: judge-decision.md contains per-criterion matrix (not composite-only)" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # Each named criterion must appear in the score matrix section
  grep -q 'specificity' "$RUN_DIR/judge-decision.md"
  grep -q 'naturalness' "$RUN_DIR/judge-decision.md"
  grep -q 'length_fit'  "$RUN_DIR/judge-decision.md"
}

@test "production: judge-decision.md scores each slot against each criterion (1-5 scale)" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # At minimum each slot should appear in the matrix
  grep -q '\bA\b' "$RUN_DIR/judge-decision.md"
  grep -q '\bB\b' "$RUN_DIR/judge-decision.md"
  grep -q '\bC\b' "$RUN_DIR/judge-decision.md"
  # A per-criterion score uses /5 notation
  grep -qE '[1-5]/5' "$RUN_DIR/judge-decision.md"
}

@test "production: judge-decision.md contains written rationale per criterion" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # Rationale section must exist and contain per-criterion subsections
  grep -qi 'per-criterion rationale\|Rationale' "$RUN_DIR/judge-decision.md"
}

@test "production: judge-decision.md winner traceable to per-criterion matrix" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # Traceability block must carry selected_slot and judge_mode=per_criterion_production
  grep -q 'selected_slot' "$RUN_DIR/judge-decision.md"
  grep -q 'per_criterion_production' "$RUN_DIR/judge-decision.md"
}

@test "production: judge-decision.md records winner as slot label (traceable to chosen draft)" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  grep -qi 'winner\|Winner\|selected_slot\|Selected' "$RUN_DIR/judge-decision.md"
}

@test "production: judge copies winning draft to final.md" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/final.md" ]
  [ -s "$RUN_DIR/final.md" ]
}

@test "production: final.md content matches one of the input drafts" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  local matched=0
  for slot in A B C; do
    if diff -q "$RUN_DIR/final.md" "$RUN_DIR/draft-${slot}.md" >/dev/null 2>&1; then
      matched=1
      break
    fi
  done
  [ "$matched" -eq 1 ]
}

@test "production: judge-decision.md does NOT claim to be test-mode output" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # The production path must NOT carry the test-fixture warning label
  run grep -c 'DR_JUDGE_TEST_MODE=1' "$RUN_DIR/judge-decision.md"
  [ "$output" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Group 2: Test-mode path (DR_JUDGE_TEST_MODE=1) — word-count proxy fixture
# ---------------------------------------------------------------------------

@test "test-mode: DR_JUDGE_TEST_MODE=1 produces judge-decision.md" {
  DR_JUDGE_TEST_MODE=1 run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/judge-decision.md" ]
}

@test "test-mode: output is clearly labelled as test-mode fixture (not production)" {
  DR_JUDGE_TEST_MODE=1 run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # Decision must carry an explicit test-mode warning/label
  grep -qi 'DR_JUDGE_TEST_MODE\|test.*fixture\|test_fixture\|word.count.proxy' \
    "$RUN_DIR/judge-decision.md"
}

@test "test-mode: traceability records judge_mode as test_fixture (not production)" {
  DR_JUDGE_TEST_MODE=1 run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  grep -q 'test_fixture\|test_composite\|word_count_proxy' "$RUN_DIR/judge-decision.md"
}

@test "test-mode: final.md is produced and matches an input draft" {
  DR_JUDGE_TEST_MODE=1 run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/final.md" ]
  [ -s "$RUN_DIR/final.md" ]
  local matched=0
  for slot in A B C; do
    if diff -q "$RUN_DIR/final.md" "$RUN_DIR/draft-${slot}.md" >/dev/null 2>&1; then
      matched=1
      break
    fi
  done
  [ "$matched" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Group 3: G1 gate — zero coworker delegation in judge script
# ---------------------------------------------------------------------------

@test "G1: judge script contains no 'coworker write' call" {
  # The judge must run natively — no coworker write delegation
  run grep -n 'coworker[[:space:]]\+write' "$JUDGE"
  [ "$status" -ne 0 ]  # grep exits 1 when no match — that is the PASS condition
}

@test "G1: judge script contains no 'coworker ask' for generation" {
  # coworker ask for bulk reads is permitted but not for generating judge output
  run grep -n 'coworker[[:space:]]\+ask.*--spec' "$JUDGE"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Group 4: 2-of-3 degraded mode
# ---------------------------------------------------------------------------

@test "degraded: judge works with only 2 drafts present (2-of-3 mode)" {
  rm "$RUN_DIR/draft-B.md"
  cat > "$RUN_DIR/run-log.jsonl" << 'LOG'
{"vendor_slot":"A","status":"ok","elapsed_s":12}
{"vendor_slot":"B","status":"error","elapsed_s":0,"reason":"exit 1"}
{"vendor_slot":"C","status":"ok","elapsed_s":15}
LOG

  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/final.md" ]
  [ -s "$RUN_DIR/final.md" ]
}

@test "degraded: judge-decision.md notes degradation when only 2 drafts available" {
  rm "$RUN_DIR/draft-B.md"
  cat > "$RUN_DIR/run-log.jsonl" << 'LOG'
{"vendor_slot":"A","status":"ok","elapsed_s":12}
{"vendor_slot":"B","status":"error","elapsed_s":0,"reason":"exit 1"}
{"vendor_slot":"C","status":"ok","elapsed_s":15}
LOG

  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  grep -qi 'degradation\|missing\|2.*of\|of.*2' "$RUN_DIR/judge-decision.md"
}
