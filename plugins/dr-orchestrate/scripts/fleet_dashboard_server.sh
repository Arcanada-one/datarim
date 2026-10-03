#!/usr/bin/env bash
# fleet_dashboard_server.sh — Fleet observability dashboard (socat HTTP server).
#
# Serves static web/fleet-dashboard/ files and /fleet-graph.json endpoint
# via socat. Binds to a Tailscale mesh IP (Tier 2) — never 0.0.0.0.
#
# Usage:
#   fleet_dashboard_server.sh [--bind IP] [--port N] [--check] [--once] [--help]
#
# Security (F-sec-6 pattern from dr_orchestrate_server.sh):
#   - Refuses 0.0.0.0 bind unless DR_FLEET_DASHBOARD_ALLOW_ANY_BIND=1
#   - Default bind: DR_FLEET_DASHBOARD_BIND env (required for start mode)
#   - Allowed: loopback (127.0.0.1, ::1) or Tailscale CGNAT range 100.x.x.x
#
# Env:
#   DR_FLEET_DASHBOARD_BIND             Bind IP (no default — must be set)
#   DR_FLEET_DASHBOARD_PORT             Port (default 8765)
#   DR_FLEET_DASHBOARD_ALLOW_ANY_BIND   Set to 1 to permit non-mesh binds (not recommended)
#   DR_FLEET_METRICS_DIR                Directory containing fleet-graph.json

set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"

: "${DR_FLEET_DASHBOARD_PORT:=8765}"
: "${DR_FLEET_DASHBOARD_ALLOW_ANY_BIND:=0}"
: "${DR_FLEET_METRICS_DIR:=$PLUGIN_DIR/var/metrics}"

BIND_CLI=""
MODE="start"

# ── arg parser ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bind)   BIND_CLI="$2"; shift 2 ;;
    --port)   DR_FLEET_DASHBOARD_PORT="$2"; shift 2 ;;
    --check)  MODE="check"; shift ;;
    --once)   MODE="once"; shift ;;
    --help)
      printf 'usage: fleet_dashboard_server.sh [--bind IP] [--port N] [--check|--once]\n'
      printf 'Serves fleet dashboard on tailnet IP. Never binds 0.0.0.0.\n'
      exit 0
      ;;
    *) printf 'ERR: unknown flag %q\n' "$1" >&2; exit 1 ;;
  esac
done

# CLI --bind overrides env
[[ -n "$BIND_CLI" ]] && DR_FLEET_DASHBOARD_BIND="${BIND_CLI}"

# ── bind address validation (F-sec-6 pattern) ────────────────────────────────

_validate_bind() {
  local bind="${DR_FLEET_DASHBOARD_BIND:-}"

  # No bind address in check mode is allowed (we just print defaults)
  if [[ "$MODE" == "check" ]] && [[ -z "$bind" ]]; then
    return 0
  fi

  # If binding is required and not set
  if [[ -z "$bind" ]]; then
    printf 'ERR: DR_FLEET_DASHBOARD_BIND is required (set to Tailscale mesh IP)\n' >&2
    return 1
  fi

  # Refuse public/any bind unless explicitly allowed
  case "$bind" in
    0.0.0.0|"::"|"0:0:0:0:0:0:0:0")
      if [[ "$DR_FLEET_DASHBOARD_ALLOW_ANY_BIND" != "1" ]]; then
        printf 'FATAL: bind %s is prohibited (Tier 3 exposure). Set DR_FLEET_DASHBOARD_ALLOW_ANY_BIND=1 with operator justification.\n' "$bind"
        return 1
      fi
      printf 'WARN: permitting any-bind %s via DR_FLEET_DASHBOARD_ALLOW_ANY_BIND=1\n' "$bind" >&2
      ;;
    # Accept: loopback, Tailscale CGNAT 100.64.0.0/10, private RFC-1918
    127.*|::1|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*)
      ;;
    *)
      if [[ "$DR_FLEET_DASHBOARD_ALLOW_ANY_BIND" != "1" ]]; then
        printf 'ERR: bind address %s is not a recognized mesh/private IP. Set DR_FLEET_DASHBOARD_BIND to a Tailscale IP (100.x.x.x).\n' "$bind" >&2
        return 1
      fi
      ;;
  esac
  return 0
}

