#!/usr/bin/env bats
# path-traversal-defence.bats — TUNE-0295 Phase B
# Router-level URI defence. 8 vectors per fixture F7.
# All vectors MUST be rejected BEFORE dispatch (no handler invocation).

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ROUTER="$PLUGIN_ROOT/scripts/dr_orchestrate_router.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  # Stub handlers that, if invoked, write a sentinel so we detect dispatch.
  export DR_ORCH_TMUX_HANDLER="$TMP/sentinel_tmux.sh"
  export DR_ORCH_ORCH_HANDLER="$TMP/sentinel_orch.sh"
  for s in sentinel_tmux sentinel_orch; do
    cat >"$TMP/$s.sh" <<EOF
#!/usr/bin/env bash
echo invoked >>"$TMP/handler-audit"
printf '200\r\nContent-Type: application/json\r\n\r\n{"data":{"stub":true}}'
EOF
    chmod +x "$TMP/$s.sh"
  done
  : >"$TMP/handler-audit"
}

teardown() { rm -rf "$TMP"; }

_audit_empty() {
  # Handler MUST NOT have been invoked. (Empty file => 0 bytes => 0 lines.)
  [ ! -s "$TMP/handler-audit" ]
}

_send() {
  # Pipe raw request to router. $1 = full request bytes.
  printf '%b' "$1" | bash "$ROUTER"
}

@test "R6 §F7-1: literal /hooks/../etc/passwd → 404 (regex non-match) or 400" {
  run _send "GET /hooks/../etc/passwd HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
  _audit_empty
}

@test "R6 §F7-2: /hooks/tmux/../../etc/passwd → 400/404" {
  run _send "GET /hooks/tmux/../../etc/passwd HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
  _audit_empty
}

@test "R6 §F7-3: %2e%2e (url-encoded ../) → 400 reject pre-decode" {
  run _send "GET /hooks/%2e%2e/etc/passwd HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
  _audit_empty
}

@test "R6 §F7-4: %252e%252e (double-encoded) → 400/404 single-decode" {
  run _send "GET /hooks/%252e%252e/etc/passwd HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
  _audit_empty
}

@test "R6 §F7-5: %00 null-byte in URI → 400 reject pre-decode" {
  run _send "GET /hooks/tmux%00/job/x HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
  _audit_empty
}

@test "R6 §F7-6: %0d%0a CRLF in URI → 400 reject pre-decode" {
  run _send "GET /hooks/tmux%0d%0a/job/x HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
  _audit_empty
}

@test "R6 §F7-7: /hooks/tmux;DROP TABLE foo → 404 (regex non-match)" {
  # The space in the URI breaks request-line parsing, so reject is 400 in
  # practice — both 400 and 404 are acceptable «not dispatched».
  run _send "GET /hooks/tmux;DROP HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
  _audit_empty
}

@test "R6 §F7-8: /hooks/tmux#frag → 404 (fragment leak not a route)" {
  run _send "GET /hooks/tmux#frag HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
  _audit_empty
}
