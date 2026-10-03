#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RESOLVER="$PLUGIN_ROOT/scripts/resolver.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export DR_ORCH_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export STATE_DIR="$DR_ORCH_STATE_DIR"
  export DR_ORCH_RULES_DEFAULT="$BATS_TEST_TMPDIR/default.yaml"
  export DR_ORCH_RULES_USER="$BATS_TEST_TMPDIR/user.yaml"
  export DR_ORCH_RULES_LEARNED="$BATS_TEST_TMPDIR/learned.yaml"
  export DR_ORCH_AUDIT_FILE="$BATS_TEST_TMPDIR/audit.jsonl"
  mkdir -p "$HOME"

  cat > "$DR_ORCH_RULES_DEFAULT" <<'YAML'
patterns:
  - match: plan
    action: "/dr-plan"
    confidence: 0.95
  - match: do
    action: "/dr-do"
    confidence: 0.95
  - match: qa
    action: "/dr-qa"
    confidence: 0.95
  - match: status
    action: "/dr-status"
    confidence: 0.95
YAML
  printf 'patterns: []\n' > "$DR_ORCH_RULES_USER"
  printf 'patterns: []\n' > "$DR_ORCH_RULES_LEARNED"
}

run_resolver() {
  run "$RESOLVER" "$@"
}

history_file() {
  printf '%s/resolver-history.jsonl\n' "$DR_ORCH_STATE_DIR"
}

@test "record normalizes intent, canonicalizes trusted dr action, and hardens state" {
  run_resolver record $'  tune\t  request  ' dr-plan 1
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }

  local history
  history="$(history_file)"
  [ "$(jq -r '.intent' "$history")" = "tune request" ] \
    && [ "$(jq -r '.action' "$history")" = "/dr-plan" ] \
    && [ "$(jq -r '.exit_code' "$history")" = "1" ] \
    && [ "$(stat -c '%a' "$DR_ORCH_STATE_DIR")" = "700" ] \
    && [ "$(stat -c '%a' "$history")" = "600" ] \
    && [ "$(stat -c '%a' "$DR_ORCH_STATE_DIR/.resolver-history.lock")" = "600" ]
}

@test "record accepts a trusted explicit user action" {
  cat > "$DR_ORCH_RULES_USER" <<'YAML'
patterns:
  - match: custom
    action: "/dr-custom"
    confidence: 0.90
YAML

  run_resolver record tune dr-custom 0
  [ "$status" -eq 0 ] \
    && [ "$(jq -r '.action' "$(history_file)")" = "/dr-custom" ]
}

@test "record rejects actions absent from the default and user registry" {
  run_resolver record tune dr-unknown 0
  [ "$status" -ne 0 ] \
    && [ ! -e "$(history_file)" ]
}

@test "learned rules never extend the trusted registry" {
  cat > "$DR_ORCH_RULES_LEARNED" <<'YAML'
patterns:
  - match: learned
    action: "/dr-learned-only"
    confidence: 1.0
YAML

  run_resolver record tune dr-learned-only 0
  [ "$status" -ne 0 ] \
    && [ ! -e "$(history_file)" ]
}

@test "invalid intents and exit codes are rejected without mutation" {
  local candidate
  for candidate in "" "-option" "../escape" "path/component" 'x;touch-canary' $'line\nbreak' $'bad\xFF'; do
    run_resolver record "$candidate" dr-plan 0
    [ "$status" -ne 0 ] || return 1
  done
  run_resolver record tune dr-plan not-an-integer
  [ "$status" -ne 0 ] || return 1
  run_resolver record tune dr-plan 256
  [ "$status" -ne 0 ] \
    && [ ! -e "$(history_file)" ]
}

@test "shell metacharacter input is inert as well as rejected" {
  local canary="$BATS_TEST_TMPDIR/injection-canary"
  run_resolver record '$(touch '"$canary"')' dr-plan 0
  [ "$status" -ne 0 ] \
    && [ ! -e "$canary" ] \
    && [ ! -e "$(history_file)" ]
}

@test "suggest returns the sole trusted failed action for compatibility" {
  run_resolver record tune dr-plan 1
  [ "$status" -eq 0 ] || return 1
  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-plan" ]
}

@test "ranking prefers success count descending" {
  run_resolver record tune dr-plan 0
  run_resolver record tune dr-do 0
  run_resolver record tune dr-do 0
  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-do" ]
}

@test "a successful distinct alternative outranks a repeatedly failed action" {
  run_resolver record tune dr-plan 1
  run_resolver record tune dr-plan 2
  run_resolver record tune dr-plan 3
  run_resolver record tune dr-do 0
  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-do" ]
}

@test "ranking prefers failure count ascending after equal success count" {
  run_resolver record tune dr-plan 0
  run_resolver record tune dr-plan 1
  run_resolver record tune dr-do 0
  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-do" ]
}

@test "ranking prefers latest success descending after equal counts" {
  DR_ORCH_NOW_EPOCH=100 run_resolver record tune dr-plan 0
  DR_ORCH_NOW_EPOCH=200 run_resolver record tune dr-do 0
  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-do" ]
}

@test "ranking uses lexical action as the deterministic final tie-break" {
  DR_ORCH_NOW_EPOCH=100 run_resolver record tune dr-plan 0
  DR_ORCH_NOW_EPOCH=100 run_resolver record tune dr-do 0
  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-do" ]
}

