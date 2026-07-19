#!/usr/bin/env bash
# Runtime telemetry normalizer. Raw payloads are never persisted or echoed.
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/context-window-state.sh
source "$DR_ORCH_DIR/scripts/lib/context-window-state.sh"

die() { printf 'ERR: %s\n' "$*" >&2; return 2; }
arg_value() { local k="$1"; shift; while [ "$#" -gt 0 ]; do if [ "$1" = "$k" ]; then [ "$#" -ge 2 ] || return 1; printf '%s' "$2"; return 0; fi; shift; done; return 1; }

normalize_claude_pressure() {
  local json value type
  json="$(arg_value --json "$@")" || die '--json is required'
  type="$(printf '%s' "$json" | jq -r '.context_window.used_percentage | type' 2>/dev/null)" || die 'malformed JSON'
  [ "$type" != null ] || return 3
  [ "$type" = number ] || die 'used_percentage must be numeric'
  value="$(printf '%s' "$json" | jq -r '.context_window.used_percentage')"
  awk -v n="$value" 'BEGIN { if (n<0 || n>100) exit 2; c=int(n); if (n>c) c++; print c }' || die 'used_percentage out of range'
}

normalize_codex_pressure() {
  local total window scaled quotient remainder
  total="$(arg_value --total "$@")"; window="$(arg_value --window "$@")"
  [[ "$total" =~ ^[0-9]+$ && "$window" =~ ^[0-9]+$ ]] || die 'token values must be integers'
  [ "$window" -gt 0 ] && [ "$total" -le "$window" ] || die 'invalid token ratio'
  [ "$total" -le 9000000000000000 ] && [ "$window" -le 9000000000000000 ] || die 'token value too large'
  scaled=$((10#$total * 100)); quotient=$((scaled / (10#$window))); remainder=$((scaled % (10#$window)))
  [ "$remainder" -eq 0 ] || quotient=$((quotient + 1)); printf '%s\n' "$quotient"
}

publish_event() {
  local runtime kind instance incarnation pane conversation transaction used root cap seq_file seq payload_file event_file tag seq_lock tmp store_lock count candidate ci cs watermark
  runtime="$(arg_value --runtime "$@")"; kind="$(arg_value --kind "$@")"
  instance="$(arg_value --instance "$@")"; pane="$(arg_value --pane "$@")"; conversation="$(arg_value --conversation "$@")"
  incarnation="$(arg_value --incarnation "$@")"
  transaction="$(arg_value --transaction "$@" 2>/dev/null || true)"; used="$(arg_value --used-percent "$@" 2>/dev/null || true)"
  ctx_instance_safe "$instance" && ctx_incarnation_safe "$incarnation" && ctx_pane_safe "$pane" || die 'unsafe instance, incarnation, or pane'
  case "$runtime" in claude|codex) ;; *) die 'unsupported runtime' ;; esac
  case "$kind" in stop|turn_complete|session_start|post_compact|instance_retired) ;; *) die 'unsupported event kind' ;; esac
  root="$(ctx_state_root)"; cap="$root/instances/$instance.cap"; ctx_secure_regular "$cap" 600 || die 'capability missing'
  seq_file="$root/instances/$instance.seq"; seq_lock="$root/instances/$instance.seq.lock"
  ctx_lock_acquire "$seq_lock" || die 'sequence lock unavailable'
  seq=0; [ ! -f "$seq_file" ] || seq="$(cat "$seq_file")"
  if ! [[ "$seq" =~ ^[0-9]+$ ]]; then ctx_lock_release "$seq_lock"; die 'invalid sequence'; fi
  seq=$((seq + 1)); tmp="$(mktemp)"; printf '%s\n' "$seq" >"$tmp"
  if ! ctx_atomic_publish "$tmp" "$seq_file" 600; then rm -f "$tmp"; ctx_lock_release "$seq_lock"; die 'sequence publish failed'; fi
  rm -f "$tmp"; ctx_lock_release "$seq_lock"
  payload_file="$(mktemp)"; event_file="$root/events/$instance-$seq.json"
  jq -n -c --arg runtime "$runtime" --arg kind "$kind" --arg instance "$instance" --arg incarnation "$incarnation" --arg pane "$pane" --arg conversation "$conversation" --arg transaction "$transaction" --arg used "$used" --argjson seq "$seq" \
    '{runtime:$runtime,kind:$kind,instance:$instance,incarnation:$incarnation,pane:$pane,conversation:$conversation,transaction:$transaction,used_percent:$used,sequence:$seq}' >"$payload_file"
  tag="$(ctx_hmac "$cap" "$payload_file")"; tmp="$(mktemp)"; jq -n -c --slurpfile p "$payload_file" --arg tag "$tag" '{payload:$p[0],tag:$tag}' >"$tmp"
  store_lock="$root/events/.store.lock"; ctx_lock_acquire "$store_lock" || { rm -f "$payload_file" "$tmp"; die 'event store lock unavailable'; }
  count="$(find "$root/events" -maxdepth 1 -name '*.json' -type f | wc -l)"
  while [ "$count" -ge 128 ]; do
    candidate=""
    for ci in "$root"/events/*.json; do
      [ -f "$ci" ] || continue; cs="$(jq -r '.payload.sequence' "$ci")"; instance="$(jq -r '.payload.instance' "$ci")"
      watermark="$root/instances/$instance.consumed"
      if ctx_secure_regular "$watermark" 600 && [ "$cs" -le "$(cat "$watermark")" ]; then candidate="$ci"; break; fi
    done
    [ -n "$candidate" ] || { ctx_lock_release "$store_lock"; rm -f "$payload_file" "$tmp"; die 'event cap exhausted by unconsumed envelopes'; }
    rm -f "$candidate"; count=$((count - 1))
  done
  ctx_atomic_publish "$tmp" "$event_file" 600 || { ctx_lock_release "$store_lock"; rm -f "$payload_file" "$tmp"; die 'event publish failed'; }
  ctx_lock_release "$store_lock"; rm -f "$payload_file" "$tmp"; printf '%s\n' "$event_file"
}

resolve_codex_rollout_pressure() {
  local conversation="$1" root rollout before after fd_path first values total window
  local -a matches=()
  [[ "$conversation" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || die 'invalid Codex thread ID'
  root="${CODEX_HOME:-$HOME/.codex}/sessions"; ctx_secure_parent "$root/session.jsonl" && [ -d "$root" ] && [ ! -L "$root" ] || die 'unsafe Codex sessions root'
  mapfile -t matches < <(rg -l -F --glob '*.jsonl' "$conversation" "$root" 2>/dev/null || true)
  [ "${#matches[@]}" -eq 1 ] || die 'Codex rollout match is missing or ambiguous'; rollout="${matches[0]}"
  ctx_secure_parent "$rollout" && ctx_secure_regular "$rollout" 600 || die 'unsafe Codex rollout'
  [ -s "$rollout" ] && [ -z "$(tail -c 1 "$rollout")" ] || die 'partial Codex rollout record'
  before="$(ctx_identity "$rollout")"; exec {rollout_fd}<"$rollout"; fd_path="/proc/self/fd/$rollout_fd"; [ -e "$fd_path" ] || fd_path="/dev/fd/$rollout_fd"
  [ "$(ctx_identity "$fd_path")" = "$before" ] || { exec {rollout_fd}<&-; die 'Codex rollout identity changed'; }
  IFS= read -r first <&"$rollout_fd" || { exec {rollout_fd}<&-; die 'empty Codex rollout'; }
  [ "$(jq -r '.type' <<<"$first")" = session_meta ] && [ "$(jq -r '.payload.id' <<<"$first")" = "$conversation" ] || { exec {rollout_fd}<&-; die 'Codex rollout session mismatch'; }
  values="$(jq -r 'select(.type=="event_msg" and .payload.type=="token_count") | [.payload.info.last_token_usage.total_tokens,.payload.info.model_context_window] | @tsv' <&"$rollout_fd" | tail -1)"
  after="$(ctx_identity "$rollout")"; exec {rollout_fd}<&-; [ "$after" = "$before" ] || die 'Codex rollout path replaced'
  IFS=$'\t' read -r total window <<<"$values"; [[ "$total" =~ ^[0-9]+$ && "$window" =~ ^[0-9]+$ ]] || die 'Codex rollout telemetry missing'
  normalize_codex_pressure --total "$total" --window "$window"
}

input_json() {
  local supplied="${1:-}" body
  if [ -n "$supplied" ]; then body="$supplied"; else body="$(head -c 65537)"; fi
  [ "${#body}" -le 65536 ] && jq -e 'type=="object"' <<<"$body" >/dev/null 2>&1 || die 'malformed or oversized runtime event'
  printf '%s' "$body"
}

require_launch_binding() {
  local runtime="$1" meta root map pid birth current socket epoch
  ctx_instance_safe "${DR_ORCH_CONTEXT_INSTANCE:-}" && ctx_incarnation_safe "${DR_ORCH_CONTEXT_INCARNATION:-}" && ctx_pane_safe "${DR_ORCH_CONTEXT_PANE:-}" || die 'runtime launch binding missing'
  [[ "${DR_ORCH_ACTIVE_TASK:-}" =~ ^[A-Z]+-[0-9]+$ ]] && [ -n "${DR_ORCH_WORKSPACE:-}" ] || die 'task launch binding missing'
  meta="$(ctx_state_root)/instances/$DR_ORCH_CONTEXT_INSTANCE.meta.json"
  ctx_secure_regular "$meta" 600 || die 'instance metadata missing'
  root="$(ctx_state_root)"; map="$root/active/$(printf '%s' "$DR_ORCH_CONTEXT_PANE" | tr -c 'A-Za-z0-9_.-' '_').map"
  ctx_secure_regular "$map" 600 && [ "$(cat "$map")" = "$DR_ORCH_CONTEXT_INSTANCE" ] && [ ! -e "$root/instances/$DR_ORCH_CONTEXT_INSTANCE.retired" ] || die 'runtime instance is not active'
  [ "$(jq -r '.runtime' "$meta")" = "$runtime" ] && [ "$(jq -r '.incarnation' "$meta")" = "$DR_ORCH_CONTEXT_INCARNATION" ] && [ "$(jq -r '.pane' "$meta")" = "$DR_ORCH_CONTEXT_PANE" ] && [ "$(jq -r '.task' "$meta")" = "$DR_ORCH_ACTIVE_TASK" ] && [ "$(jq -r '.workspace' "$meta")" = "$DR_ORCH_WORKSPACE" ] && [ "$(jq -r '.runtime_bound' "$meta")" = true ] || die 'runtime launch binding mismatch'
  pid="$(jq -r '.process_pid' "$meta")"; birth="$(jq -r '.process_birth' "$meta")"; current="$(ctx_process_birth "$pid" 2>/dev/null || true)"; [ -n "$current" ] && [ "$current" = "$birth" ] && ctx_process_live "$pid" || die 'bound runtime process is not alive'
  socket="$(jq -r '.socket' "$meta")"; epoch="$(jq -r '.epoch' "$meta")"
  if [ "$socket" != unbound ]; then [ -S "$socket" ] && tmux -S "$socket" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq "$DR_ORCH_CONTEXT_PANE" && [ "$(tmux -S "$socket" show-options -gv @datarim_context_epoch 2>/dev/null)" = "$epoch" ] || die 'tmux binding is not current'; fi
}

telemetry_file() { printf '%s/instances/%s.pressure.json' "$(ctx_state_root)" "$DR_ORCH_CONTEXT_INSTANCE"; }

store_pressure() {
  local conversation="$1" used="$2" file tmp
  file="$(telemetry_file)"; tmp="$(mktemp)"
  jq -n -c --arg conversation "$conversation" --arg incarnation "$DR_ORCH_CONTEXT_INCARNATION" --argjson used "$used" '{conversation:$conversation,incarnation:$incarnation,used_percent:$used}' >"$tmp"
  ctx_atomic_publish "$tmp" "$file" 600 || { rm -f "$tmp"; die 'pressure checkpoint failed'; }
  rm -f "$tmp"
}

active_transaction() {
  local wanted="$1" file state found=""
  for file in "$(ctx_state_root)"/transactions/*.json; do
    [ -f "$file" ] || continue
    [ "$(jq -r '.instance' "$file")" = "$DR_ORCH_CONTEXT_INSTANCE" ] || continue
    [ "$(jq -r '.incarnation' "$file")" = "$DR_ORCH_CONTEXT_INCARNATION" ] || continue
    state="$(jq -r '.state' "$file")"; [ "$state" = "$wanted" ] || continue
    [ -z "$found" ] || die 'ambiguous active transactions'
    found="$(jq -r '.id' "$file")"
  done
  [ -n "$found" ] || return 1; printf '%s' "$found"
}

dispatch_boundary() {
  local runtime="$1" conversation="$2" boundary="$3" pressure used mode tx event meta label
  pressure="$(telemetry_file)"; ctx_secure_regular "$pressure" 600 || return 0
  [ "$(jq -r '.conversation' "$pressure")" = "$conversation" ] || die 'pressure conversation mismatch'
  [ "$(jq -r '.incarnation' "$pressure")" = "$DR_ORCH_CONTEXT_INCARNATION" ] || die 'pressure incarnation mismatch'
  used="$(jq -r '.used_percent' "$pressure")"; meta="$(ctx_state_root)/instances/$DR_ORCH_CONTEXT_INSTANCE.meta.json"
  label="$(jq -r '.label // empty' "$meta")"
  mode="$(DR_CONTEXT_POLICY_LABEL="$label" bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" evaluate --used-percent "$used")"
  [ "$mode" != no_op ] || return 0
  if [ "$runtime" = codex ]; then
    local ready
    ready="$(ctx_state_root)/instances/$DR_ORCH_CONTEXT_INSTANCE.ready.json"
    ctx_secure_regular "$ready" 600 || die 'Codex lifecycle handshake missing'
    [ "$(jq -r '.conversation' "$ready")" = "$conversation" ] && [ "$(jq -r '.incarnation' "$ready")" = "$DR_ORCH_CONTEXT_INCARNATION" ] && [ "$(jq -r '.profile_digest' "$ready")" = "$(jq -r '.overlay_digest' "$meta")" ] && [ "$(ctx_codex_profile_digest "$(jq -r '.overlay' "$meta")")" = "$(jq -r '.overlay_digest' "$meta")" ] || die 'Codex lifecycle handshake is stale'
  fi
  if active_transaction prepared >/dev/null 2>&1 || active_transaction compact_dispatched >/dev/null 2>&1 || active_transaction clear_dispatched >/dev/null 2>&1; then
    die 'nonterminal reset transaction already exists'
  fi
  tx="$(bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" prepare --task "$DR_ORCH_ACTIVE_TASK" --workspace "$DR_ORCH_WORKSPACE" --runtime "$runtime" --instance "$DR_ORCH_CONTEXT_INSTANCE" --incarnation "$DR_ORCH_CONTEXT_INCARNATION" --pane "$DR_ORCH_CONTEXT_PANE" --conversation "$conversation" --mode "$mode")"
  event="$(publish_event --runtime "$runtime" --kind "$boundary" --instance "$DR_ORCH_CONTEXT_INSTANCE" --incarnation "$DR_ORCH_CONTEXT_INCARNATION" --pane "$DR_ORCH_CONTEXT_PANE" --conversation "$conversation" --transaction "$tx" --used-percent "$used")"
  bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" dispatch --transaction "$tx" --event "$event"
}

mark_codex_ready() {
  local conversation="$1" meta profile digest tmp dest
  meta="$(ctx_state_root)/instances/$DR_ORCH_CONTEXT_INSTANCE.meta.json"; profile="$(jq -r '.overlay' "$meta")"
  ctx_secure_regular "$profile" 600 || die 'Codex profile missing'
  digest="$(ctx_codex_profile_digest "$profile")"; [ "$digest" = "$(jq -r '.overlay_digest' "$meta")" ] || die 'Codex profile digest changed'
  tmp="$(mktemp)"; jq -n -c --arg conversation "$conversation" --arg incarnation "$DR_ORCH_CONTEXT_INCARNATION" --arg digest "$digest" '{conversation:$conversation,incarnation:$incarnation,profile_digest:$digest}' >"$tmp"
  dest="$(ctx_state_root)/instances/$DR_ORCH_CONTEXT_INSTANCE.ready.json"
  ctx_atomic_publish "$tmp" "$dest" 600 || { rm -f "$tmp"; die 'readiness publish failed'; }; rm -f "$tmp"
}

complete_or_resume() {
  local runtime="$1" kind="$2" conversation="$3" tx event
  case "$kind" in
    post_compact)
      tx="$(active_transaction compact_dispatched)" || return 0
      event="$(publish_event --runtime "$runtime" --kind post_compact --instance "$DR_ORCH_CONTEXT_INSTANCE" --incarnation "$DR_ORCH_CONTEXT_INCARNATION" --pane "$DR_ORCH_CONTEXT_PANE" --conversation "$conversation" --transaction "$tx")"
      bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" complete --transaction "$tx" --event "$event"
      ;;
    session_start)
      [ "$runtime" != codex ] || mark_codex_ready "$conversation"
      tx="$(active_transaction clear_dispatched)" || return 0
      event="$(publish_event --runtime "$runtime" --kind session_start --instance "$DR_ORCH_CONTEXT_INSTANCE" --incarnation "$DR_ORCH_CONTEXT_INCARNATION" --pane "$DR_ORCH_CONTEXT_PANE" --conversation "$conversation" --transaction "$tx")"
      bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" resume --transaction "$tx" --event "$event"
      ;;
  esac
}

ingest_claude() {
  local kind json conversation used source
  kind="$(arg_value --kind "$@")" || die '--kind is required'; json="$(input_json "$(arg_value --json "$@" 2>/dev/null || true)")"
  require_launch_binding claude; conversation="$(jq -r '.session_id // empty' <<<"$json")"; [ -n "$conversation" ] || die 'Claude session ID missing'
  case "$kind" in
    status) used="$(normalize_claude_pressure --json "$json")" || return $?; store_pressure "$conversation" "$used" ;;
    stop) dispatch_boundary claude "$conversation" stop ;;
    post_compact) complete_or_resume claude post_compact "$conversation" ;;
    session_start) source="$(jq -r '.source // empty' <<<"$json")"; [ "$source" = clear ] || return 0; complete_or_resume claude session_start "$conversation" ;;
    *) die 'unsupported Claude event' ;;
  esac
}

ingest_codex() {
  local kind json conversation total window used event_type
  kind="$(arg_value --kind "$@")" || die '--kind is required'; json="$(input_json "$(arg_value --json "$@" 2>/dev/null || true)")"
  require_launch_binding codex; conversation="$(jq -r '."thread-id" // .session_id // empty' <<<"$json")"; [ -n "$conversation" ] || die 'Codex thread ID missing'
  case "$kind" in
    notify)
      event_type="$(jq -r '.type // empty' <<<"$json")"; [ "$event_type" = agent-turn-complete ] || die 'unsupported Codex notify event'
      used="$(resolve_codex_rollout_pressure "$conversation")"; store_pressure "$conversation" "$used"; dispatch_boundary codex "$conversation" turn_complete
      ;;
    session_start|post_compact) complete_or_resume codex "$kind" "$conversation" ;;
    *) die 'unsupported Codex event' ;;
  esac
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in normalize-claude-pressure) normalize_claude_pressure "$@" ;; normalize-codex-pressure) normalize_codex_pressure "$@" ;; publish) publish_event "$@" ;; ingest-claude) ingest_claude "$@" ;; ingest-codex) ingest_codex "$@" ;; *) die 'unknown adapter verb' ;; esac
}
main "$@"
