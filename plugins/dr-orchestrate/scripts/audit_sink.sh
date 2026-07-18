#!/usr/bin/env bash
# audit_sink.sh — JSONL audit backend.
# V-AC: 10 (emit), 11 (required fields), 12 (hash-only credentials), 18 (schema v2).
set -euo pipefail

AUDIT_SINK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
# shellcheck source=lib/portable-stat.sh
source "$AUDIT_SINK_LIB_DIR/portable-stat.sh"

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
_safe_append_open() {
  local path="$1" migrate_legacy="${2:-0}" path_identity fd_identity mode parent parent_mode
  parent="$(dirname -- "$path")"
  [[ -d "$parent" && ! -L "$parent" && "$(portable_uid "$parent")" == "$(id -u)" ]] \
    || { echo "ERR: unsafe append parent" >&2; return 1; }
  parent_mode="$(portable_mode "$parent")" || return 1
  (( (8#$parent_mode & 8#022) == 0 )) \
    || { echo "ERR: writable append parent" >&2; return 1; }
  [[ ! -L "$path" ]] || { echo "ERR: append path is a symlink" >&2; return 1; }
  if [[ ! -e "$path" ]]; then
    ( set -o noclobber; umask 077; : >"$path" ) 2>/dev/null || true
  fi
  [[ -f "$path" && ! -L "$path" && "$(portable_uid "$path")" == "$(id -u)" ]] \
    || { echo "ERR: unsafe append path" >&2; return 1; }
  mode="$(portable_mode "$path")" || return 1
  if [[ "$migrate_legacy" == 1 && "$mode" == 644 ]]; then
    chmod 0600 "$path" || return 1
    mode="$(portable_mode "$path")" || return 1
  fi
  [[ "$mode" == 600 ]] || { echo "ERR: unsafe append mode" >&2; return 1; }
  exec {SAFE_APPEND_FD}>>"$path" || return 1
  path_identity="$(portable_identity "$path")" || { exec {SAFE_APPEND_FD}>&-; return 1; }
  fd_identity="$(portable_identity "/dev/fd/$SAFE_APPEND_FD")" \
    || { exec {SAFE_APPEND_FD}>&-; return 1; }
  [[ ! -L "$path" && -f "/dev/fd/$SAFE_APPEND_FD" && "$path_identity" == "$fd_identity" ]] \
    || { echo "ERR: append path changed during open" >&2; exec {SAFE_APPEND_FD}>&-; return 1; }
}

_safe_read_file() {
  local path="$1" fd path_identity fd_identity mode parent parent_mode
  parent="$(dirname -- "$path")"
  [[ -d "$parent" && ! -L "$parent" && "$(portable_uid "$parent")" == "$(id -u)" ]] \
    || { echo "ERR: unsafe read parent" >&2; return 1; }
  parent_mode="$(portable_mode "$parent")" || return 1
  (( (8#$parent_mode & 8#022) == 0 )) \
    || { echo "ERR: writable read parent" >&2; return 1; }
  [[ -f "$path" && ! -L "$path" && "$(portable_uid "$path")" == "$(id -u)" ]] \
    || { echo "ERR: unsafe read path" >&2; return 1; }
  mode="$(portable_mode "$path")" || return 1
  if [[ "$mode" == 644 ]]; then
    chmod 0600 "$path" || return 1
    mode="$(portable_mode "$path")" || return 1
  fi
  [[ "$mode" == 600 ]] || { echo "ERR: unsafe read mode" >&2; return 1; }
  exec {fd}<"$path" || return 1
  path_identity="$(portable_identity "$path")" || { exec {fd}>&-; return 1; }
  fd_identity="$(portable_identity "/dev/fd/$fd")" || { exec {fd}>&-; return 1; }
  [[ ! -L "$path" && -f "/dev/fd/$fd" && "$path_identity" == "$fd_identity" ]] \
    || { echo "ERR: read path changed during open" >&2; exec {fd}>&-; return 1; }
  cat <&"$fd"
  exec {fd}>&-
}

emit() {
  local file="$1"; local payload="$2"
  umask 077
  mkdir -p "$(dirname "$file")"
  [[ ! -L "$file" ]] || { echo "ERR: audit path is a symlink" >&2; return 1; }
  local lock="${file}.lock"
  _safe_append_open "$lock" || return 1
  local audit_lock_fd="$SAFE_APPEND_FD"
  flock -w 5 "$audit_lock_fd" || { exec {audit_lock_fd}>&-; return 1; }
  _safe_append_open "$file" 1 || { flock -u "$audit_lock_fd"; exec {audit_lock_fd}>&-; return 1; }
  local audit_data_fd="$SAFE_APPEND_FD"
  printf '%s\n' "$payload" >&"$audit_data_fd"
  exec {audit_data_fd}>&-
  flock -u "$audit_lock_fd"
  exec {audit_lock_fd}>&-
}

# make_cycle_checkpoint <phase> <cycle_id> <session> <pane> <action> <proposal_status> [outcome]
# Raw pane text, callback capability and action payloads never enter this ledger.
make_cycle_checkpoint() {
  local phase="$1" cycle_id="$2" session="$3" pane="$4" action="$5"
  local proposal_status="$6" outcome="${7:-}"
  jq -n -c --arg ts "$(now_iso)" --arg phase "$phase" --arg cycle "$cycle_id" \
    --arg session "$session" --arg pane "$pane" --arg action_hash "$(hash_sha256 "$action")" \
    --arg proposal "$proposal_status" --arg outcome "$outcome" \
    '{schema_version:3,event:"cycle_checkpoint",timestamp:$ts,phase:$phase,
      cycle_id:$cycle,session:$session,pane_id:$pane,selected_action_hash:$action_hash,
      proposal_status:$proposal,outcome:$outcome}'
}

# Mark only the latest trailing prepare for a session/pane as interrupted.
# Recovery is ledger-only and deliberately has no executor hook.
recover_cycle_checkpoint() {
  local file="$1" session="$2" pane="$3"
  [[ -s "$file" ]] || return 0
  local cycle recovered content recovery_lock="${file}.recovery.lock"
  _safe_append_open "$recovery_lock" || return 2
  local recovery_fd="$SAFE_APPEND_FD"
  flock -w 5 "$recovery_fd" || { exec {recovery_fd}>&-; return 2; }
  content="$(_safe_read_file "$file")" \
    || { flock -u "$recovery_fd"; exec {recovery_fd}>&-; return 2; }
  cycle="$(jq -rs --arg session "$session" --arg pane "$pane" '
    [ .[] | select(.event=="cycle_checkpoint" and .session==$session and .pane_id==$pane) ]
    | if length==0 then "" else .[-1] as $last
      | if $last.phase=="prepare" then $last.cycle_id else "" end end' <<<"$content" 2>/dev/null)" \
    || { flock -u "$recovery_fd"; exec {recovery_fd}>&-; return 2; }
  cycle="${cycle#\"}"; cycle="${cycle%\"}"
  if [[ -z "$cycle" ]]; then flock -u "$recovery_fd"; exec {recovery_fd}>&-; return 0; fi
  recovered="$(jq -rs --arg cycle "$cycle" \
    '[.[] | select(.event=="cycle_checkpoint" and .cycle_id==$cycle and .phase=="recovery")] | length' \
    <<<"$content")"
  if [[ "$recovered" != "0" ]]; then flock -u "$recovery_fd"; exec {recovery_fd}>&-; return 0; fi
  emit "$file" "$(make_cycle_checkpoint recovery "$cycle" "$session" "$pane" "" interrupted recovered_interrupted)"
  flock -u "$recovery_fd"
  exec {recovery_fd}>&-
}

# Recover across day-rotated ledgers so a UTC-midnight crash is not lost.
recover_latest_cycle_checkpoint() {
  local audit_dir="$1" output_file="$2" session="$3" pane="$4"
  local combined file cycle recovered event recovery_lock="$audit_dir/.checkpoint-recovery.lock"
  umask 077
  mkdir -p "$audit_dir"
  _safe_append_open "$recovery_lock" || return 2
  local recovery_fd="$SAFE_APPEND_FD"
  flock -w 5 "$recovery_fd" || { exec {recovery_fd}>&-; return 2; }
  combined="$(mktemp "$audit_dir/.checkpoint-recovery.XXXXXX")" \
    || { flock -u "$recovery_fd"; exec {recovery_fd}>&-; return 2; }
  while IFS= read -r file; do _safe_read_file "$file" >>"$combined" || {
      rm -f "$combined"
      flock -u "$recovery_fd"
      exec {recovery_fd}>&-
      return 2
    }; done \
    < <(find "$audit_dir" -maxdepth 1 -type f -name 'audit-*.jsonl' -print | LC_ALL=C sort)
  cycle="$(jq -rs --arg session "$session" --arg pane "$pane" '
    [ .[] | select(.event=="cycle_checkpoint" and .session==$session and .pane_id==$pane) ]
    | if length==0 then "" else .[-1] as $last
      | if $last.phase=="prepare" then $last.cycle_id else "" end end' "$combined" 2>/dev/null)" \
    || { rm -f "$combined"; flock -u "$recovery_fd"; exec {recovery_fd}>&-; return 2; }
  cycle="${cycle#\"}"; cycle="${cycle%\"}"
  if [[ -n "$cycle" ]]; then
    recovered="$(jq -rs --arg cycle "$cycle" \
      '[.[] | select(.event=="cycle_checkpoint" and .cycle_id==$cycle and .phase=="recovery")] | length' \
      "$combined")"
    if [[ "$recovered" == 0 ]]; then
      event="$(make_cycle_checkpoint recovery "$cycle" "$session" "$pane" "" interrupted recovered_interrupted)"
      emit "$output_file" "$event"
    fi
  fi
  rm -f "$combined"
  flock -u "$recovery_fd"
  exec {recovery_fd}>&-
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
# `expected_outcome` is an additive optional field read from
# DR_ORCH_EXPECTED_OUTCOME env var (null when unset). Old consumers that do
# not set this env var get null, which the measure script treats as "no label"
# and excludes from the refined metric — backward-compatible.
make_event_v2() {
  local matched_text="$1"; local command="$2"; local exit_code="$3"
  local duration_ms="$4"; local pane_id="$5"
  local confidence="${6:-0}"; local subagent_model="${7:-}"
  local backend_used="${8:-}"; local escalation_backend="${9:-}"
  local stage="${10:-}"; local outcome="${11:-}"
  local reason; reason="$(redact_reason "${12:-}")"
  local expected_outcome="${DR_ORCH_EXPECTED_OUTCOME:-}"
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
    --arg eo   "$expected_outcome" \
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
      reason: $rsn,
      expected_outcome: (if $eo == "" then null else $eo end)}'
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
