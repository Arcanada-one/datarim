#!/usr/bin/env bash
# redis_job_store.sh — TUNE-0295 Phase B
# Async job store for /hooks/tmux op=new. Backed by Redis (redis-cli),
# fail-soft when Redis unreachable.
#
# Key schema: dr-orch:tmux-job:<uuid>
# Value: JSON string (caller-defined shape: {"status":"pending|complete|error","data":{...}})
# TTL: DR_ORCH_JOB_TTL seconds (default 3600).
#
# V-AC: V-AC-3 (async machinery), V-AC-9 (security floor — no eval).

set -o pipefail

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_ORCH_JOB_TTL:=3600}"
: "${DR_ORCH_REDIS_KEY_PREFIX:=dr-orch:tmux-job:}"

_redis() {
  # Wrapper around redis-cli. Args appended after -u <url>.
  # Returns redis-cli exit code; stdout = response.
  if ! command -v redis-cli >/dev/null 2>&1; then
    echo "redis-cli not in PATH" >&2
    return 1
  fi
  redis-cli -u "$DR_ORCH_REDIS_URL" "$@"
}

job_store_key() {
  local uuid="$1"
  printf '%s%s' "$DR_ORCH_REDIS_KEY_PREFIX" "$uuid"
}

job_store_set() {
  local uuid="$1" val="$2"
  local key
  key="$(job_store_key "$uuid")"
  local out
  if ! out="$(_redis SET "$key" "$val" EX "$DR_ORCH_JOB_TTL" 2>&1)"; then
    return 1
  fi
  [[ "$out" == "OK" ]] || return 1
}

job_store_get() {
  local uuid="$1"
  local key
  key="$(job_store_key "$uuid")"
  local ttl
  ttl="$(_redis TTL "$key" 2>/dev/null)"
  case "$ttl" in
    -2|-2*) return 1 ;;  # not found
  esac
  local val
  val="$(_redis GET "$key" 2>/dev/null)" || return 1
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

job_store_ttl() {
  local uuid="$1"
  local key
  key="$(job_store_key "$uuid")"
  _redis TTL "$key" 2>/dev/null
}

job_store_del() {
  local uuid="$1"
  local key
  key="$(job_store_key "$uuid")"
  _redis DEL "$key" >/dev/null 2>&1 || return 1
}

job_store_ping() {
  _redis PING >/dev/null 2>&1
}

# CLI mode: redis_job_store.sh <fn> <args...>
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  case "$fn" in
    set|get|ttl|del|ping) "job_store_$fn" "$@" ;;
    *) echo "usage: $0 <set|get|ttl|del|ping> [args]" >&2; exit 2 ;;
  esac
fi
