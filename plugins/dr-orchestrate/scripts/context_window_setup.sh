#!/usr/bin/env bash
# Private runtime-overlay setup/doctor/remove helper.
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/context-window-state.sh
source "$DR_ORCH_DIR/scripts/lib/context-window-state.sh"

die() { printf 'ERR: %s\n' "$*" >&2; return 2; }
config_value() {
  local key="$1" file="${DR_ORCH_USER_CONFIG:-$DR_ORCH_DIR/user-config.yaml}" before after fd_path value
  ctx_secure_parent "$file" && ctx_secure_regular "$file" 600 || return 1
  before="$(ctx_identity "$file")"; exec {config_fd}<"$file"; fd_path="/proc/self/fd/$config_fd"; [ -e "$fd_path" ] || fd_path="/dev/fd/$config_fd"
  [ "$(ctx_identity "$fd_path")" = "$before" ] || { exec {config_fd}<&-; return 1; }
  case "$key" in
    key_injection) value="$(awk '/^key_injection:[[:space:]]+(true|false)([[:space:]]|$)/ {print $2; exit}' "$fd_path")" ;;
    trust_same_uid_runtime) value="$(awk '/^context_window:[[:space:]]*$/ {inside=1; next} inside && /^[^[:space:]]/ {exit} inside && $1=="trust_same_uid_runtime:" {print $2; exit}' "$fd_path")" ;;
    enabled) value="$(awk '/^context_window:[[:space:]]*$/ {inside=1; next} inside && /^[^[:space:]]/ {exit} inside && $1=="enabled:" {print $2; exit}' "$fd_path")" ;;
    policy_label) value="$(awk '/^context_window:[[:space:]]*$/ {inside=1; next} inside && /^[^[:space:]]/ {exit} inside && $1=="policy_label:" {sub(/^[[:space:]]*policy_label:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$fd_path")" ;;
  esac
  after="$(ctx_identity "$file")"; exec {config_fd}<&-; [ "$after" = "$before" ] || return 1; printf '%s\n' "$value"
}

require_enabled() {
  [ "$(config_value key_injection)" = true ] && [ "$(config_value enabled)" = true ] && [ "$(config_value trust_same_uid_runtime)" = true ]
}

write_claude() {
  local root adapter adapter_q dest tmp digest_file digest_tmp
  root="$(ctx_state_root)"; adapter="$DR_ORCH_DIR/scripts/context_pressure_adapter.sh"; adapter_q="$(printf '%q' "$adapter")"; dest="$root/config/context-window-hooks.claude.json"; tmp="$(mktemp)"
  jq -n --arg adapter "$adapter_q" '{statusLine:{type:"command",command:("bash "+$adapter+" ingest-claude --kind status")},hooks:{Stop:[{hooks:[{type:"command",command:("bash "+$adapter+" ingest-claude --kind stop")}]}],SessionStart:[{matcher:"clear",hooks:[{type:"command",command:("bash "+$adapter+" ingest-claude --kind session_start")}]}],PostCompact:[{hooks:[{type:"command",command:("bash "+$adapter+" ingest-claude --kind post_compact")}]}]}}' >"$tmp"
  if [ -e "$dest" ] && ! cmp -s "$tmp" "$dest"; then rm -f "$tmp"; return 1; fi
  ctx_atomic_publish "$tmp" "$dest" 600 || { rm -f "$tmp"; return 1; }
  digest_file="$dest.sha256"; digest_tmp="$(mktemp)"; ctx_sha256 "$tmp" >"$digest_tmp"
  ctx_atomic_publish "$digest_tmp" "$digest_file" 600 || { rm -f "$tmp" "$digest_tmp"; return 1; }
  rm -f "$tmp" "$digest_tmp"; printf '%s\n' "$dest"
}

