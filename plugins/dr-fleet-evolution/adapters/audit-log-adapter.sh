#!/usr/bin/env bash
# adapters/audit-log-adapter.sh — emit eval-dataset records from the fleet
# audit-log Redis Stream (source-adapter-contract.md).
#
# argv[1] is the Redis URL (e.g. redis://127.0.0.1:6379); the stream key is the
# fixed audit-log topic `stream:fleet:audit-log`. Each stream entry is a fleet
# message envelope (id/ts/type/task_id/reason[/outcome]); one JSONL record is
# emitted per entry:
#
#   task_input      — "<task_id> (<type>)" (redacted)
#   expected_output — "" (the audit log records no intended result)
#   actual_output   — the entry's reason, run through the redaction layer
#   outcome         — success, unless the entry signals otherwise:
#                       type in {alert, agent-killed}          -> failure
#                       an explicit outcome field of "failure" -> failure
#   source          — "audit-log"
#
# SECURITY (S1): audit reasons carry action traces (paths, hostnames, command
# fragments, secrets). Every string derived from an entry is passed through
# redact_trace (lib/redact.sh) BEFORE it reaches stdout — the dataset is fed to
# an external LLM via coworker and MUST NOT leak sensitive material.
#
# Redis is optional: when the client binary is absent or the endpoint is
# unreachable, the adapter skips gracefully (exit 0, empty stdout) — an
# unavailable broker is not an error (env-gated skip). JSON is emitted via
# jsonl_emit_record (jq) for correct escaping.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jsonl.sh
source "$SCRIPT_DIR/../lib/jsonl.sh"
# shellcheck source=../lib/redact.sh
source "$SCRIPT_DIR/../lib/redact.sh"

# Redis client binary — overridable for testing (mirrors COWORKER_BIN/GIT_BIN).
REDIS_CLI_BIN="${REDIS_CLI_BIN:-redis-cli}"
# Fixed audit-log topic → stream key (matches bus_adapter.sh _stream_key).
AUDIT_STREAM_KEY="stream:fleet:audit-log"

usage() {
    cat <<EOF
Usage: $(basename "$0") <redis-url>

Emit JSONL eval-dataset records (one per audit-log entry) to stdout.
Exit 0 on success (empty stdout when Redis is unavailable — env-gated skip);
exit 2 on usage error.
EOF
}

log() { echo "audit-log-adapter: $*" >&2; }

# true when the client binary exists and the endpoint answers PING with PONG.
_redis_reachable() {
    local url=$1
    command -v "$REDIS_CLI_BIN" >/dev/null 2>&1 || return 1
    "$REDIS_CLI_BIN" -u "$url" ping 2>/dev/null | grep -q PONG
}

# Flatten the stream to one line per entry: "<id>\t<k>=<v>\t<k>=<v>...".
# A server-side Lua pass keeps parsing version-stable and avoids the brittle
# nested/indented text of a plain `XRANGE`. Field values have tabs/newlines
# collapsed to spaces so the TAB delimiter stays unambiguous.
_LUA_FLATTEN='local res = redis.call("XRANGE", KEYS[1], "-", "+")
local out = {}
for _, e in ipairs(res) do
  local parts = {e[1]}
  local f = e[2]
  for i = 1, #f, 2 do
    local v = f[i+1] or ""
    v = string.gsub(v, "[\t\n\r]", " ")
    parts[#parts+1] = f[i] .. "=" .. v
  end
  out[#out+1] = table.concat(parts, "\t")
end
return table.concat(out, "\n")'

# Derive a success|failure outcome from an entry's type and optional outcome.
_derive_outcome() {
    local type=$1 outcome=$2
    if [ "$outcome" = "success" ] || [ "$outcome" = "failure" ]; then
        echo "$outcome"; return
    fi
    case "$type" in
        alert|agent-killed) echo "failure" ;;
        *)                  echo "success" ;;
    esac
}

# Emit one record from a single flattened entry line (fields after the id).
_emit_entry() {
    local line=$1
    local -a fields
    IFS=$'\t' read -r -a fields <<< "$line"
    local tok key val task_id="" type="" reason="" outcome=""
    # fields[0] is the stream id — skip it; the rest are k=v tokens.
    local i
    for ((i = 1; i < ${#fields[@]}; i++)); do
        tok=${fields[i]}
        key=${tok%%=*}
        val=${tok#*=}
        case "$key" in
            task_id) task_id=$val ;;
            type)    type=$val ;;
            reason)  reason=$val ;;
            outcome) outcome=$val ;;
        esac
    done

    local derived task_input actual
    derived=$(_derive_outcome "$type" "$outcome")
    task_input=$(redact_trace "${task_id:-unknown} (${type:-audit})")
    actual=$(redact_trace "${reason:-type=${type:-audit}}")

    jsonl_emit_record \
        "$task_input" \
        "" \
        "$actual" \
        "$derived" \
        "audit-log"
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        "") usage >&2; exit 2 ;;
    esac
    local url=$1
    jsonl_require_jq || exit 3

    if ! _redis_reachable "$url"; then
        log "Redis unavailable at $url — skipping (not an error)"
        exit 0
    fi

    local flat
    if ! flat=$("$REDIS_CLI_BIN" -u "$url" EVAL "$_LUA_FLATTEN" 1 "$AUDIT_STREAM_KEY" 2>/dev/null); then
        log "audit-log stream read failed — skipping (not an error)"
        exit 0
    fi

    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        _emit_entry "$line"
    done <<< "$flat"
}

main "$@"
