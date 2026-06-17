#!/usr/bin/env bats
# test_content_consilium_judge.bats — TDD tests for content_consilium_judge.sh
# Tests: score matrix presence; rationale + traceability; no coworker write in script.

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

  # Minimal criteria config
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

# --- Test 1: Score matrix is present in judge-decision.md ---
@test "judge produces judge-decision.md" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/judge-decision.md" ]
}

@test "judge-decision.md contains score matrix table (vendor_slot column)" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  grep -q 'vendor_slot\|Vendor Slot\|Slot' "$RUN_DIR/judge-decision.md"
}

@test "judge-decision.md contains a score for each draft slot" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  # Each slot appears in the decision
  grep -q '\bA\b' "$RUN_DIR/judge-decision.md"
  grep -q '\bB\b' "$RUN_DIR/judge-decision.md"
  grep -q '\bC\b' "$RUN_DIR/judge-decision.md"
}

# --- Test 2: Rationale and traceability ---
@test "judge-decision.md contains rationale section" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  grep -qi 'rationale\|reason\|selected' "$RUN_DIR/judge-decision.md"
}

@test "judge-decision.md records which vendor slot was selected" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  grep -q 'winner\|Winner\|selected_slot\|Selected' "$RUN_DIR/judge-decision.md"
}

@test "judge copies winning draft to final.md" {
  run bash "$JUDGE" --run-dir "$RUN_DIR" --criteria "$CRITERIA_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/final.md" ]
  # final.md must be non-empty
  [ -s "$RUN_DIR/final.md" ]
}

@test "final.md content matches one of the input drafts" {
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

# --- Test 3: Zero coworker write in judge script itself (G1 gate) ---
@test "G1: judge script contains no 'coworker write' call" {
  # The judge must run natively — no coworker write delegation
  run grep -n 'coworker[[:space:]]\+write' "$JUDGE"
  [ "$status" -ne 0 ]  # grep exits 1 when no match — that is the PASS condition
}

@test "G1: judge script contains no 'coworker ask' for generation" {
  # coworker ask for bulk reads is permitted but not for generating judge output
  # Check for the specific pattern: coworker ask ... --spec (write/generation indicator)
  run grep -n 'coworker[[:space:]]\+ask.*--spec' "$JUDGE"
  [ "$status" -ne 0 ]
}

# --- Test 4: 2-of-3 input (one draft missing) still produces output ---
@test "judge works with only 2 drafts present (2-of-3 mode)" {
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

@test "judge-decision.md notes degradation when only 2 drafts available" {
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