write_codex() {
  local dest tmp adapter quoted command digest_file digest_tmp prefix expected_prefix
  dest="${CODEX_HOME:-$HOME/.codex}/datarim-orchestrate-context.config.toml"; adapter="$DR_ORCH_DIR/scripts/context_pressure_adapter.sh"
  mkdir -p "$(dirname "$dest")"; chmod 700 "$(dirname "$dest")"; tmp="$(mktemp)"; quoted="$(printf '%s' "$adapter" | jq -Rs .)"; command="bash $(printf '%q' "$adapter")"
  printf 'developer_instructions = "DATARIM_CONTEXT_PROFILE_CANARY"\nnotify = ["bash", %s, "ingest-codex", "--kind", "notify"]\n\n[features]\nhooks = true\n\n[[hooks.SessionStart]]\nmatcher = "startup|resume|clear|compact"\n[[hooks.SessionStart.hooks]]\ntype = "command"\ncommand = %s\n\n[[hooks.PostCompact]]\n[[hooks.PostCompact.hooks]]\ntype = "command"\ncommand = %s\n\n# DATARIM_MANAGED_END\n' "$quoted" "$(printf '%s ingest-codex --kind session_start' "$command" | jq -Rs .)" "$(printf '%s ingest-codex --kind post_compact' "$command" | jq -Rs .)" >"$tmp"
  if [ -e "$dest" ]; then
    [ "$(grep -c '^# DATARIM_MANAGED_END$' "$dest")" -eq 1 ] || { rm -f "$tmp"; return 1; }
    prefix="$(mktemp)"; awk '/^# DATARIM_MANAGED_END$/ || /^\[projects\./ || /^\[tui\./ || /^\[hooks\.state\./ {exit} {print}' "$dest" >"$prefix" || { rm -f "$tmp" "$prefix"; return 1; }
    expected_prefix="$(mktemp)"; awk '/^# DATARIM_MANAGED_END$/ {exit} {print}' "$tmp" >"$expected_prefix"; cmp -s "$expected_prefix" "$prefix" || { rm -f "$tmp" "$prefix" "$expected_prefix"; return 1; }
    awk 'BEGIN{after=0} /^# DATARIM_MANAGED_END$/ || /^\[projects\./ || /^\[tui\./ || /^\[hooks\.state\./ {after=1} after && /^\[/ {if ($0 !~ /^\[projects\./ && $0 !~ /^\[tui\./ && $0 !~ /^\[hooks\.state\./) exit 2}' "$dest" || { rm -f "$tmp" "$prefix" "$expected_prefix"; return 1; }
    rm -f "$prefix" "$expected_prefix"
  else
    ctx_atomic_publish "$tmp" "$dest" 600 || { rm -f "$tmp"; return 1; }
  fi
  digest_file="$dest.sha256"; digest_tmp="$(mktemp)"; ctx_codex_profile_digest "$dest" >"$digest_tmp"
  ctx_atomic_publish "$digest_tmp" "$digest_file" 600 || { rm -f "$tmp" "$digest_tmp"; return 1; }
  rm -f "$tmp" "$digest_tmp"; printf '%s\n' "$dest"
}

profile_digest() {
  local runtime="$1" path="$2"
  if [ "$runtime" = codex ]; then ctx_codex_profile_digest "$path"; else ctx_sha256 "$path"; fi
}

