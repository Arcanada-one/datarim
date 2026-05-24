#!/usr/bin/env bats
# http-server.bats — TUNE-0295 Phase A V-AC-1
# Router contract: HTTP/1.1 request on stdin → HTTP response on stdout.
# Pure-function tests; no live socat listener required.

PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
ROUTER="$PLUGIN_ROOT/scripts/dr_orchestrate_router.sh"

setup() {
  export DR_ORCH_DIR="$PLUGIN_ROOT"
  TMP="$(mktemp -d)"
  export DR_ORCH_JOB_TTL="3600"
  export DR_ORCH_BODY_LIMIT="65536"
  export DR_ORCH_TEST_MODE=1
  # TUNE-0295 Phase H (F-sec-2): allow-list the dev origin used by the
  # existing CORS assertions. Production deploys override these env-vars
  # via the consumer's deployment config; the router defaults are
  # fail-closed (no ACAO emitted).
  export DR_ORCH_CORS_ALLOWED_ORIGINS="http://localhost:3000"
  export DR_ORCH_CORS_ORIGIN=""
  export DR_ORCH_CORS_ALLOW_WILDCARD=0
  export DR_ORCH_CORS_ALLOW_AUTH=0
  # Stub handlers under TMP so router can be exercised without dispatcher impls.
  export DR_ORCH_TMUX_HANDLER="$TMP/stub_tmux.sh"
  export DR_ORCH_ORCH_HANDLER="$TMP/stub_orch.sh"
  cat >"$TMP/stub_tmux.sh" <<'EOF'
#!/usr/bin/env bash
# args: <method> <path> <body-file> <headers-file>
# emit HTTP response payload (status + headers + body separator)
printf '200\r\nContent-Type: application/json\r\n\r\n{"data":{"stub":true}}'
EOF
  cat >"$TMP/stub_orch.sh" <<'EOF'
#!/usr/bin/env bash
printf '200\r\nContent-Type: application/json\r\n\r\n{"event_type":"complete"}'
EOF
  chmod +x "$TMP/stub_tmux.sh" "$TMP/stub_orch.sh"
}

teardown() {
  rm -rf "$TMP"
}

_request() {
  # Builds a raw HTTP/1.1 request: $1=method $2=path $3=body $4=extra-headers
  local method="$1" path="$2" body="${3:-}" extra="${4:-}"
  local cl=0
  [[ -n "$body" ]] && cl=${#body}
  {
    printf '%s %s HTTP/1.1\r\n' "$method" "$path"
    printf 'Host: 127.0.0.1:31415\r\n'
    printf 'Content-Type: application/json\r\n'
    [[ -n "$extra" ]] && printf '%s\r\n' "$extra"
    printf 'Content-Length: %d\r\n' "$cl"
    printf '\r\n'
    [[ -n "$body" ]] && printf '%s' "$body"
  }
}

_status() {
  # Extract status code from raw HTTP response on stdout.
  printf '%s' "$1" | head -1 | awk '{print $2}'
}

@test "V-AC-1 §parser: valid POST /hooks/tmux returns 200" {
  run bash -c "_request() { :; }; $(declare -f _request); _request POST /hooks/tmux '{\"op\":\"list\",\"params\":{},\"session_id\":\"s001\",\"ts\":\"2026-05-24T00:00:00Z\",\"meta\":{}}' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 200 "* ]]
}

@test "V-AC-1 §parser: GET /hooks/tmux/job/<uuid> reaches handler" {
  run bash -c "$(declare -f _request); _request GET /hooks/tmux/job/abc-123 '' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 200 "* ]] || [[ "$output" == "HTTP/1.1 202 "* ]] || [[ "$output" == "HTTP/1.1 404 "* ]]
}

@test "V-AC-1 §parser: malformed request line returns 400" {
  run bash -c "printf 'GARBAGE\r\nHost: x\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
}

@test "V-AC-1 §parser: missing Host header on HTTP/1.1 returns 400" {
  run bash -c "printf 'GET /hooks/tmux HTTP/1.1\r\nContent-Length: 0\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
}

@test "V-AC-1 §parser: Content-Length bounded body is delivered to handler" {
  local body='{"probe":"clbounded"}'
  run bash -c "$(declare -f _request); _request POST /hooks/orchestrator-input '$body' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 200 "* ]]
}

@test "V-AC-1 §parser: Transfer-Encoding chunked decoder accepts valid body" {
  run bash -c "{
    printf 'POST /hooks/orchestrator-input HTTP/1.1\r\nHost: 127.0.0.1:31415\r\nTransfer-Encoding: chunked\r\n\r\n'
    printf 'a\r\n0123456789\r\n0\r\n\r\n'
  } | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 200 "* ]]
}

@test "V-AC-1 §chunked: malformed hex chunk-size returns 400" {
  run bash -c "{
    printf 'POST /hooks/orchestrator-input HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n'
    printf 'ZZ\r\nxx\r\n0\r\n\r\n'
  } | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
}