@test "suggest normalizes whitespace but preserves case distinctions" {
  run_resolver record $' tune\trequest ' dr-plan 0
  run_resolver record "Tune request" dr-do 0
  run_resolver suggest_alternative "  tune   request"
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-plan" ]
}

@test "corrupt history is ignored and produces an audit event" {
  mkdir -p "$DR_ORCH_STATE_DIR"
  chmod 700 "$DR_ORCH_STATE_DIR"
  {
    printf '%s\n' '{broken-json'
    jq -nc '{intent:"tune",action:"/dr-plan",exit_code:0,timestamp:100}'
  } > "$(history_file)"
  chmod 600 "$(history_file)"

  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ "$output" = "/dr-plan" ] \
    && [ "$(stat -c '%a' "$DR_ORCH_AUDIT_FILE")" = "600" ] \
    && jq -e 'select(.event_type == "resolver_history_corrupt" and .corrupt_count == 1)' \
      "$DR_ORCH_AUDIT_FILE" >/dev/null
}

@test "manually injected untrusted actions are never suggested" {
  mkdir -p "$DR_ORCH_STATE_DIR"
  chmod 700 "$DR_ORCH_STATE_DIR"
  jq -nc '{intent:"tune",action:"/dr-untrusted",exit_code:0,timestamp:100}' \
    > "$(history_file)"
  chmod 600 "$(history_file)"

  run_resolver suggest_alternative tune
  [ "$status" -eq 0 ] \
    && [ -z "$output" ]
}

@test "rotation retains exactly the newest 5000 valid records" {
  mkdir -p "$DR_ORCH_STATE_DIR"
  chmod 700 "$DR_ORCH_STATE_DIR"
  local i
  for i in $(seq 1 5001); do
    jq -nc --argjson ts "$i" \
      '{intent:"tune",action:"/dr-plan",exit_code:0,timestamp:$ts}'
  done > "$(history_file)"
  chmod 600 "$(history_file)"

  DR_ORCH_NOW_EPOCH=6000 run_resolver record tune dr-do 0
  [ "$status" -eq 0 ] \
    && [ "$(wc -l < "$(history_file)")" -eq 5000 ] \
    && [ "$(head -1 "$(history_file)" | jq -r '.timestamp')" -eq 3 ] \
    && [ "$(tail -1 "$(history_file)" | jq -r '.timestamp')" -eq 6000 ]
}

@test "rotation caps valid history at one MiB while retaining the newest suffix" {
  mkdir -p "$DR_ORCH_STATE_DIR"
  chmod 700 "$DR_ORCH_STATE_DIR"
  python3 - "$(history_file)" <<'PY'
import json
import sys

path = sys.argv[1]
intent = "x" * 240
with open(path, "w", encoding="utf-8") as stream:
    for stamp in range(1, 4001):
        stream.write(json.dumps({
            "intent": intent,
            "action": "/dr-plan",
            "exit_code": 0,
            "timestamp": stamp,
        }, separators=(",", ":")) + "\n")
PY
  chmod 600 "$(history_file)"

  DR_ORCH_NOW_EPOCH=5000 run_resolver record tune dr-do 0
  [ "$status" -eq 0 ] \
    && [ "$(wc -c < "$(history_file)")" -le 1048576 ] \
    && [ "$(tail -1 "$(history_file)" | jq -r '.timestamp')" -eq 5000 ] \
    && [ "$(head -1 "$(history_file)" | jq -r '.timestamp')" -gt 1 ]
}

@test "concurrent records all survive the shared history lock" {
  # The property under test is "the shared lock serialises 40 concurrent
  # writers without losing a record" — the assertions below are unchanged.
  #
  # resolver.sh defaults DR_ORCH_LOCK_TIMEOUT to 5s. On a loaded CI runner,
  # 40 forked writers can queue longer than that; the losers exit 2 and drop
  # their record, so the suite failed by wall-clock luck rather than by any
  # defect in the locking. Pin a generous, explicit budget so the outcome
  # depends on the lock's correctness and not on the scheduler.
  export DR_ORCH_LOCK_TIMEOUT=60

  run bash -c '
    set -euo pipefail
    resolver="$1"
    for i in $(seq 1 40); do
      DR_ORCH_NOW_EPOCH="$i" "$resolver" record tune dr-plan 0 &
    done
    wait
  ' _ "$RESOLVER"
  [ "$status" -eq 0 ] \
    && [ "$(wc -l < "$(history_file)")" -eq 40 ] \
    && [ "$(jq -s 'map(.timestamp) | unique | length' "$(history_file)")" -eq 40 ]
}

@test "symlinked state and history paths fail closed" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  ln -s "$outside" "$DR_ORCH_STATE_DIR"
  run_resolver record tune dr-plan 0
  [ "$status" -ne 0 ] || return 1

  rm -f "$DR_ORCH_STATE_DIR"
  mkdir -p "$DR_ORCH_STATE_DIR"
  chmod 700 "$DR_ORCH_STATE_DIR"
  ln -s "$outside/history" "$(history_file)"
  run_resolver record tune dr-plan 0
  [ "$status" -ne 0 ] \
    && [ ! -e "$outside/history" ]
}