probe_codex_profile() {
  local bin="${DR_ORCH_CODEX_BIN:-codex}" output session pane pane_pid captured ready=0 exited=0 attempt profile probe_home response hooks
  [ "${DR_ORCH_SKIP_RUNTIME_PROBE:-0}" != 1 ] || return 0
  command -v "$bin" >/dev/null 2>&1 || return 1
  output="$(CODEX_HOME="${CODEX_HOME:-$HOME/.codex}" "$bin" --profile datarim-orchestrate-context debug prompt-input 2>/dev/null)" || return 1
  grep -qF DATARIM_CONTEXT_PROFILE_CANARY <<<"$output" || return 1
  profile="${CODEX_HOME:-$HOME/.codex}/datarim-orchestrate-context.config.toml"; probe_home="$(mktemp -d "$(ctx_state_root)/config/codex-probe.XXXXXX")"; chmod 700 "$probe_home"; cp "$profile" "$probe_home/config.toml"; chmod 600 "$probe_home/config.toml"
  response="$({ printf '%s\n' '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"datarim_probe","title":"Datarim hook probe","version":"1"}}}' '{"method":"initialized"}' "{\"method\":\"hooks/list\",\"id\":1,\"params\":{\"cwds\":[\"$PWD\"]}}"; sleep 1; } | HOME="$probe_home" CODEX_HOME="$probe_home" "$bin" app-server 2>/dev/null | jq -c 'select(.id==1)')" || { rm -rf -- "$probe_home"; return 1; }
  hooks="$(jq -r '[.result.data[0].hooks[] | select((.eventName=="sessionStart" or .eventName=="postCompact") and .handlerType=="command")] | length' <<<"$response")"; rm -rf -- "$probe_home"; [ "$hooks" -eq 2 ] || return 1
  command -v tmux >/dev/null 2>&1 || return 1; session="dr-context-probe-$$-$RANDOM"
  tmux new-session -d -s "$session" -x 160 -y 40 "env CODEX_HOME=$(printf '%q' "${CODEX_HOME:-$HOME/.codex}") $(printf '%q' "$bin") --no-alt-screen --strict-config --profile datarim-orchestrate-context" || return 1
  pane="$(tmux display-message -p -t "$session" '#{pane_id}')"
  for ((attempt=1; attempt<=50; attempt++)); do
    captured="$(tmux capture-pane -p -t "$pane" 2>/dev/null || true)"
    grep -Eqi 'configuration error|unknown (field|feature)|failed to load' <<<"$captured" && break
    if grep -Eqi 'OpenAI Codex|Sign in with ChatGPT|Use an API key|Do you trust the contents of this directory' <<<"$captured"; then ready=1; break; fi
    sleep 0.1
  done
  pane_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)"
  tmux send-keys -t "$pane" C-c 2>/dev/null || true
  for ((attempt=1; attempt<=20; attempt++)); do
    if [ "$(tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null || printf 1)" = 1 ] || ! kill -0 "$pane_pid" 2>/dev/null; then exited=1; break; fi
    sleep 0.05
  done
  if [ "$exited" -ne 1 ]; then
    tmux send-keys -t "$pane" C-c 2>/dev/null || true
    for ((attempt=1; attempt<=20; attempt++)); do
      if [ "$(tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null || printf 1)" = 1 ] || ! kill -0 "$pane_pid" 2>/dev/null; then exited=1; break; fi
      sleep 0.05
    done
  fi
  tmux kill-session -t "$session" 2>/dev/null || true
  [ "$ready" -eq 1 ] && [ "$exited" -eq 1 ]
}

pane_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }

