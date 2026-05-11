#!/usr/bin/env bats
# outbound-devbot-noop.bats — V-AC-7: _emit_devbot no-op when env unset.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
BACKEND="$PLUGIN_ROOT/scripts/escalation_backend.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  export DR_ORCH_ESCALATION_MOCK_LOG="$TMP/escalation.jsonl"
  export DR_ORCH_PROMPT_TEXT="test pane text"
  unset DR_ORCH_ESCALATION_DEVBOT_URL || true
}

teardown() {
  rm -rf "$TMP"
}

_resolver_json() {
  printf '%s' '{"action":"/dr-do","confidence":0.30,"reason":"low","backend_used":"coworker-deepseek","subagent_model":"deepseek-chat"}'
}

# V-AC-7: DR_ORCH_ESCALATION_DEVBOT_URL unset → _emit_devbot exits 0 (no-op, silent)
@test "V-AC-7: _emit_devbot silent no-op when DEVBOT_URL unset" {
  run bash "$BACKEND" _emit_devbot "$(_resolver_json)" "test-session"
  [ "$status" -eq 0 ]
}

# V-AC-7: no stdout/stderr on no-op path (silent exit per Defensive Invariants)
@test "V-AC-7: no-op path produces no output" {
  out="$(bash "$BACKEND" _emit_devbot "$(_resolver_json)" "test-session" 2>&1)"
  [ -z "$out" ]
}

# V-AC-7: DR_ORCH_OUTBOUND_BACKEND=callback with DEVBOT_URL unset → still no-op
@test "V-AC-7: callback backend with no URL is no-op" {
  DR_ORCH_OUTBOUND_BACKEND=callback \
    run bash "$BACKEND" _emit_devbot "$(_resolver_json)" "test-session"
  [ "$status" -eq 0 ]
}

# Regression: DR_ORCH_ESCALATION_BACKEND=dev-bot should route to _emit_devbot
@test "regression: dev-bot backend routes to _emit_devbot (no-op with unset URL)" {
  DR_ORCH_ESCALATION_BACKEND=dev-bot \
    run bash "$BACKEND" emit "$(_resolver_json)" "test-pane"
  [ "$status" -eq 0 ]
}
