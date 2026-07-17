#!/usr/bin/env bash
# adapters/audit-log-adapter.sh — emit eval-dataset records from audit-log traces.
#
# Third source-adapter for the fleet skill-evolution loop (after archive and
# dr-dream), reading the fleet audit-log into the eval dataset via the
# source-adapter-contract.md JSONL contract. Unlike archive/dr-dream, audit
# traces may carry SENSITIVE material (paths, hostnames, command fragments,
# secrets) — so every emitted field is passed through a redaction layer BEFORE
# it can reach the external LLM. This closes the contract's § Security clause
# ("Sources that may carry sensitive traces ... require a redaction layer").
#
# Input (argv[1]): a directory of audit JSONL files (one JSON object per line,
# the make_event_v2 shape written by the orchestrator audit sink and mirrored to
# disk by fleet_audit_consumer.sh). Fields read: command, stage, outcome,
# reason, exit_code, expected_outcome. Missing fields default to empty.
#
# Redis live path (opt-in, env-gated): with DR_FLEET_AUDIT_REDIS=1 the adapter
# additionally replays the fleet:audit-log stream via the orchestrator
# bus_adapter.sh. When redis-cli / the redis backend is unavailable it SKIPS
# cleanly (emits nothing, exit 0) — an absent Redis is never an error, matching
# the "empty source is not an error" contract and the jq-skip idiom.
#
# Exit codes (contract): 0 success (stdout may be empty); 1 missing directory;
# 2 usage error; 3 jq absent.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jsonl.sh
source "$SCRIPT_DIR/../lib/jsonl.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <audit-jsonl-dir>

Emit redacted JSONL eval-dataset records from audit-log traces to stdout.
Env: DR_FLEET_AUDIT_REDIS=1 also replays fleet:audit-log (skips if redis absent).
Exit 0 on success (empty stdout if no traces); 1 missing dir; 2 usage; 3 no jq.
EOF
}

# _redact <string> — strip sensitive material before it reaches the external LLM.
# Layered on the orchestrator's redact_reason() vocabulary (key=value secrets)
# and EXTENDED to also elide absolute paths, hostnames/IPs, and user@host
# fragments, which the § Security clause requires and no prior helper covered.
# Typed placeholders (<REDACTED>/<PATH>/<HOST>) preserve trace shape for eval
# signal without leaking the value.
_redact() {
    local s="${1:-}"
    s="${s:0:1000}"
    printf '%s' "$s" \
        | sed -E 's/[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
        | sed -E 's/[Tt][Oo][Kk][Ee][Nn][[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
        | sed -E 's/([Ss][Ee][Cc][Rr][Ee][Tt]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
        | sed -E 's/[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+[A-Za-z0-9._-]+/<REDACTED>/g' \
        | sed -E 's#/(home|Users|root|opt|var|etc|srv|mnt|tmp)/[^[:space:]"'"'"']*#<PATH>#g' \
        | sed -E 's/[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+/<USER@HOST>/g' \
        | sed -E 's/\b[0-9]{1,3}(\.[0-9]{1,3}){3}\b/<HOST>/g' \
        | sed -E 's/\b([a-zA-Z0-9-]+\.)+(com|net|org|io|ai|internal|local|lan|dev|arcanada)\b/<HOST>/g'
}

# Derive contract outcome from an audit trace: an explicit "success" outcome, or
# an exit_code of 0 with no failure signal, maps to success; everything else
# (denied, blocked, non-zero exit, escalation) is a failure signal.
_audit_outcome() {
    local outcome="$1" exit_code="$2"
    case "$outcome" in
        success|ok|allow|allowed) echo "success"; return ;;
        fail|failure|deny|denied|blocked|error|escalate|escalated) echo "failure"; return ;;
    esac
    if [ "${exit_code:-1}" = "0" ]; then echo "success"; else echo "failure"; fi
}

# Emit one eval record per audit JSON line read on stdin.
_emit_from_stream() {
    local line command stage outcome reason exit_code expected ti ao eo oc
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        # Skip non-object / unparseable lines defensively.
        printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1 || continue
        command=$(printf '%s' "$line" | jq -r '.command // ""')
        stage=$(printf '%s' "$line" | jq -r '.stage // ""')
        outcome=$(printf '%s' "$line" | jq -r '.outcome // ""')
        reason=$(printf '%s' "$line" | jq -r '.reason // ""')
        exit_code=$(printf '%s' "$line" | jq -r '.exit_code // ""')
        expected=$(printf '%s' "$line" | jq -r '.expected_outcome // ""')

        oc=$(_audit_outcome "$outcome" "$exit_code")
        ti=$(_redact "$(printf '%s %s' "$stage" "$command" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')")
        ao=$(_redact "outcome=$outcome; $reason")
        eo=$(_redact "$expected")

        jsonl_emit_record "$ti" "$eo" "$ao" "$oc" "audit-log"
    done
}

# Optional live replay of the fleet:audit-log Redis stream. Skips (returns 0,
# emits nothing) when redis-cli or the redis backend is unavailable.
_replay_redis() {
    local orch_lib
    orch_lib="$SCRIPT_DIR/../../dr-orchestrate/scripts/bus_adapter.sh"
    [ -f "$orch_lib" ] || return 0
    command -v redis-cli >/dev/null 2>&1 || return 0
    [ "${DR_FLEET_BUS_BACKEND:-redis}" = "redis" ] || return 0
    # shellcheck source=/dev/null
    source "$orch_lib" 2>/dev/null || return 0
    # bus_replay prints stream entries as JSON lines; feed them through the same
    # redacting emitter. Any failure (no stream, auth) degrades to a clean skip.
    bus_replay "${FLEET_TOPIC_AUDIT_LOG:-fleet:audit-log}" 0 2>/dev/null | _emit_from_stream || true
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        "") usage >&2; exit 2 ;;
    esac
    local dir=$1
    [ -d "$dir" ] || { echo "audit-log-adapter: not a directory: $dir" >&2; exit 1; }
    jsonl_require_jq || exit 3

    # Filesystem path: every *.jsonl file in the dir, stable order.
    local file
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        _emit_from_stream < "$file"
    done < <(find "$dir" -maxdepth 1 -type f -name '*.jsonl' | sort)

    # Opt-in live Redis replay (env-gated; clean skip when redis absent).
    if [ "${DR_FLEET_AUDIT_REDIS:-0}" = "1" ]; then
        _replay_redis
    fi
}

main "$@"
