#!/usr/bin/env bash
# escalation_backend.sh — escalation sink for low-confidence resolver outputs.
# TUNE-0165 M3. Two backends: mock (JSONL writer) and dev-bot (stub).
# Schema frozen via tasks/TUNE-0165-fixtures.md § Escalation-JSONL Schema; any
# change requires a schema_version bump.
set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_ESCALATION_BACKEND:=mock}"
: "${DR_ORCH_ESCALATION_MOCK_LOG:=$HOME/.local/share/dr-orchestrate/escalation.jsonl}"

_redact() {
  local s="${1:-}"
  s="${s:0:500}"
  printf '%s' "$s" \
    | sed -E 's/[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
    | sed -E 's/[Tt][Oo][Kk][Ee][Nn][[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g' \
    | sed -E 's/([Ss][Ee][Cc][Rr][Ee][Tt]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[[:space:]]*[=:][[:space:]]*[^[:space:]]+/<REDACTED>/g'
}

_cycle_id() {
  # rfc9562-compatible UUID v7 (best-effort): timestamp_ms || version=7 || random.
  perl -e '
    use Time::HiRes qw(gettimeofday);
    my ($s, $us) = gettimeofday();
    my $ms = $s * 1000 + int($us / 1000);
    my $ts_hex = sprintf("%012x", $ms);
    my @r = map { int(rand(256)) } 1..10;
    my $ver_rand = (0x7 << 12) | (($r[0] << 4) | ($r[1] >> 4));
    my $var_rand = (0x8 << 12) | (($r[2] & 0x3F) << 8) | $r[3];
    printf "%s-%s-%04x-%04x-%02x%02x%02x%02x%02x%02x\n",
      substr($ts_hex, 0, 8),
      substr($ts_hex, 8, 4),
      $ver_rand,
      $var_rand,
      $r[4], $r[5], $r[6], $r[7], $r[8], $r[9];
  '
}

_hash_prompt() {
  printf '%s' "${DR_ORCH_PROMPT_TEXT:-}" | shasum -a 256 | awk '{print $1}'
}

_emit_mock() {
  local rj="$1"; local pane_id="$2"
  mkdir -p "$(dirname "$DR_ORCH_ESCALATION_MOCK_LOG")"
  local cid ts ph
  cid="$(_cycle_id)"
  ts="$(date -u +%FT%TZ)"
  ph="$(_hash_prompt)"
  local action conf reason backend_used model redacted
  action="$(printf '%s' "$rj" | jq -r '.action // ""')"
  conf="$(printf '%s' "$rj" | jq '.confidence // 0')"
  reason="$(printf '%s' "$rj" | jq -r '.reason // ""')"
  backend_used="$(printf '%s' "$rj" | jq -r '.backend_used // ""')"
  model="$(printf '%s' "$rj" | jq -r '.subagent_model // ""')"
  redacted="$(_redact "$reason")"
  jq -n -c \
    --arg ts "$ts" \
    --arg cid "$cid" \
    --arg p "$pane_id" \
    --arg ph "$ph" \
    --arg act "$action" \
    --argjson conf "$conf" \
    --arg r "$redacted" \
    --arg bu "$backend_used" \
    --arg m "$model" \
    '{schema_version:2, ts:$ts, cycle_id:$cid, pane_id:$p, prompt_hash:$ph,
      action_suggested:$act, confidence:$conf, reason:$r,
      subagent_model:$m, backend_used:$bu,
      escalation_backend:"mock", mock:true}' \
    >> "$DR_ORCH_ESCALATION_MOCK_LOG"
}

_emit_devbot() {
  local resolver_json="${1:-}"; local session_id="${2:-unknown}"
  # Gated no-op: if destination URL is unset, return silently (V-AC-7).
  # Defensive invariant: silent exit MUST NOT print a success message.
  if [[ -z "${DR_ORCH_ESCALATION_DEVBOT_URL:-}" ]]; then
    return 0
  fi
  # Resolve HMAC secret: env var direct (DR_ORCH_ESCALATION_HMAC_SECRET) or
  # via secrets_backend (DR_ORCH_ESCALATION_HMAC_SECRET_REF → yaml_get).
  local secret="${DR_ORCH_ESCALATION_HMAC_SECRET:-}"
  if [[ -z "$secret" ]] && [[ -n "${DR_ORCH_ESCALATION_HMAC_SECRET_REF:-}" ]]; then
    # shellcheck source=secrets_backend.sh
    source "$DR_ORCH_DIR/scripts/secrets_backend.sh" 2>/dev/null || true
    secret="$(yaml_get "${DR_ORCH_ESCALATION_HMAC_SECRET_REF}" "hmac_secret" 2>/dev/null || true)"
  fi
  # Build schema_version:2 event payload.
  local cid ts text
  cid="$(_cycle_id)"
  ts="$(date -u +%FT%TZ)"
  text="$(_redact "${DR_ORCH_PROMPT_TEXT:-}")"
  local payload
  payload="$(jq -n -c \
    --argjson sv 2 \
    --arg et "escalation" \
    --arg cid "$cid" \
    --arg sid "$session_id" \
    --arg txt "$text" \
    --arg ts_ "$ts" \
    '{schema_version:$sv, event_type:$et, cycle_id:$cid, session_id:$sid, text:$txt, ts:$ts_}')"
  # Dispatch to outbound backend.
  local backend="${DR_ORCH_OUTBOUND_BACKEND:-callback}"
  case "$backend" in
    callback)
      if [[ -z "$secret" ]]; then
        printf 'ERR: DR_ORCH_ESCALATION_HMAC_SECRET required for callback backend\n' >&2
        return 1
      fi
      bash "$DR_ORCH_DIR/scripts/outbound-hmac-sign.sh" sign_and_post \
        "$DR_ORCH_ESCALATION_DEVBOT_URL" "$secret" "$payload"
      ;;
    redis)
      bash "$DR_ORCH_DIR/scripts/outbound-redis-publish.sh" publish_event \
        "$session_id" "$payload"
      ;;
    *)
      printf 'ERR: unknown DR_ORCH_OUTBOUND_BACKEND=%s\n' "$backend" >&2
      return 2
      ;;
  esac
}

emit() {
  local resolver_json="${1:-}"; local pane_id="${2:-unknown}"
  if [[ -z "$resolver_json" ]]; then
    echo "ERR: emit requires <resolver_json> <pane_id>" >&2
    return 2
  fi
  case "$DR_ORCH_ESCALATION_BACKEND" in
    mock)    _emit_mock    "$resolver_json" "$pane_id" ;;
    dev-bot) _emit_devbot "$resolver_json" "$pane_id" ;;
    *)       echo "ERR: unknown escalation backend '$DR_ORCH_ESCALATION_BACKEND'" >&2; return 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: escalation_backend.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
