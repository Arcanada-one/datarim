#!/usr/bin/env bash
# dr_orchestrate_router.sh — TUNE-0295 Phase A
# HTTP/1.1 request parser + router. Reads request from stdin, writes
# response to stdout. Pure-function: no listener, no fork. Invoked
# per connection by dr_orchestrate_server.sh (socat EXEC) and by
# tests directly via pipe.
#
# Env:
#   DR_ORCH_BODY_LIMIT          — max body bytes (default 65536)
#   DR_ORCH_TMUX_HANDLER        — script for /hooks/tmux*  (4-arg signature)
#   DR_ORCH_ORCH_HANDLER        — script for /hooks/orchestrator-input
#   DR_ORCH_CORS_ORIGIN         — fallback ACAO value when request has no Origin
#                                 OR Origin is not in allow-list. Default empty
#                                 (no ACAO emitted → cross-origin blocked).
#                                 Wildcard `*` requires DR_ORCH_CORS_ALLOW_WILDCARD=1.
#   DR_ORCH_CORS_ALLOWED_ORIGINS — whitespace-separated exact-match allow-list of
#                                  Origins permitted to be reflected verbatim in
#                                  ACAO. Default empty.
#   DR_ORCH_CORS_ALLOW_WILDCARD  — set to `1` to permit `DR_ORCH_CORS_ORIGIN=*`.
#                                  Default 0 (hard reject).
#   DR_ORCH_CORS_ALLOW_AUTH      — set to `1` to advertise `Authorization` in
#                                  Access-Control-Allow-Headers. Default 0 —
#                                  bearerAuth is deferred to a SEC-* task per
#                                  TUNE-0295 PRD Debate 1.
#
# Handler signature: <method> <path> <body-file> <headers-file>
# Handler stdout shape: <status>\r\n<header-lines>\r\n\r\n<body>
#
# V-AC: V-AC-1 (endpoint live), R6 (URI control-char defence),
#       R8 (header CRLF rejection), oversized body → 413,
#       F-sec-2 (CORS reflection hardening, TUNE-0295 Phase H).

set -o pipefail

: "${DR_ORCH_BODY_LIMIT:=65536}"
: "${DR_ORCH_CORS_ORIGIN:=}"
: "${DR_ORCH_CORS_ALLOWED_ORIGINS:=}"
: "${DR_ORCH_CORS_ALLOW_WILDCARD:=0}"
: "${DR_ORCH_CORS_ALLOW_AUTH:=0}"
: "${DR_ORCH_TMUX_HANDLER:=}"
: "${DR_ORCH_ORCH_HANDLER:=}"

# Fail-closed on wildcard CORS unless explicitly opted in. Bare `*` ACAO
# with Authorization in ACAH is a credentials-bearing wildcard which the
# Fetch spec forbids; the gate exists to prevent foot-gun configuration.
if [[ "$DR_ORCH_CORS_ORIGIN" == "*" ]] && [[ "$DR_ORCH_CORS_ALLOW_WILDCARD" != "1" ]]; then
  printf 'FATAL: DR_ORCH_CORS_ORIGIN=* requires DR_ORCH_CORS_ALLOW_WILDCARD=1 (TUNE-0295 F-sec-2)\n' >&2
  exit 6
fi

CRLF=$'\r\n'

# Lowercase a string (bash 3.2-compatible — `${var,,}` is bash 4+).
_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Globals for trap.
ROUTER_TMP=""
_cleanup() { [ -n "$ROUTER_TMP" ] && rm -rf "$ROUTER_TMP"; }
trap _cleanup EXIT

# ---- response helpers --------------------------------------------------

_reason() {
  case "$1" in
    200) echo "OK" ;;
    202) echo "Accepted" ;;
    204) echo "No Content" ;;
    400) echo "Bad Request" ;;
    404) echo "Not Found" ;;
    405) echo "Method Not Allowed" ;;
    410) echo "Gone" ;;
    413) echo "Payload Too Large" ;;
    500) echo "Internal Server Error" ;;
    503) echo "Service Unavailable" ;;
    *)   echo "OK" ;;
  esac
}