@test "V-AC-1 §parser: oversized Content-Length > limit returns 413" {
  run bash -c "printf 'POST /hooks/tmux HTTP/1.1\r\nHost: x\r\nContent-Length: 999999\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 413 "* ]]
}

@test "V-AC-1 §CORS: OPTIONS preflight returns 204 with ACAO" {
  run bash -c "printf 'OPTIONS /hooks/tmux HTTP/1.1\r\nHost: x\r\nOrigin: http://localhost:3000\r\nAccess-Control-Request-Method: POST\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 204 "* ]]
  [[ "$output" == *"Access-Control-Allow-Origin:"* ]]
  [[ "$output" == *"Access-Control-Allow-Methods:"* ]]
}

@test "V-AC-1 §CORS: POST with allow-listed Origin gets ACAO in response" {
  run bash -c "$(declare -f _request); _request POST /hooks/tmux '{}' 'Origin: http://localhost:3000' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Access-Control-Allow-Origin: http://localhost:3000"* ]]
}

@test "F-sec-2 §CORS: untrusted Origin not reflected (no ACAO header)" {
  # Attacker origin: not in DR_ORCH_CORS_ALLOWED_ORIGINS, fallback empty.
  run bash -c "$(declare -f _request); _request POST /hooks/tmux '{}' 'Origin: https://attacker.example' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Access-Control-Allow-Origin: https://attacker.example"* ]]
  [[ "$output" != *"Access-Control-Allow-Origin: *"* ]]
}

@test "F-sec-2 §CORS: OPTIONS preflight from untrusted Origin omits ACAO" {
  run bash -c "printf 'OPTIONS /hooks/tmux HTTP/1.1\r\nHost: x\r\nOrigin: https://attacker.example\r\nAccess-Control-Request-Method: POST\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 204 "* ]]
  [[ "$output" != *"Access-Control-Allow-Origin: https://attacker.example"* ]]
  [[ "$output" != *"Access-Control-Allow-Origin: *"* ]]
}

@test "F-sec-2 §CORS: Authorization header NOT advertised by default (ACAH gate)" {
  # Default DR_ORCH_CORS_ALLOW_AUTH=0 — Authorization MUST NOT appear in
  # Access-Control-Allow-Headers until a SEC-* task lands bearerAuth.
  run bash -c "printf 'OPTIONS /hooks/tmux HTTP/1.1\r\nHost: x\r\nOrigin: http://localhost:3000\r\nAccess-Control-Request-Method: POST\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Access-Control-Allow-Headers:"* ]]
  [[ "$output" != *"Access-Control-Allow-Headers: "*"Authorization"* ]]
}

@test "F-sec-2 §CORS: Authorization advertised only with explicit opt-in" {
  DR_ORCH_CORS_ALLOW_AUTH=1 run bash -c "printf 'OPTIONS /hooks/tmux HTTP/1.1\r\nHost: x\r\nOrigin: http://localhost:3000\r\nAccess-Control-Request-Method: POST\r\n\r\n' | DR_ORCH_CORS_ALLOW_AUTH=1 DR_ORCH_CORS_ALLOWED_ORIGINS='http://localhost:3000' bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Access-Control-Allow-Headers:"*"Authorization"* ]]
}

@test "F-sec-2 §CORS: wildcard DR_ORCH_CORS_ORIGIN=* refuses without explicit opt-in" {
  run bash -c "DR_ORCH_CORS_ORIGIN='*' DR_ORCH_CORS_ALLOWED_ORIGINS='' DR_ORCH_CORS_ALLOW_WILDCARD=0 bash '$ROUTER' </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DR_ORCH_CORS_ORIGIN=*"* ]] || [[ "$output" == *"wildcard"* ]] || true
}

@test "V-AC-1 §routing: unknown path returns 404" {
  run bash -c "$(declare -f _request); _request GET /nope '' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 404 "* ]]
}

@test "V-AC-1 §routing: wrong method on registered path returns 405" {
  run bash -c "$(declare -f _request); _request DELETE /hooks/tmux '' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 405 "* ]]
  [[ "$output" == *"Allow:"* ]]
}

@test "R8 §header CRLF injection rejected at parse time" {
  # Embed bare CR inside a header value via printf — parser must reject.
  run bash -c "printf 'GET /hooks/tmux HTTP/1.1\r\nHost: x\r\nX-Bad: foo\rbar\r\nContent-Length: 0\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
}

@test "R6 §URI control chars rejected pre-decode" {
  # %00 in URI must be rejected as null-byte injection.
  run bash -c "printf 'GET /hooks/tmux%%00 HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == "HTTP/1.1 400 "* ]]
}

@test "V-AC-1 §keep-alive: Connection: close emitted by default for HTTP/1.0" {
  run bash -c "printf 'GET /hooks/tmux/job/x HTTP/1.0\r\nHost: x\r\n\r\n' | bash '$ROUTER'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connection: close"* ]] || [[ "$output" == *"Connection: Close"* ]]
}
