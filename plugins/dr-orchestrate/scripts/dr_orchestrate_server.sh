#!/usr/bin/env bash
# dr_orchestrate_server.sh — TUNE-0295 Phase A
# Thin socat wrapper that binds 127.0.0.1:31415 (Tier 1 loopback) and
# invokes dr_orchestrate_router.sh per connection. Reads config from
# config/dr-orchestrate-server.yaml or env-var overrides.
#
# Usage:
#   dr_orchestrate_server.sh            — start listener (foreground)
#   dr_orchestrate_server.sh --check    — print effective config + exit 0
#   dr_orchestrate_server.sh --once     — accept exactly one connection (smoke)
#
# Env overrides:
#   DR_ORCH_BIND       — bind address (default 127.0.0.1)
#   DR_ORCH_PORT       — listen port  (default 31415)
#   DR_ORCH_MAX_CHILDREN — socat max-children (default 50)
#   DR_ORCH_BODY_LIMIT, DR_ORCH_TMUX_HANDLER, DR_ORCH_ORCH_HANDLER —
#       forwarded to router.

set -uo pipefail

: "${DR_ORCH_BIND:=127.0.0.1}"
: "${DR_ORCH_PORT:=31415}"
: "${DR_ORCH_MAX_CHILDREN:=50}"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTER="$PLUGIN_DIR/scripts/dr_orchestrate_router.sh"

: "${DR_ORCH_TMUX_HANDLER:=$PLUGIN_DIR/scripts/tmux_dispatcher.sh}"
: "${DR_ORCH_ORCH_HANDLER:=$PLUGIN_DIR/scripts/orchestrator-input-handler.sh}"

export DR_ORCH_TMUX_HANDLER DR_ORCH_ORCH_HANDLER
export DR_ORCH_BODY_LIMIT="${DR_ORCH_BODY_LIMIT:-65536}"

_check() {
  printf 'bind=%s\nport=%s\nmax_children=%s\nrouter=%s\ntmux_handler=%s\norch_handler=%s\nbody_limit=%s\n' \
    "$DR_ORCH_BIND" "$DR_ORCH_PORT" "$DR_ORCH_MAX_CHILDREN" \
    "$ROUTER" "$DR_ORCH_TMUX_HANDLER" "$DR_ORCH_ORCH_HANDLER" \
    "$DR_ORCH_BODY_LIMIT"
}

_preflight() {
  if ! command -v socat >/dev/null 2>&1; then
    echo "ERR: socat not installed (install via 'apt install socat' or 'brew install socat')" >&2
    return 2
  fi
  if [[ ! -x "$ROUTER" ]]; then
    echo "ERR: router not executable: $ROUTER" >&2
    return 2
  fi
  # Probe port: refuse if already in use.
  if exec 9<>/dev/tcp/"$DR_ORCH_BIND"/"$DR_ORCH_PORT" 2>/dev/null; then
    exec 9>&-
    echo "ERR: port $DR_ORCH_BIND:$DR_ORCH_PORT already in use" >&2
    return 3
  fi
}

case "${1:-start}" in
  --check) _check; exit 0 ;;
  --once)
    _preflight || exit $?
    exec socat -T 30 \
      TCP-LISTEN:"$DR_ORCH_PORT",bind="$DR_ORCH_BIND",reuseaddr \
      EXEC:"bash $ROUTER",stderr,nofork
    ;;
  start|"")
    _preflight || exit $?
    exec socat -T 30 \
      TCP-LISTEN:"$DR_ORCH_PORT",bind="$DR_ORCH_BIND",reuseaddr,fork,max-children="$DR_ORCH_MAX_CHILDREN" \
      EXEC:"bash $ROUTER",stderr
    ;;
  *)
    echo "usage: $0 [start|--check|--once]" >&2
    exit 2
    ;;
esac
