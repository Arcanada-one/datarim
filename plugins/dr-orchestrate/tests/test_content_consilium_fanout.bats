#!/usr/bin/env bats
# test_content_consilium_fanout.bats — TDD tests for content_consilium_fanout.sh
# Tests: 3-vendor full run-log; 2-of-3 degradation; <2 exits non-zero; hang→degrade.
# Requires: bats-core; macOS/Linux portable (no grep -P).

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FANOUT="$SCRIPT_DIR/scripts/content_consilium_fanout.sh"

setup() {
  export RUN_DIR
  RUN_DIR="$(mktemp -d)"
  # Write a minimal brief
  printf 'Write a short paragraph about the importance of testing.\n' > "$RUN_DIR/brief.md"

  # Default config with three stub vendors (command-only, no real CLIs in tests)
  export CONSILIUM_CONFIG
  CONSILIUM_CONFIG="$(mktemp)"
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "echo"
    args: ["DRAFT_A_DONE"]
  - slot: B
    cmd: "echo"
    args: ["DRAFT_B_DONE"]
  - slot: C
    cmd: "echo"
    args: ["DRAFT_C_DONE"]
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  # Stub tmux — not needed because fanout uses direct subprocess in test mode
  export DR_FANOUT_TEST_MODE=1
  export DR_ORCH_DIR="$SCRIPT_DIR"
}

teardown() {
  rm -rf "$RUN_DIR" "$CONSILIUM_CONFIG"
}

# --- Test 1: 3-vendor full run produces 3 draft files + 3-entry run-log ---
@test "3-vendor full run: produces draft-A.md, draft-B.md, draft-C.md" {
  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/draft-A.md" ]
  [ -f "$RUN_DIR/draft-B.md" ]
  [ -f "$RUN_DIR/draft-C.md" ]
}

@test "3-vendor full run: run-log.jsonl has exactly 3 entries" {
  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/run-log.jsonl" ]
  local count
  count="$(wc -l < "$RUN_DIR/run-log.jsonl" | tr -d ' ')"
  [ "$count" -eq 3 ]
}

@test "3-vendor full run: each run-log entry has vendor_slot and status fields" {
  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  grep -q '"vendor_slot"' "$RUN_DIR/run-log.jsonl"
  grep -q '"status"'      "$RUN_DIR/run-log.jsonl"
  # F4: run-log must also carry vendor, cli, session to prove vendor-distinctness (plan §4.2)
  grep -q '"vendor"'      "$RUN_DIR/run-log.jsonl"
  grep -q '"cli"'         "$RUN_DIR/run-log.jsonl"
  grep -q '"session"'     "$RUN_DIR/run-log.jsonl"
}

# --- Test 2: 2-of-3 degradation (one vendor unavailable) ---
@test "2-of-3 degradation: exits 0 when exactly one vendor fails" {
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "echo"
    args: ["DRAFT_A_DONE"]
  - slot: B
    cmd: "false"
    args: []
  - slot: C
    cmd: "echo"
    args: ["DRAFT_C_DONE"]
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/draft-A.md" ]
  [ -f "$RUN_DIR/draft-C.md" ]
}

@test "2-of-3 degradation: run-log records failed vendor with status=error" {
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "echo"
    args: ["DRAFT_A_DONE"]
  - slot: B
    cmd: "false"
    args: []
  - slot: C
    cmd: "echo"
    args: ["DRAFT_C_DONE"]
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  grep -q '"status":"error"' "$RUN_DIR/run-log.jsonl"
}

@test "2-of-3 degradation: degradation_note file is created" {
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "echo"
    args: ["DRAFT_A_DONE"]
  - slot: B
    cmd: "false"
    args: []
  - slot: C
    cmd: "echo"
    args: ["DRAFT_C_DONE"]
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/degradation_note.txt" ]
}

# --- Test 3: <2 vendors exits non-zero ---
@test "<2 vendors available: exits non-zero" {
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "false"
    args: []
  - slot: B
    cmd: "false"
    args: []
  - slot: C
    cmd: "false"
    args: []
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -ne 0 ]
}

@test "<2 vendors available: no draft files produced" {
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "false"
    args: []
  - slot: B
    cmd: "false"
    args: []
  - slot: C
    cmd: "false"
    args: []
hang_idle_secs: 5
hang_deadline_secs: 10
YAML

  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -ne 0 ]
  [ ! -f "$RUN_DIR/draft-A.md" ]
  [ ! -f "$RUN_DIR/draft-B.md" ]
  [ ! -f "$RUN_DIR/draft-C.md" ]
}

# --- Test 4: hang→degrade (a vendor produces no output within idle window) ---
@test "hang detection: hung vendor is treated as unavailable (2-of-3 proceeds)" {
  # Slot B hangs (sleeps longer than deadline)
  cat > "$CONSILIUM_CONFIG" << 'YAML'
vendors:
  - slot: A
    cmd: "echo"
    args: ["DRAFT_A_DONE"]
  - slot: B
    cmd: "sleep"
    args: ["30"]
  - slot: C
    cmd: "echo"
    args: ["DRAFT_C_DONE"]
hang_idle_secs: 1
hang_deadline_secs: 2
YAML

  run bash "$FANOUT" --brief "$RUN_DIR/brief.md" --run-dir "$RUN_DIR" --config "$CONSILIUM_CONFIG"
  [ "$status" -eq 0 ]
  [ -f "$RUN_DIR/draft-A.md" ]
  [ -f "$RUN_DIR/draft-C.md" ]
  grep -q '"status":"hung"' "$RUN_DIR/run-log.jsonl"
}
