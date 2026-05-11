#!/usr/bin/env bash
# audit_sink.sh — JSONL audit backend.
# V-AC: 10 (emit), 11 (required fields), 12 (hash-only credentials), 18 (schema v2).
set -euo pipefail

now_iso() { date -u +%FT%TZ; }

hash_sha256() { printf '%s' "${1:-}" | shasum -a 256 | awk '{print $1}'; }

# redact_reason <string> — truncate to 500 chars and elide tokens that look
# like secret material (password=, token=, secret=, credential=, api_key=).
# Conservative: catches the canonical `key[=:]value` shapes; not a substitute
# for boundary-side filtering. TUNE-0165 M5.
redact_reason() {
  local s="${1:-}"
  s="${s:0:500}"
  printf '%s' "$s" \
    | sed -E 's/[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
    | sed -E 's/[Tt][Oo][Kk][Ee][Nn][[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
    | sed -E 's/([Ss][Ee][Cc][Rr][Ee][Tt]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g'
}

# emit <file> <json-payload> — append payload as one JSONL line. Creates parent
# directory if needed. The day-rotated file path is the caller's responsibility;
# emit only writes verbatim.
emit() {
  local file="$1"; local payload="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$payload" >> "$file"
}

# make_event <matched_text> <command> <exit_code> <duration_ms> <pane_id>
# Phase-1 schema-v1 event with 6 required fields. matched_text is hashed
# (V-AC-12); raw text never enters the audit stream. Retained for backward
# compatibility — new call sites should use make_event_v2.
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

# make_event_v2 <matched_text> <command> <exit_code> <duration_ms> <pane_id>
#               <confidence> <subagent_model> <backend_used>
#               <escalation_backend> <stage> <outcome> [reason]
# Phase-2 schema-v2 event. Adds confidence + resolver/escalation metadata +
# stage/outcome tags. `reason` field is grep-redacted via redact_reason.
# Empty positional values yield empty JSON strings (preserved shape).
make_event_v2() {
  local matched_text="$1"; local command="$2"; local exit_code="$3"
  local duration_ms="$4"; local pane_id="$5"
  local confidence="${6:-0}"; local subagent_model="${7:-}"
  local backend_used="${8:-}"; local escalation_backend="${9:-}"
  local stage="${10:-}"; local outcome="${11:-}"
  local reason; reason="$(redact_reason "${12:-}")"
  local h; h="$(hash_sha256 "$matched_text")"
  jq -n -c \
    --arg ts   "$(now_iso)" \
    --arg h    "$h" \
    --arg c    "$command" \
    --argjson ec   "$exit_code" \
    --argjson dur  "$duration_ms" \
    --arg p    "$pane_id" \
    --argjson cf "$confidence" \
    --arg sm   "$subagent_model" \
    --arg bu   "$backend_used" \
    --arg eb   "$escalation_backend" \
    --arg stg  "$stage" \
    --arg oc   "$outcome" \
    --arg rsn  "$reason" \
    '{schema_version: 2,
      timestamp: $ts,
      matched_text_hash: $h,
      command: $c,
      exit_code: $ec,
      duration_ms: $dur,
      pane_id: $p,
      confidence: $cf,
      subagent_model: $sm,
      backend_used: $bu,
      escalation_backend: $eb,
      stage: $stg,
      outcome: $oc,
      reason: $rsn}'
}

# OpsBot sink remains a Phase-3+ stub. Phase 2 does not wire it.
opsbot_emit() {
  echo "ERR: OpsBot audit sink deferred (Phase 3+)" >&2
  return 99
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: audit_sink.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
