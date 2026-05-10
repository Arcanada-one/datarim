#!/usr/bin/env bash
# audit_sink.sh — JSONL audit backend. OpsBot stub deferred to Phase 2.
# V-AC: 10 (emit), 11 (required fields), 12 (hash-only credentials).
set -euo pipefail

now_iso() { date -u +%FT%TZ; }

hash_sha256() { printf '%s' "${1:-}" | shasum -a 256 | awk '{print $1}'; }

# emit <file> <json-payload> — append payload as one JSONL line. Creates parent
# directory if needed. The day-rotated file path is the caller's responsibility;
# emit only writes verbatim.
emit() {
  local file="$1"; local payload="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$payload" >> "$file"
}

# make_event <matched_text> <command> <exit_code> <duration_ms> <pane_id>
# Emits canonical JSON object with the 6 V-AC-11 fields. matched_text is hashed
# (V-AC-12); raw text never enters the audit stream.
make_event() {
  local matched_text="$1"; local command="$2"; local exit_code="$3"
  local duration_ms="$4"; local pane_id="$5"
  local h; h="$(hash_sha256 "$matched_text")"
  jq -n -c \
    --arg ts  "$(now_iso)" \
    --arg h   "$h" \
    --arg c   "$command" \
    --argjson ec  "$exit_code" \
    --argjson dur "$duration_ms" \
    --arg p   "$pane_id" \
    '{timestamp:$ts, matched_text_hash:$h, command:$c, exit_code:$ec, duration_ms:$dur, pane_id:$p}'
}

# Phase 2 stubs.
opsbot_emit() {
  echo "ERR: OpsBot audit sink deferred to Phase 2 (TUNE-0165)" >&2
  return 99
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: audit_sink.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
