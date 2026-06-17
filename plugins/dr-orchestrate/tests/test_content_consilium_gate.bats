#!/usr/bin/env bats
# test_content_consilium_gate.bats — TDD tests for publish hard-gate.
# Tests: dry-run default; explicit --publish flag path; FB-rules entry present.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FANOUT="$SCRIPT_DIR/scripts/content_consilium_fanout.sh"
JUDGE="$SCRIPT_DIR/scripts/content_consilium_judge.sh"
FB_RULES="$SCRIPT_DIR/rules/fb-rules.yaml"

setup() {
  export RUN_DIR
  RUN_DIR="$(mktemp -d)"
  printf 'Test brief for publish gate.\n' > "$RUN_DIR/brief.md"
  cat > "$RUN_DIR/final.md" << 'FINAL'
This is the final approved draft for publish-gate testing.
FINAL

  export CONFIG
  CONFIG="$(mktemp)"
  cat > "$CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "echo"
    args: ["DRAFT_A"]
  - slot: B
    cmd: "echo"
    args: ["DRAFT_B"]
  - slot: C
    cmd: "echo"
    args: ["DRAFT_C"]
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  export CRITERIA
  CRITERIA="$(mktemp)"
  cat > "$CRITERIA" << 'YAML'
criteria:
  - id: hook
    weight: 1
    description: "Hook strength"
YAML

  # Stub publish target: a file that the gate writes to when --publish is given
  export PUBLISH_TARGET="$RUN_DIR/publish_output.txt"
}

teardown() {
  rm -rf "$RUN_DIR" "$CONFIG" "$CRITERIA"
}

# --- Test 1: dry-run default — no publish occurs without --publish flag ---
@test "gate: dry-run is default — publish output file not created without --publish" {
  # Run fanout + judge in test mode
  DR_FANOUT_TEST_MODE=1 bash "$FANOUT" \
    --brief "$RUN_DIR/brief.md" \
    --run-dir "$RUN_DIR" \
    --config "$CONFIG"

  bash "$JUDGE" \
    --run-dir "$RUN_DIR" \
    --criteria "$CRITERIA"

  # Gate check: final.md exists but no publish has occurred (no PUBLISH_TARGET)
  [ -f "$RUN_DIR/final.md" ]
  [ ! -f "$PUBLISH_TARGET" ]
}

@test "gate: dry-run mode prints DRY-RUN notice" {
  DR_FANOUT_TEST_MODE=1 bash "$FANOUT" \
    --brief "$RUN_DIR/brief.md" \
    --run-dir "$RUN_DIR" \
    --config "$CONFIG"

  bash "$JUDGE" \
    --run-dir "$RUN_DIR" \
    --criteria "$CRITERIA"

  # The gate script emits a DRY-RUN notice on stdout/stderr by default
  run bash "${SCRIPT_DIR}/scripts/content_consilium_gate.sh" \
    --run-dir "$RUN_DIR" \
    --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qi 'dry.run\|DRY.RUN\|dry run'
}

# --- Test 2: explicit --publish flag path ---
@test "gate: --publish flag is accepted and gate executes publish path" {
  DR_FANOUT_TEST_MODE=1 bash "$FANOUT" \
    --brief "$RUN_DIR/brief.md" \
    --run-dir "$RUN_DIR" \
    --config "$CONFIG"

  bash "$JUDGE" \
    --run-dir "$RUN_DIR" \
    --criteria "$CRITERIA"

  run bash "${SCRIPT_DIR}/scripts/content_consilium_gate.sh" \
    --run-dir "$RUN_DIR" \
    --publish \
    --target "$PUBLISH_TARGET"
  [ "$status" -eq 0 ]
}

@test "gate: --publish writes final content to target" {
  DR_FANOUT_TEST_MODE=1 bash "$FANOUT" \
    --brief "$RUN_DIR/brief.md" \
    --run-dir "$RUN_DIR" \
    --config "$CONFIG"

  bash "$JUDGE" \
    --run-dir "$RUN_DIR" \
    --criteria "$CRITERIA"

  bash "${SCRIPT_DIR}/scripts/content_consilium_gate.sh" \
    --run-dir "$RUN_DIR" \
    --publish \
    --target "$PUBLISH_TARGET"

  [ -f "$PUBLISH_TARGET" ]
  [ -s "$PUBLISH_TARGET" ]
}

# --- Test 3: FB-rules entry for content_consilium_publish exists ---
@test "FB-rules: content_consilium_publish entry present in hard_gated_actions or equivalently named" {
  # The fb-rules.yaml must have a content_consilium_publish entry
  run grep -q 'content_consilium_publish\|consilium_publish\|publish_gate' "$FB_RULES"
  [ "$status" -eq 0 ]
}

@test "FB-rules: content_consilium_publish entry is under hard_gated_actions block" {
  # Verify positioning: the entry appears AFTER the hard_gated_actions: key.
  # Extract line number of hard_gated_actions: header and the entry, then compare.
  local header_line entry_line
  header_line="$(grep -n '^hard_gated_actions:' "$FB_RULES" | head -1 | cut -d: -f1)"
  entry_line="$(grep -n 'content_consilium_publish\|consilium_publish\|publish_gate' "$FB_RULES" | head -1 | cut -d: -f1)"
  [ -n "$header_line" ]
  [ -n "$entry_line" ]
  [ "$entry_line" -gt "$header_line" ]
}

# --- Test 4: gate aborts when final.md is missing (safety check) ---
@test "gate: exits non-zero when final.md is missing from run-dir" {
  rm -f "$RUN_DIR/final.md"
  run bash "${SCRIPT_DIR}/scripts/content_consilium_gate.sh" \
    --run-dir "$RUN_DIR" \
    --publish \
    --target "$PUBLISH_TARGET"
  [ "$status" -ne 0 ]
}