_emit() {
  # Emit HTTP/1.1 response. Args: status, headers-string (multi-line, each CRLF-terminated), body
  local status="$1" hdrs="$2" body="$3"
  local reason; reason="$(_reason "$status")"
  local cl=${#body}
  printf 'HTTP/1.1 %s %s\r\n' "$status" "$reason"
  printf '%s' "$hdrs"
  printf 'Content-Length: %d\r\n' "$cl"
  printf '\r\n'
  printf '%s' "$body"
}

# Resolve the ACAO value. Reflection happens ONLY when the request Origin
# matches an entry in DR_ORCH_CORS_ALLOWED_ORIGINS (whitespace-separated
# exact-match). Otherwise fall back to DR_ORCH_CORS_ORIGIN literal.
# Empty result ⇒ omit CORS headers entirely (cross-origin blocked).
_resolve_acao() {
  local origin="${1:-}"
  if [[ -n "$origin" ]] && [[ -n "$DR_ORCH_CORS_ALLOWED_ORIGINS" ]]; then
    local entry
    for entry in $DR_ORCH_CORS_ALLOWED_ORIGINS; do
      if [[ "$origin" == "$entry" ]]; then
        printf '%s' "$origin"
        return 0
      fi
    done
  fi
  # No reflection — emit static fallback (may be empty).
  printf '%s' "$DR_ORCH_CORS_ORIGIN"
}

_cors_headers() {
  local origin="${1:-}"
  local acao
  acao="$(_resolve_acao "$origin")"
  # Empty ACAO ⇒ omit all CORS headers (fail-closed default).
  if [[ -z "$acao" ]]; then
    return 0
  fi
  local acah='Content-Type, X-Sync-Timeout'
  if [[ "$DR_ORCH_CORS_ALLOW_AUTH" == "1" ]]; then
    acah="$acah, Authorization"
  fi
  printf 'Access-Control-Allow-Origin: %s\r\n' "$acao"
  printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n'
  printf 'Access-Control-Allow-Headers: %s\r\n' "$acah"
  printf 'Access-Control-Max-Age: 600\r\n'
  printf 'Vary: Origin\r\n'
}

_error() {
  # Emit error response with Connection: close. $2 (detail) reserved
  # for future audit-log hook — currently unused; status text suffices.
  local status="$1"
  local body
  body="$(printf '{"error":"%s","status":%s}' "$(_reason "$status")" "$status")"
  local hdrs
  hdrs="$(printf 'Content-Type: application/problem+json\r\nConnection: close\r\n')"
  _emit "$status" "$hdrs" "$body"
}

# ---- parser ------------------------------------------------------------

# Read CRLF-terminated line from stdin. Strips trailing \r.
_read_line() {
  local line
  IFS= read -r line || return 1
  printf '%s' "${line%$'\r'}"
}

# Validate URI: no control characters (\x00–\x1F, \x7F), no embedded CRLF
# (already stripped at line boundary but bare \r in middle would be caught
# by header CRLF guard separately).
_validate_uri() {
  local uri="$1"
  # Reject percent-encoded null/CR/LF as well.
  if [[ "$uri" == *%00* ]] || [[ "$uri" == *%0[aAdD]* ]]; then
    return 1
  fi
  # Reject literal control chars.
  if [[ "$uri" =~ [[:cntrl:]] ]]; then
    return 1
  fi
  return 0
}

# Header value validation: reject bare \r or \n inside the header
# value (CRLF injection). The line read already terminated on \n, but
# any embedded \r (without paired \n) survived as content — _read_line
# strips only the trailing \r.
_validate_header_value() {
  local v="$1"
  [[ "$v" != *$'\r'* ]] || return 1
  [[ "$v" != *$'\n'* ]] || return 1
  return 0
}

# Decode chunked body from stdin into TMP body file. Echoes 0 on
# success or non-zero on malformed input.
_read_chunked() {
  local out="$1" limit="$2"
  local total=0
  local size_line size_hex size
  while true; do
    size_line="$(_read_line)" || return 1
    # Strip optional chunk-extension after ';'.
    size_hex="${size_line%%;*}"
    # Hex format: ^[0-9a-fA-F]+$
    if [[ ! "$size_hex" =~ ^[0-9a-fA-F]+$ ]]; then
      return 1
    fi
    size=$((16#$size_hex))
    if [[ $size -eq 0 ]]; then
      # Consume trailer CRLF.
      _read_line >/dev/null || true
      return 0
    fi
    total=$((total + size))
    if [[ $total -gt $limit ]]; then
      return 2  # 413
    fi
    # Read exactly $size bytes (dd bs=1 — pipe-safe, no over-read).
    dd bs=1 count="$size" 2>/dev/null >>"$out"
    # Consume trailing CRLF.
    _read_line >/dev/null || return 1
  done
}

# ---- main --------------------------------------------------------------

main() {
  ROUTER_TMP="$(mktemp -d)"

  local body_file="$ROUTER_TMP/body"
  local headers_file="$ROUTER_TMP/headers"
  : >"$body_file"
  : >"$headers_file"

  # 1. Request line.
  local req_line; req_line="$(_read_line)" || { _error 400; return 0; }
  if [[ -z "$req_line" ]]; then _error 400; return 0; fi

  # Parse: METHOD SP URI SP HTTP/x.y
  local method uri version
  read -r method uri version <<<"$req_line" || { _error 400; return 0; }
  if [[ -z "$method" || -z "$uri" || -z "$version" ]]; then
    _error 400; return 0
  fi
  if [[ ! "$method" =~ ^[A-Z]+$ ]] || [[ ! "$version" =~ ^HTTP/1\.[01]$ ]]; then
    _error 400; return 0
  fi
  _validate_uri "$uri" || { _error 400; return 0; }

  # 2. Headers loop.
  local host_seen=0
  local content_length=0
  local transfer_encoding=""
  local origin=""
  local connection=""
  local line name value lower
  while true; do
    line="$(_read_line)" || break
    [[ -z "$line" ]] && break
    if [[ "$line" != *:* ]]; then
      _error 400; return 0
    fi
    name="${line%%:*}"
    value="${line#*:}"
    # Trim leading whitespace from value.
    value="${value#"${value%%[![:space:]]*}"}"
    _validate_header_value "$value" || { _error 400; return 0; }
    lower="$(_lc "$name")"
    case "$lower" in
      host) host_seen=1 ;;
      content-length)
        if [[ ! "$value" =~ ^[0-9]+$ ]]; then _error 400; return 0; fi
        content_length="$value"
        ;;
      transfer-encoding) transfer_encoding="$(_lc "$value")" ;;
      origin) origin="$value" ;;
      connection) connection="$(_lc "$value")" ;;
    esac
    # Persist for handler consumption.
    printf '%s: %s\r\n' "$name" "$value" >>"$headers_file"
  done

  # HTTP/1.1 requires Host header.
  if [[ "$version" == "HTTP/1.1" ]] && [[ $host_seen -eq 0 ]]; then
    _error 400; return 0
  fi

  # 3. Body.
  if [[ "$transfer_encoding" == "chunked" ]]; then
    local rc
    _read_chunked "$body_file" "$DR_ORCH_BODY_LIMIT"
    rc=$?
    if [[ $rc -eq 2 ]]; then _error 413; return 0; fi
    if [[ $rc -ne 0 ]]; then _error 400; return 0; fi
  elif [[ "$content_length" -gt 0 ]]; then
    if [[ "$content_length" -gt "$DR_ORCH_BODY_LIMIT" ]]; then
      _error 413; return 0
    fi
    # dd bs=1 — pipe-safe byte-exact read; head -c can over-buffer.
    dd bs=1 count="$content_length" 2>/dev/null >"$body_file"
  fi

  # 4. CORS preflight.
  if [[ "$method" == "OPTIONS" ]]; then
    local hdrs; hdrs="$(_cors_headers "$origin")"
    # Append connection-close for HTTP/1.0 default.
    if [[ "$version" == "HTTP/1.0" ]]; then
      hdrs="${hdrs}$(printf 'Connection: close\r\n')"
    fi
    _emit 204 "$hdrs" ""
    return 0
  fi

  # 5. Routing.
  local handler="" allowed=""
  case "$uri" in
    /hooks/tmux)
      handler="$DR_ORCH_TMUX_HANDLER"
      allowed="POST"
      ;;
    /hooks/tmux/job/*)
      handler="$DR_ORCH_TMUX_HANDLER"
      allowed="GET"
      ;;
    /hooks/orchestrator-input)
      handler="$DR_ORCH_ORCH_HANDLER"
      allowed="POST"
      ;;
    *)
      _error 404; return 0
      ;;
  esac

  if [[ ",$allowed," != *",${method},"* ]]; then
    local hdrs
    hdrs="$(printf 'Allow: %s\r\nContent-Type: application/problem+json\r\nConnection: close\r\n' "$allowed")"
    local body
    body="$(printf '{"error":"Method Not Allowed","status":405,"allow":"%s"}' "$allowed")"
    _emit 405 "$hdrs" "$body"
    return 0
  fi

  if [[ -z "$handler" ]] || [[ ! -x "$handler" ]]; then
    _error 500 "handler not configured"
    return 0
  fi

  # 6. Invoke handler.
  local handler_out
  if ! handler_out="$(bash "$handler" "$method" "$uri" "$body_file" "$headers_file" 2>/dev/null)"; then
    _error 500
    return 0
  fi

  # Handler output shape: <status>\r\n<header-lines>\r\n\r\n<body>
  local h_status h_rest h_headers h_body
  h_status="${handler_out%%$'\r\n'*}"
  h_rest="${handler_out#*$'\r\n'}"
  if [[ ! "$h_status" =~ ^[1-5][0-9][0-9]$ ]]; then
    _error 500
    return 0
  fi
  # Split rest on first blank line.
  h_headers="${h_rest%%$'\r\n\r\n'*}"
  if [[ "$h_rest" == *$'\r\n\r\n'* ]]; then
    h_body="${h_rest#*$'\r\n\r\n'}"
  else
    h_body=""
  fi
  # Ensure trailing CRLF on headers.
  if [[ -n "$h_headers" ]] && [[ "$h_headers" != *$'\r\n' ]]; then
    h_headers="${h_headers}${CRLF}"
  fi

  # Inject CORS for non-OPTIONS responses when Origin present.
  if [[ -n "$origin" ]]; then
    h_headers="${h_headers}$(_cors_headers "$origin")"
  fi

  # Connection handling: HTTP/1.0 default close; HTTP/1.1 honor request.
  if [[ "$version" == "HTTP/1.0" ]] || [[ "$connection" == "close" ]]; then
    h_headers="${h_headers}$(printf 'Connection: close\r\n')"
  else
    h_headers="${h_headers}$(printf 'Connection: keep-alive\r\n')"
  fi

  _emit "$h_status" "$h_headers" "$h_body"
}

main "$@"
