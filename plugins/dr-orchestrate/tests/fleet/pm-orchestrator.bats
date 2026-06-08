#!/usr/bin/env bats
# pm-orchestrator.bats — V-AC-5: PM timeout/unblock/reassign/kill commands.
# Contract tests run without Redis. Integration tests skip when Redis absent.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
PM="$PLUGIN_ROOT/scripts/fleet_pm_orchestrator.sh"
STATUS="$PLUGIN_ROOT/scripts/fleet_status_adapter.sh"

REDIS_URL="${DR_ORCH_REDIS_URL:-redis://127.0.0.1:6379}"

setup() {
  TMP="$(mktemp -d)"
  export DR_FLEET_BUS_BACKEND=mock
  export DR_FLEET_MOCK_LOG="$TMP/mock.log"
  export DR_FLEET_MOCK_XADD_ID="1700000000000-0"
  export DR_ORCH_REDIS_URL="$REDIS_URL"
  # Use temp tasks.md for status adapter tests
  export DR_FLEET_TASKS_FILE="$TMP/tasks.md"
  cat > "$DR_FLEET_TASKS_FILE" <<'TASKSMD'
<!-- thin-index -->
| ID | Title | L | Status | Since |
|----|-------|---|--------|-------|
| TUNE-0001 | Test task one | L2 | in_progress | 2026-06-01 |
| TUNE-0002 | Test task two | L3 | pending | 2026-06-01 |
TASKSMD
  REDIS_AVAILABLE=0
  if command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$REDIS_URL" ping 2>/dev/null | grep -q PONG; then
    REDIS_AVAILABLE=1
  fi
}

teardown() {
  rm -rf "$TMP"
}

# ── PM orchestrator executable + help ────────────────────────────────────────

@test "V-AC-5: fleet_pm_orchestrator.sh is executable" {
  [ -x "$PM" ]
}

@test "V-AC-5: fleet_pm_orchestrator.sh --help exits 0" {
  run bash "$PM" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "V-AC-5: --check mode shows config and exits 0" {
  run bash "$PM" --check
  [ "$status" -eq 0 ]
}

# ── status adapter ─────────────────────────────────────────────────────────────

@test "V-AC-5: fleet_status_adapter.sh is executable" {
  [ -x "$STATUS" ]
}

@test "V-AC-5: fleet_status_adapter.sh --help exits 0" {
  run bash "$STATUS" --help
  [ "$status" -eq 0 ]
}

@test "V-AC-5: status_get function exists" {
  run bash -c "source '$STATUS' && declare -f status_get"
  [ "$status" -eq 0 ]
}

@test "V-AC-5: status_update function exists" {
  run bash -c "source '$STATUS' && declare -f status_update"
  [ "$status" -eq 0 ]
}

# ── status_get from tasks.md ──────────────────────────────────────────────────

@test "V-AC-5: status_get returns status from tasks.md" {
  run bash -c "
    export DR_FLEET_TASKS_FILE='$TMP/tasks.md'
    source '$STATUS'
    status_get 'TUNE-0001'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"in_progress"* ]]
}

@test "V-AC-5: status_get returns pending for TUNE-0002" {
  run bash -c "
    export DR_FLEET_TASKS_FILE='$TMP/tasks.md'
    source '$STATUS'
    status_get 'TUNE-0002'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"pending"* ]]
}

@test "V-AC-5: status_get returns unknown for non-existent task" {
  run bash -c "
    export DR_FLEET_TASKS_FILE='$TMP/tasks.md'
    source '$STATUS'
    status_get 'TUNE-9999'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
}

# ── status_update writes to tasks.md ─────────────────────────────────────────

@test "V-AC-5: status_update changes status in tasks.md" {
  run bash -c "
    export DR_FLEET_TASKS_FILE='$TMP/tasks.md'
    export DR_FLEET_BUS_BACKEND=mock
    export DR_FLEET_MOCK_LOG='$TMP/mock.log'
    source '$STATUS'
    status_update 'TUNE-0001' 'blocked' 'timeout exceeded'
    status_get 'TUNE-0001'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"blocked"* ]]
}

@test "V-AC-5: status_update publishes event to bus (mock)" {
  run bash -c "
    export DR_FLEET_TASKS_FILE='$TMP/tasks.md'
    export DR_FLEET_BUS_BACKEND=mock
    export DR_FLEET_MOCK_LOG='$TMP/mock2.log'
    source '$STATUS'
    status_update 'TUNE-0001' 'blocked' 'pm-timeout'
  "
  [ "$status" -eq 0 ]
  grep -q 'XADD' "$TMP/mock2.log"
}

# ── PM commands ──────────────────────────────────────────────────────────────

@test "V-AC-5: PM unblock-task publishes event" {
  run bash "$PM" unblock-task TUNE-0001
  [ "$status" -eq 0 ]
  grep -q 'XADD' "$TMP/mock.log"
}

@test "V-AC-5: PM reassign-level publishes level-reassigned event" {
  run bash "$PM" reassign-level TUNE-0001 L1
  [ "$status" -eq 0 ]
  grep -q 'level-reassigned' "$TMP/mock.log"
}

@test "V-AC-5: PM kill-agent requires session id" {
  run bash "$PM" kill-agent
  [ "$status" -ne 0 ]
}

@test "V-AC-5: PM timeout-check exits 0 in check mode" {
  run bash "$PM" timeout-check --dry-run
  [ "$status" -eq 0 ]
}