nonterminal_ref_exists() {
  local instance="$1" root file state
  root="$(ctx_state_root)"
  for file in "$root"/transactions/*.json; do
    [ -f "$file" ] || continue
    [ "$(jq -r '.instance' "$file")" = "$instance" ] || continue
    state="$(jq -r '.state' "$file")"; case "$state" in completed|aborted) ;; *) return 0 ;; esac
  done
  return 1
}

prune_retired() {
  local root cap instance payload expected actual key candidate lock store_lock failed=0
  root="$(ctx_state_root)"; lock="$root/instances/.lifecycle.lock"; store_lock="$root/transactions/.store.lock"
  ctx_lock_acquire "$lock" || return 1; ctx_lock_acquire "$store_lock" || { ctx_lock_release "$lock"; return 1; }
  while [ "$(find "$root/instances" -maxdepth 1 -name '*.meta.json' -type f | wc -l)" -ge 16 ]; do
    candidate="$(for cap in "$root"/instances/*.retired; do [ -f "$cap" ] || continue; instance="$(basename "$cap" .retired)"; printf '%020d\t%s\n' "$(jq -r '.created_seq' "$root/instances/$instance.meta.json")" "$cap"; done | sort -n | head -1)"; cap="${candidate#*$'\t'}"
    [ -n "$cap" ] || { failed=1; break; }; instance="$(basename "$cap" .retired)"
    nonterminal_ref_exists "$instance" && { failed=1; break; }
    grep -Rqs -- "$instance" "$root/active" && { failed=1; break; }
    payload="$(mktemp)"; jq -c '.payload' "$cap" >"$payload"; key="$root/instances/$instance.cap"; [ -f "$key" ] || key="$root/instances/$instance.retired-key"; expected="$(ctx_hmac "$key" "$payload")"; actual="$(jq -r '.tag' "$cap")"; rm -f "$payload"
    [ "$expected" = "$actual" ] || { failed=1; break; }
    rm -f "$root/instances/$instance.cap" "$root/instances/$instance.retired-key" "$root/instances/$instance.seq" "$root/instances/$instance.meta.json" "$root/instances/$instance.current" "$root/instances/$instance.ready.json" "$root/instances/$instance.pressure.json" "$root/instances/$instance.consumed" "$root/instances/$instance.replaced" "$root/instances/$instance.replaced-old" "$cap" "$root/events/$instance-"*.json
  done
  ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; [ "$failed" -eq 0 ]
}

prune_replacement_staging() {
  local root dir instance meta cap claim claim_history map marker canonical_meta canonical_cap old_payload new_payload old_expected old_actual new_expected new_actual lock store_lock failed=0
  root="$(ctx_state_root)"; lock="$root/instances/.lifecycle.lock"; store_lock="$root/transactions/.store.lock"
  ctx_lock_acquire "$lock" || return 1; ctx_lock_acquire "$store_lock" || { ctx_lock_release "$lock"; return 1; }
  for dir in "$root"/replacements/*; do
    [ -d "$dir" ] || continue; instance="$(basename "$dir")"; ctx_instance_safe "$instance" || { failed=1; break; }
    meta="$dir/rollback-metadata.json"; cap="$dir/rollback-capability"; claim="$dir/old-claim.json"; ctx_secure_regular "$meta" 600 && ctx_secure_regular "$cap" 600 && ctx_secure_regular "$claim" 600 && [ "$(jq -r '.instance' "$meta")" = "$instance" ] && ctx_incarnation_safe "$(jq -r '.incarnation' "$meta")" || { failed=1; break; }
    nonterminal_ref_exists "$instance" && continue
    map="$root/active/$(pane_key "$(jq -r '.pane' "$meta")").map"; marker="$root/instances/$instance.replaced"; claim_history="$root/instances/$instance.replaced-old"; canonical_meta="$root/instances/$instance.meta.json"; canonical_cap="$root/instances/$instance.cap"
    if [ -f "$map" ] && [ "$(cat "$map")" = "$instance" ]; then
      if [ -e "$marker" ]; then
        ctx_secure_regular "$marker" 600 && ctx_secure_regular "$canonical_meta" 600 && ctx_secure_regular "$canonical_cap" 600 || { failed=1; break; }
        old_payload="$(mktemp)"; new_payload="$(mktemp)"; jq -c '.payload' "$claim" >"$old_payload"; jq -c '.payload' "$marker" >"$new_payload"; old_expected="$(ctx_hmac "$cap" "$old_payload")"; old_actual="$(jq -r '.tag' "$claim")"; new_expected="$(ctx_hmac "$canonical_cap" "$new_payload")"; new_actual="$(jq -r '.tag' "$marker")"
        if [ "$old_expected" != "$old_actual" ] || [ "$new_expected" != "$new_actual" ] || [ "$(jq -r '.kind' "$old_payload")" != instance_replacement_claim ] || [ "$(jq -r '.kind' "$new_payload")" != instance_replaced ] || [ "$(jq -r '.instance' "$old_payload")" != "$instance" ] || [ "$(jq -r '.instance' "$new_payload")" != "$instance" ] || [ "$(jq -r '.pane' "$old_payload")" != "$(jq -r '.pane' "$meta")" ] || [ "$(jq -r '.pane' "$new_payload")" != "$(jq -r '.pane' "$meta")" ] || [ "$(jq -r '.old_incarnation' "$old_payload")" != "$(jq -r '.incarnation' "$meta")" ] || [ "$(jq -r '.old_incarnation' "$new_payload")" != "$(jq -r '.incarnation' "$meta")" ] || [ "$(jq -r '.new_incarnation' "$old_payload")" != "$(jq -r '.incarnation' "$canonical_meta")" ] || [ "$(jq -r '.new_incarnation' "$new_payload")" != "$(jq -r '.incarnation' "$canonical_meta")" ] || [ "$(jq -r '.new_metadata_digest' "$old_payload")" != "$(ctx_sha256 "$canonical_meta")" ] || [ "$(jq -r '.new_metadata_digest' "$new_payload")" != "$(ctx_sha256 "$canonical_meta")" ] || [ "$(jq -r '.old_claim_digest' "$new_payload")" != "$(ctx_sha256 "$claim")" ]; then rm -f "$old_payload" "$new_payload"; failed=1; break; fi
        rm -f "$old_payload" "$new_payload"; mv "$claim" "$claim_history" && rm -f "$meta" "$cap" && rmdir "$dir" || { failed=1; break; }
      else
        rm -f "$canonical_meta" "$canonical_cap" "$claim"; mv "$cap" "$canonical_cap" && mv "$meta" "$canonical_meta" && rmdir "$dir" || { failed=1; break; }
      fi
      continue
    fi
    rm -f "$meta" "$cap" "$claim"; rmdir "$dir" || { failed=1; break; }
  done
  ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; [ "$failed" -eq 0 ]
}

install_runtime() {
  local runtime="${1:-}" root instance incarnation pane epoch socket task workspace label map old path cap_source meta_source
  require_enabled || die 'context-window automation requires both explicit trust flags'
  ctx_state_init; prune_replacement_staging || die 'replacement staging validation failed'; root="$(ctx_state_root)"
  pane="${DR_ORCH_CONTEXT_PANE:-unbound}"; epoch="${DR_ORCH_CONTEXT_EPOCH:-unbound}"; socket="${DR_ORCH_CONTEXT_SOCKET:-unbound}"; task="${DR_ORCH_ACTIVE_TASK:-}"; workspace="${DR_ORCH_WORKSPACE:-}"; label="$(config_value policy_label)"
  ctx_pane_safe "$pane" && [[ "$task" =~ ^[A-Z]+-[0-9]+$ ]] && [[ "$workspace" = /* ]] && [ -d "$workspace" ] || die 'orchestrator launch bindings are required'
  if [ "${DR_ORCH_SKIP_RUNTIME_PROBE:-0}" != 1 ]; then [[ "$epoch" =~ ^[a-f0-9]{32}$ ]] && [ -S "$socket" ] || die 'live tmux socket and epoch are required'; fi
  [[ -z "$label" || "$label" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || die 'unsafe policy label'
  path="$(render_runtime "$runtime")" || return 1
  map="$root/active/$(pane_key "$pane").map"; instance="$(ctx_random_hex 16)"; if [ -f "$map" ]; then instance="$(cat "$map")"; ctx_instance_safe "$instance" || die 'unsafe active pane mapping'; fi
  incarnation="$(ctx_random_hex 16)"; cap_source="$(mktemp)"; meta_source="$(mktemp)"; printf '%s\n' "$(ctx_random_hex 32)" >"$cap_source"; chmod 600 "$cap_source"
  jq -n -c --arg instance "$instance" --arg incarnation "$incarnation" --arg runtime "$runtime" --arg pane "$pane" --arg epoch "$epoch" --arg socket "$socket" --arg task "$task" --arg workspace "$workspace" --arg label "$label" --arg overlay "$path" --arg digest "$(profile_digest "$runtime" "$path")" --arg pid "$$" --arg birth "$(ctx_process_birth "$$")" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{instance:$instance,incarnation:$incarnation,runtime:$runtime,pane:$pane,epoch:$epoch,socket:$socket,task:$task,workspace:$workspace,label:$label,overlay:$overlay,overlay_digest:$digest,process_pid:$pid,process_birth:$birth,runtime_bound:false,created_at:$created_at}' >"$meta_source"; chmod 600 "$meta_source"
  if [ -f "$map" ]; then
    old="$(cat "$map")"; bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" replace --old-instance "$old" --pane "$pane" --new-instance "$instance" --cap-source "$cap_source" --meta-source "$meta_source" || { rm -f "$cap_source" "$meta_source"; die 'active pane replacement proof failed'; }
  else
    prune_retired || { rm -f "$cap_source" "$meta_source"; die 'runtime-instance cap exhausted'; }
    bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" register --instance "$instance" --pane "$pane" --cap-source "$cap_source" --meta-source "$meta_source" || { rm -f "$cap_source" "$meta_source"; die 'instance registration failed'; }
  fi
  rm -f "$cap_source" "$meta_source"; printf 'instance=%s\nincarnation=%s\noverlay=%s\n' "$instance" "$incarnation" "$path"
}

render_runtime() {
  local runtime="${1:-}" path
  require_enabled || die 'context-window automation requires both explicit trust flags'; ctx_state_init
  case "$runtime" in
    claude) path="$(write_claude)" || return 1 ;;
    codex) path="$(write_codex)" || return 1; probe_codex_profile || return 1 ;;
    *) die 'runtime must be claude or codex' ;;
  esac
  printf '%s\n' "$path"
}

doctor() {
  ctx_state_init; prune_replacement_staging || die 'replacement staging validation failed'
  printf 'context_window_state=ready\n'
  printf 'same_uid_origin=trusted_by_explicit_opt_in\n'
}

recover_stale() {
  local root map instance current_socket current_epoch failed=0
  command -v tmux >/dev/null 2>&1 || die 'tmux is required for recovery proof'
  current_socket="${DR_ORCH_CONTEXT_TMUX_SOCKET:-$(tmux display-message -p '#{socket_path}' 2>/dev/null || true)}"
  [ -S "$current_socket" ] || die 'current tmux socket proof is required'
  current_epoch="$(tmux -S "$current_socket" show-options -gv @datarim_context_epoch 2>/dev/null || true)"
  [[ "$current_epoch" =~ ^[a-f0-9]{32}$ ]] || die 'current tmux epoch proof is required'
  root="$(ctx_state_root)"
  for map in "$root"/active/*.map; do
    [ -f "$map" ] || continue; instance="$(cat "$map")"
    bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" retire --instance "$instance" --pane "$(jq -r '.pane' "$root/instances/$instance.meta.json")" --recovery true --current-epoch "$current_epoch" || failed=1
  done
  [ "$failed" -eq 0 ]
}

bind_process() {
  local instance="$1" incarnation="$2" pid="$3" birth root file tmp lock
  ctx_instance_safe "$instance" && ctx_incarnation_safe "$incarnation" || die 'invalid instance or incarnation'; [[ "$pid" =~ ^[0-9]+$ ]] || die 'invalid process id'; birth="$(ctx_process_birth "$pid")" || die 'process is not alive'; ctx_process_live "$pid" || die 'process is not live'
  root="$(ctx_state_root)"; file="$root/instances/$instance.meta.json"; lock="$root/instances/.lifecycle.lock"; ctx_lock_acquire "$lock" || die 'instance lifecycle lock unavailable'
  if ! ctx_secure_regular "$file" 600 || [ "$(jq -r '.incarnation' "$file")" != "$incarnation" ] || [ "$(jq -r '.runtime_bound' "$file")" != false ]; then ctx_lock_release "$lock"; die 'instance incarnation is not bindable'; fi
  tmp="$(mktemp)"; jq -c --arg pid "$pid" --arg birth "$birth" '.process_pid=$pid|.process_birth=$birth|.runtime_bound=true' "$file" >"$tmp"
  if ! ctx_atomic_publish "$tmp" "$file" 600; then rm -f "$tmp"; ctx_lock_release "$lock"; die 'process binding publish failed'; fi
  rm -f "$tmp"; ctx_lock_release "$lock"
}

retire_pane() {
  local pane="$1" root map instance
  root="$(ctx_state_root)"; map="$root/active/$(pane_key "$pane").map"
  ctx_secure_regular "$map" 600 || die 'active mapping missing'; instance="$(cat "$map")"
  bash "$DR_ORCH_DIR/scripts/context_window_controller.sh" retire --instance "$instance" --pane "$pane"
}

remove_owned() {
  local runtime="${1:-}" dest digest_file expected
  case "$runtime" in claude) dest="$(ctx_state_root)/config/context-window-hooks.claude.json" ;; codex) dest="${CODEX_HOME:-$HOME/.codex}/datarim-orchestrate-context.config.toml" ;; *) die 'runtime must be claude or codex' ;; esac
  if [ -e "$dest" ]; then
    digest_file="$dest.sha256"; ctx_secure_regular "$dest" 600 && ctx_secure_regular "$digest_file" 600 || die 'refusing unsafe removal'
    expected="$(cat "$digest_file")"
    if [ "$runtime" = codex ]; then [ "$(ctx_codex_profile_digest "$dest")" = "$expected" ] || die 'refusing modified runtime overlay'; else [ "$(ctx_sha256 "$dest")" = "$expected" ] || die 'refusing modified runtime overlay'; fi
    rm -f "$dest" "$digest_file"
  fi
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    enabled) require_enabled ;;
    render) [ "${1:-}" = --runtime ] || die '--runtime required'; render_runtime "${2:-}" ;;
    install) [ "${1:-}" = --runtime ] || die '--runtime required'; install_runtime "${2:-}" ;;
    doctor) if [ "${1:-}" = --recover-stale-instances ]; then recover_stale; else doctor; fi ;;
    bind-process) bind_process "${1:-}" "${2:-}" "${3:-}" ;;
    retire) [ "${1:-}" = --pane ] || die '--pane required'; retire_pane "${2:-}" ;;
    remove) [ "${1:-}" = --runtime ] || die '--runtime required'; remove_owned "${2:-}" ;;
    *) die 'usage: context_window_setup.sh {render|install|doctor|bind-process|retire|remove}' ;;
  esac
}
main "$@"
