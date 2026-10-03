#!/usr/bin/env bash
# fleet_obs_aggregator.sh — Fleet observability aggregator.
#
# Reads from fleet:task-events and fleet:audit-log to build a force-directed
# graph snapshot stored as var/metrics/fleet-graph.json.
#
# Usage:
#   fleet_obs_aggregator.sh [--snapshot] [--check] [--help]
#   fleet_obs_aggregator.sh --once    — process one batch from Redis
#
# Modes:
#   --snapshot  Write fleet-graph.json from current state (mock or Redis)
#   --check     Print config and exit 0
#   --once      Subscribe one batch to obs consumer group and snapshot
#   (default)   Continuous loop
#
# Env:
#   DR_ORCH_REDIS_URL       Redis URL (default redis://127.0.0.1:6379)
#   DR_FLEET_BUS_BACKEND    "redis" or "mock" (default redis)
#   DR_FLEET_METRICS_DIR    Output directory (default: <plugin>/var/metrics)

set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
BUS_ADAPTER="$PLUGIN_DIR/scripts/bus_adapter.sh"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_FLEET_METRICS_DIR:=$PLUGIN_DIR/var/metrics}"

MODE="loop"

# ── arg parser ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot) MODE="snapshot"; shift ;;
    --check)    MODE="check"; shift ;;
    --once)     MODE="once"; shift ;;
    --help)
      printf 'usage: fleet_obs_aggregator.sh [--snapshot|--check|--once|--help]\n'
      printf 'Writes fleet-graph.json to DR_FLEET_METRICS_DIR.\n'
      exit 0
      ;;
    *) printf 'ERR: unknown flag %q\n' "$1" >&2; exit 1 ;;
  esac
done

# ── snapshot writer ───────────────────────────────────────────────────────────

_write_snapshot() {
  mkdir -p "$DR_FLEET_METRICS_DIR"

  local snapshot_file="$DR_FLEET_METRICS_DIR/fleet-graph.json"
  local ts
  ts="$(date -u +%FT%TZ)"

  # Collect nodes and edges from Redis if available; emit minimal structure
  local nodes="[]"
  local edges="[]"
  local total_messages=0
  local active_agents=0

  if [[ "$DR_FLEET_BUS_BACKEND" == "redis" ]] \
      && command -v redis-cli >/dev/null 2>&1 \
      && redis-cli -u "$DR_ORCH_REDIS_URL" ping 2>/dev/null | grep -q PONG; then

    # Count messages across all topics
    for topic in "fleet:task-events" "fleet:monitoring-alerts" \
                 "fleet:fleet-commands" "fleet:audit-log"; do
      local count
      count=$(redis-cli -u "$DR_ORCH_REDIS_URL" XLEN "stream:$topic" 2>/dev/null || echo 0)
      total_messages=$(( total_messages + count ))
    done

    # Build nodes from recent task-events (last 200 entries)
    nodes=$(redis-cli -u "$DR_ORCH_REDIS_URL" \
      XREVRANGE "stream:fleet:task-events" + - COUNT 200 2>/dev/null \
      | awk '
          /^from$/ { getline; froms[$0]=1 }
          /^to$/ { getline; tos[$0]=1 }
          END {
            n=0
            for (a in froms) agents[n++]=a
            for (a in tos) { if (!(a in froms)) agents[n++]=a }
            printf "["
            for (i=0; i<n; i++) {
              if (i>0) printf ","
              printf "{\"id\":\"%s\",\"role\":\"agent\",\"active\":true}", agents[i]
            }
            printf "]"
          }
        ' 2>/dev/null || echo "[]")

    # Count approximate active agents
    active_agents=$(printf '%s' "$nodes" | grep -o '"id"' | wc -l | tr -d ' ')
  fi

  # Write atomic JSON snapshot
  local tmp_file="${snapshot_file}.tmp.$$"
  cat > "$tmp_file" <<JSON
{
  "generated_at": "$ts",
  "nodes": $nodes,
  "edges": $edges,
  "metrics": {
    "total_messages": $total_messages,
    "active_agents": $active_agents,
    "snapshot_source": "$DR_FLEET_BUS_BACKEND"
  }
}
JSON
  mv -f "$tmp_file" "$snapshot_file"
  printf 'INFO: snapshot written to %s\n' "$snapshot_file"
}

# ── check ─────────────────────────────────────────────────────────────────────

_check() {
  printf 'metrics_dir=%s\nbackend=%s\nredis_url=%s\n' \
    "$DR_FLEET_METRICS_DIR" "$DR_FLEET_BUS_BACKEND" "$DR_ORCH_REDIS_URL"
}

# ── main ──────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=scripts/bus_adapter.sh
  source "$BUS_ADAPTER"

  case "$MODE" in
    check)    _check; exit 0 ;;
    snapshot) _write_snapshot; exit 0 ;;
    once)
      _write_snapshot
      # Drain one pending batch; discard output — snapshot is rebuilt after
      bus_subscribe "fleet:task-events" "obs" "obs-consumer-1" 5000 >/dev/null 2>&1 || true
      _write_snapshot
      exit 0
      ;;
    loop)
      printf 'INFO: obs aggregator starting (metrics_dir=%s)\n' "$DR_FLEET_METRICS_DIR"
      while true; do
        bus_subscribe "fleet:task-events" "obs" "obs-consumer-1" 10000 >/dev/null 2>&1 || true
        _write_snapshot
      done
      ;;
  esac
fi