_check() {
  local bind="${DR_FLEET_DASHBOARD_BIND:-not-set}"
  _validate_bind || return 1
  printf 'bind=%s\nport=%s\nmetrics_dir=%s\nallow_any_bind=%s\n' \
    "$bind" "$DR_FLEET_DASHBOARD_PORT" \
    "$DR_FLEET_METRICS_DIR" "$DR_FLEET_DASHBOARD_ALLOW_ANY_BIND"
}

# ── HTTP handler ──────────────────────────────────────────────────────────────

_http_handler() {
  local metrics_dir="$DR_FLEET_METRICS_DIR"
  local web_root="$PLUGIN_DIR/web/fleet-dashboard"
  local request_line
  read -r request_line

  local path
  path=$(printf '%s' "$request_line" | awk '{print $2}')

  # Skip remaining headers
  while IFS= read -r header; do
    [[ "$header" == $'\r' ]] || [[ -z "$header" ]] && break
  done

  case "$path" in
    "/fleet-graph.json"|"/fleet-graph.json?"*)
      local snap_file="$metrics_dir/fleet-graph.json"
      if [[ -f "$snap_file" ]]; then
        local size
        size=$(wc -c < "$snap_file" | tr -d ' ')
        printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nAccess-Control-Allow-Origin: *\r\n\r\n' "$size"
        cat "$snap_file"
      else
        printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 15\r\n\r\n{"error":"none"}'
      fi
      ;;
    "/"|"/index.html")
      local html_file="$web_root/index.html"
      if [[ -f "$html_file" ]]; then
        local size
        size=$(wc -c < "$html_file" | tr -d ' ')
        printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: %s\r\n\r\n' "$size"
        cat "$html_file"
      else
        printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nnot found'
      fi
      ;;
    *)
      printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nnot found'
      ;;
  esac
}

export -f _http_handler
export DR_FLEET_METRICS_DIR PLUGIN_DIR

# ── main ──────────────────────────────────────────────────────────────────────

case "$MODE" in
  check)
    _check
    exit $?
    ;;
  once)
    _validate_bind || exit 1
    if ! command -v socat >/dev/null 2>&1; then
      printf 'ERR: socat not installed\n' >&2
      exit 2
    fi
    printf 'INFO: dashboard serving one connection on %s:%s\n' \
      "${DR_FLEET_DASHBOARD_BIND:-127.0.0.1}" "$DR_FLEET_DASHBOARD_PORT"
    socat -T 10 \
      "TCP-LISTEN:${DR_FLEET_DASHBOARD_PORT},bind=${DR_FLEET_DASHBOARD_BIND:-127.0.0.1},reuseaddr" \
      SYSTEM:'bash -c _http_handler',stderr,nofork
    ;;
  start)
    _validate_bind || exit 1
    if ! command -v socat >/dev/null 2>&1; then
      printf 'ERR: socat not installed (brew install socat / apt install socat)\n' >&2
      exit 2
    fi
    printf 'INFO: fleet dashboard on %s:%s (metrics: %s)\n' \
      "${DR_FLEET_DASHBOARD_BIND}" "$DR_FLEET_DASHBOARD_PORT" "$DR_FLEET_METRICS_DIR"
    exec socat -T 30 \
      "TCP-LISTEN:${DR_FLEET_DASHBOARD_PORT},bind=${DR_FLEET_DASHBOARD_BIND},reuseaddr,fork,max-children=20" \
      SYSTEM:'bash -c _http_handler',stderr
    ;;
esac
