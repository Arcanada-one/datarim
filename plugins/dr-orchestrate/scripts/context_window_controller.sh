#!/usr/bin/env bash
# Deterministic context-window controller.
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/context-window-state.sh
source "$DR_ORCH_DIR/scripts/lib/context-window-state.sh"

die() { printf 'ERR: %s\n' "$*" >&2; return 2; }

audit_tx() {
  local file="$1" event="$2" result="$3" root audit lock line combined trimmed
  root="$(ctx_state_root)"; audit="$root/audit/context-window.jsonl"; lock="$audit.lock"; ctx_lock_acquire "$lock" || return 1
  line="$(mktemp)"; jq -n -c --arg event "$event" --arg result "$result" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --slurpfile tx "$file" '{at:$at,event:$event,result:$result,transaction:$tx[0].id,task:$tx[0].task,instance:$tx[0].instance,mode:$tx[0].mode,snapshot_digest:$tx[0].snapshot_digest,generation:$tx[0].generation}' >"$line"
  combined="$(mktemp)"; [ ! -f "$audit" ] || { ctx_secure_regular "$audit" 600 || { rm -f "$line" "$combined"; ctx_lock_release "$lock"; return 1; }; cat "$audit" >"$combined"; }
  cat "$line" >>"$combined"; trimmed="$(mktemp)"; tail -n 5000 "$combined" >"$trimmed"
  ctx_atomic_publish "$trimmed" "$audit" 600 || { rm -f "$line" "$combined" "$trimmed"; ctx_lock_release "$lock"; return 1; }
  rm -f "$line" "$combined" "$trimmed"; ctx_lock_release "$lock"
}

arg_value() {
  local wanted="$1"; shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "$wanted" ]; then [ "$#" -ge 2 ] || return 1; printf '%s' "$2"; return 0; fi
    shift
  done
  return 1
}

policy_mode() {
  local used="$1" file="${DR_CONTEXT_POLICY_FILE:-}" label="${DR_CONTEXT_POLICY_LABEL:-}" before after fd_path result rc
  [ -n "$file" ] && [ -n "$label" ] || return 3
  ctx_secure_parent "$file" && ctx_secure_regular "$file" 600 || return 1
  [ "$(wc -c <"$file")" -le 16384 ] && [ "$(wc -l <"$file")" -le 128 ] || return 1
  [[ "$label" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
  before="$(ctx_identity "$file")"; exec {policy_fd}<"$file"; fd_path="/proc/self/fd/$policy_fd"; [ -e "$fd_path" ] || fd_path="/dev/fd/$policy_fd"
  [ "$(ctx_identity "$fd_path")" = "$before" ] || { exec {policy_fd}<&-; return 1; }
  set +e; result="$(awk -F '\t' -v label="$label" -v used="$used" '
    BEGIN { found=0 }
    /^[[:space:]]*#/ || NF==0 { next }
    NF!=3 || $1 !~ /^[a-z0-9][a-z0-9._-]{0,63}$/ || ($2!="selective_drop" && $2!="full_clear") || $3 !~ /^[0-9]+$/ || $3<50 || $3>100 { bad=1; next }
    seen[$1]++ > 0 { bad=1; next }
    $1==label { found=1; mode=$2; floor=$3 }
    END { if (bad) exit 2; if (found && used>=floor) print mode; else if (found) exit 3; else exit 4 }
  ' "$fd_path")"; rc=$?; set -e
  after="$(ctx_identity "$file")"; exec {policy_fd}<&-; [ "$after" = "$before" ] || return 1
  [ "$rc" -eq 0 ] && printf '%s\n' "$result"; return "$rc"
}

evaluate() {
  local used mode rc
  used="$(arg_value --used-percent "$@")" || die '--used-percent is required'
  [[ "$used" =~ ^[0-9]+$ ]] && [ "$used" -le 100 ] || die 'used percent must be integer 0..100'
  set +e; mode="$(policy_mode "$used")"; rc=$?; set -e
  if [ "$rc" -eq 0 ]; then printf '%s\n' "$mode"; return 0; fi
  [ "$rc" -eq 3 ] || [ "$rc" -eq 4 ] || die 'unsafe taught policy'
  if [ "$used" -ge 90 ]; then printf 'full_clear\n'
  elif [ "$used" -ge 75 ]; then printf 'selective_drop\n'
  else printf 'no_op\n'; fi
}

instruction() {
  local runtime mode
  runtime="$(arg_value --runtime "$@")" || die '--runtime is required'
  mode="$(arg_value --mode "$@")" || die '--mode is required'
  case "$runtime:$mode" in
    codex:selective_drop) printf '/compact\n' ;;
    claude:selective_drop) printf '/compact Preserve active Datarim task pointer last completed phase current plan open verification findings and next action\n' ;;
    codex:full_clear|claude:full_clear) printf '/clear\n' ;;
    *) die 'unsupported runtime or mode' ;;
  esac
}

validate_task_snapshot() {
  local workspace="$1" task="$2" snap
  snap="$workspace/datarim/snapshots/$task.snapshot.md"
  [[ "$task" =~ ^[A-Z]+-[0-9]+$ ]] || return 1
  ctx_secure_parent "$snap" && ctx_secure_regular "$snap" 600 || return 1
  grep -q "^task_id: $task$" "$snap" || return 1
  grep -qE '^stage: (init|prd|plan|design|do|qa|verify|compliance|archive)$' "$snap" || return 1
  printf '%s' "$snap"
}

prepare() {
  local task workspace runtime instance incarnation pane conversation mode snap root id file tmp stage task_desc lock lifecycle_lock map meta candidate state count snap_digest snap_identity task_desc_identity task_desc_digest generation generation_file created_at created_seq
  task="$(arg_value --task "$@")"; workspace="$(arg_value --workspace "$@")"
  runtime="$(arg_value --runtime "$@")"; instance="$(arg_value --instance "$@")"
  incarnation="$(arg_value --incarnation "$@" 2>/dev/null || true)"
  pane="$(arg_value --pane "$@")"; conversation="$(arg_value --conversation "$@")"
  mode="$(arg_value --mode "$@")"
  if [ "${DR_ORCH_TEST_ALLOW_UNBOUND:-0}" = 1 ] && [ -z "$incarnation" ]; then incarnation="00000000000000000000000000000000"; fi
  ctx_instance_safe "$instance" && ctx_incarnation_safe "$incarnation" && ctx_pane_safe "$pane" || die 'unsafe instance, incarnation, or pane'
  case "$runtime:$mode" in claude:selective_drop|claude:full_clear|codex:selective_drop|codex:full_clear) ;; *) die 'unsupported runtime or mode' ;; esac
  snap="$(validate_task_snapshot "$workspace" "$task")" || die 'invalid task snapshot'
  task_desc="$workspace/datarim/tasks/$task-task-description.md"
  ctx_secure_parent "$task_desc" && ctx_secure_owner_regular "$task_desc" || die 'invalid task description'
  snap_identity="$(ctx_identity "$snap")"; snap_digest="$(ctx_sha256 "$snap")"; task_desc_identity="$(ctx_identity "$task_desc")"; task_desc_digest="$(ctx_sha256 "$task_desc")"
  stage="$(awk '/^stage: /{print $2; exit}' "$snap")"; [ "$(ctx_identity "$snap")" = "$snap_identity" ] && [ "$(ctx_sha256 "$snap")" = "$snap_digest" ] || die 'snapshot changed during prepare'; root="$(ctx_state_root)"
  ctx_state_init; lifecycle_lock="$root/instances/.lifecycle.lock"; lock="$root/transactions/.store.lock"
  ctx_lock_acquire "$lifecycle_lock" || die 'instance lifecycle lock unavailable'
  ctx_lock_acquire "$lock" || { ctx_lock_release "$lifecycle_lock"; die 'transaction store lock unavailable'; }
  if [ "${DR_ORCH_TEST_ALLOW_UNBOUND:-0}" != 1 ]; then
    map="$root/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; meta="$root/instances/$instance.meta.json"
    if ! ctx_secure_regular "$map" 600 || [ "$(cat "$map")" != "$instance" ] || [ -e "$root/instances/$instance.retired" ] || ! ctx_secure_regular "$meta" 600 ||
      [ "$(jq -r '.runtime' "$meta")" != "$runtime" ] || [ "$(jq -r '.incarnation' "$meta")" != "$incarnation" ] || [ "$(jq -r '.pane' "$meta")" != "$pane" ] || [ "$(jq -r '.task' "$meta")" != "$task" ] || [ "$(jq -r '.workspace' "$meta")" != "$workspace" ]; then
      ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'runtime instance changed before prepare'
    fi
  fi
  for candidate in "$root"/transactions/*.json; do
    [ -f "$candidate" ] || continue
    [ "$(jq -r '.instance' "$candidate")" = "$instance" ] || continue
    state="$(jq -r '.state' "$candidate")"; if ! ctx_terminal_state "$state"; then ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'instance already has nonterminal transaction'; fi
  done
  count="$(find "$root/transactions" -maxdepth 1 -name '*.json' -type f | wc -l)"
  while [ "$count" -ge 64 ]; do
    candidate="$(for file in "$root"/transactions/*.json; do [ -f "$file" ] || continue; state="$(jq -r '.state' "$file")"; if ctx_terminal_state "$state"; then printf '%020d\t%s\n' "$(jq -r '.created_seq' "$file")" "$file"; fi; done | sort -n | head -1)"; candidate="${candidate#*$'\t'}"
    [ -n "$candidate" ] || { ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'transaction cap exhausted by protected records'; }
    rm -f "$candidate"; count=$((count - 1))
  done
  generation_file="$root/instances/$instance.generation"; generation=0; [ ! -f "$generation_file" ] || generation="$(cat "$generation_file")"; [[ "$generation" =~ ^[0-9]+$ ]] || { ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'invalid generation'; }; generation=$((generation + 1))
  tmp="$(mktemp)"; printf '%s\n' "$generation" >"$tmp"; ctx_atomic_publish "$tmp" "$generation_file" 600 || { rm -f "$tmp"; ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'generation publish failed'; }; rm -f "$tmp"; created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; created_seq="$(ctx_next_sequence "$root/transactions/.creation-seq")" || { ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'transaction sequence reservation failed'; }
  id="$(ctx_random_hex 16)"; file="$root/transactions/$id.json"; tmp="$(mktemp)"
  jq -n -c --arg id "$id" --arg task "$task" --arg runtime "$runtime" --arg instance "$instance" --arg incarnation "$incarnation" \
    --arg pane "$pane" --arg conversation "$conversation" --arg mode "$mode" --arg stage "$stage" \
    --arg workspace "$workspace" --arg snapshot "datarim/snapshots/$task.snapshot.md" --arg digest "$snap_digest" --arg snapshot_identity "$snap_identity" --arg task_desc "datarim/tasks/$task-task-description.md" --arg task_desc_identity "$task_desc_identity" --arg task_desc_digest "$task_desc_digest" --argjson generation "$generation" --arg created_at "$created_at" --argjson created_seq "$created_seq" \
    '{id:$id,task:$task,runtime:$runtime,instance:$instance,incarnation:$incarnation,pane:$pane,conversation:$conversation,mode:$mode,stage:$stage,workspace:$workspace,snapshot:$snapshot,snapshot_digest:$digest,snapshot_identity:$snapshot_identity,task_description:$task_desc,task_description_identity:$task_desc_identity,task_description_digest:$task_desc_digest,generation:$generation,created_at:$created_at,created_seq:$created_seq,state:"prepared"}' >"$tmp"
  [ "$(wc -c <"$tmp")" -le 4096 ] || { rm -f "$tmp"; ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'transaction exceeds size cap'; }
  ctx_atomic_publish "$tmp" "$file" 600 || { rm -f "$tmp"; ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'transaction publish failed'; }; rm -f "$tmp"
  tmp="$(mktemp)"; printf '%s\n' "$id" >"$tmp"; ctx_atomic_publish "$tmp" "$root/instances/$instance.current" 600 || { rm -f "$tmp" "$file"; ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; die 'current-pointer publish failed'; }
  rm -f "$tmp"; ctx_lock_release "$lock"; ctx_lock_release "$lifecycle_lock"; audit_tx "$file" prepared success || die 'prepare audit failed'; printf '%s\n' "$id"
}

reconcile() {
  local id action file root state
  id="$(arg_value --transaction "$@")"; action="$(arg_value --action "$@")"
  [[ "$id" =~ ^[a-f0-9]{32}$ ]] || die 'invalid transaction'
  [ "$action" = report ] || [ "$action" = abort ] || die 'invalid reconcile action'
  root="$(ctx_state_root)"; file="$root/transactions/$id.json"; ctx_secure_regular "$file" 600 || die 'transaction not found'
  if [ "$action" = report ]; then jq -c '{id,state,task,mode}' "$file"; return 0; fi
  state="$(jq -r '.state' "$file")"; ctx_terminal_state "$state" && die 'transaction already terminal'
  tx_transition "$file" "$state" aborted || die 'abort compare-and-swap failed'; audit_tx "$file" reconciled aborted || die 'reconcile audit failed'
}

instance_has_nonterminal() {
  local instance="$1" file state
  for file in "$(ctx_state_root)"/transactions/*.json; do
    [ -f "$file" ] || continue; [ "$(jq -r '.instance' "$file")" = "$instance" ] || continue
    state="$(jq -r '.state' "$file")"; ctx_terminal_state "$state" || return 0
  done
  return 1
}

retire_instance() {
  local instance="$1" pane="$2" recovery="${3:-0}" keep_lock="${4:-0}" current_epoch="${5:-}" root map meta socket epoch pid birth current_birth lock store_lock cap payload tag marker tmp
  ctx_instance_safe "$instance" && ctx_pane_safe "$pane" || die 'unsafe retirement binding'
  root="$(ctx_state_root)"; map="$root/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; meta="$root/instances/$instance.meta.json"
  lock="$root/instances/.lifecycle.lock"; ctx_lock_acquire "$lock" || die 'instance lifecycle lock unavailable'
  if ! ctx_secure_regular "$map" 600 || [ "$(cat "$map")" != "$instance" ] || ! ctx_secure_regular "$meta" 600; then ctx_lock_release "$lock"; die 'active instance mapping mismatch'; fi
  [ "$(jq -r '.pane' "$meta")" = "$pane" ] || { ctx_lock_release "$lock"; die 'metadata pane mismatch'; }
  socket="$(jq -r '.socket' "$meta")"; epoch="$(jq -r '.epoch' "$meta")"; pid="$(jq -r '.process_pid' "$meta")"; birth="$(jq -r '.process_birth' "$meta")"
  [[ "$pid" =~ ^[0-9]+$ && "$birth" != pending ]] || { ctx_lock_release "$lock"; die 'runtime process binding is incomplete'; }
  current_birth="$(ctx_process_birth "$pid" 2>/dev/null || true)"; if [ "$current_birth" = "$birth" ] && ctx_process_live "$pid"; then ctx_lock_release "$lock"; die 'bound process is still alive'; fi
  if [ -S "$socket" ] && [ "$(tmux -S "$socket" display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null || printf missing)" != 1 ] && tmux -S "$socket" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq "$pane"; then
    ctx_lock_release "$lock"; die 'bound tmux pane is still alive'
  fi
  if [ "$recovery" = 1 ]; then
    [[ "$current_epoch" =~ ^[a-f0-9]{32}$ ]] && [ "$current_epoch" != "$epoch" ] || { ctx_lock_release "$lock"; die 'stale recovery requires a distinct current epoch'; }
    if [ -S "$socket" ]; then
      [ "$(tmux -S "$socket" show-options -gv @datarim_context_epoch 2>/dev/null || true)" != "$epoch" ] || { ctx_lock_release "$lock"; die 'stale recovery epoch is still current'; }
    fi
  fi
  store_lock="$root/transactions/.store.lock"; ctx_lock_acquire "$store_lock" || { ctx_lock_release "$lock"; die 'transaction store lock unavailable'; }
  instance_has_nonterminal "$instance" && { ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'instance has nonterminal work'; }
  cap="$root/instances/$instance.cap"; ctx_secure_regular "$cap" 600 || { ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'capability missing'; }
  payload="$(mktemp)"; jq -n -c --arg instance "$instance" --arg pane "$pane" --arg epoch "$epoch" '{kind:"instance_retired",instance:$instance,pane:$pane,epoch:$epoch}' >"$payload"
  tag="$(ctx_hmac "$cap" "$payload")"; tmp="$(mktemp)"; jq -n -c --slurpfile p "$payload" --arg tag "$tag" '{payload:$p[0],tag:$tag}' >"$tmp"; marker="$root/instances/$instance.retired"
  ctx_atomic_publish "$tmp" "$marker" 600 || { rm -f "$payload" "$tmp"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'retired marker publish failed'; }
  jq -n -c --arg instance "$instance" --arg task "$(jq -r '.task' "$meta")" '{id:"none",task:$task,instance:$instance,mode:"retire",snapshot_digest:"none",generation:0}' >"$payload"
  audit_tx "$payload" instance_retired success || { rm -f "$payload" "$tmp"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'retirement audit failed'; }
  rm -f "$payload" "$tmp" "$map"; ctx_lock_release "$store_lock"; [ "$keep_lock" = 1 ] || ctx_lock_release "$lock"
}

retire() {
  local instance pane recovery=0 current_epoch=""
  instance="$(arg_value --instance "$@")" || die '--instance is required'; pane="$(arg_value --pane "$@")" || die '--pane is required'
  [ "$(arg_value --recovery "$@" 2>/dev/null || true)" != true ] || recovery=1
  current_epoch="$(arg_value --current-epoch "$@" 2>/dev/null || true)"
  retire_instance "$instance" "$pane" "$recovery" 0 "$current_epoch"
}

replace() {
  local instance pane new_instance cap_source meta_source root map meta lock store_lock cap stage_dir stage_cap stage_meta stage_claim marker claim_history audit_tmp claim_payload claim_envelope final_payload final_envelope new_meta socket epoch pid birth current_birth fail created_seq tag old_incarnation new_incarnation new_digest claim_digest
  instance="$(arg_value --old-instance "$@")" || die '--old-instance is required'; pane="$(arg_value --pane "$@")" || die '--pane is required'
  new_instance="$(arg_value --new-instance "$@")" || die '--new-instance is required'; cap_source="$(arg_value --cap-source "$@")" || die '--cap-source is required'; meta_source="$(arg_value --meta-source "$@")" || die '--meta-source is required'
  ctx_instance_safe "$new_instance" && ctx_secure_regular "$cap_source" 600 && ctx_secure_regular "$meta_source" 600 || die 'unsafe replacement sources'
  [ "$new_instance" = "$instance" ] || die 'same-pane replacement must reuse its bounded instance slot'
  [ "$(jq -r '.instance' "$meta_source")" = "$new_instance" ] && [ "$(jq -r '.pane' "$meta_source")" = "$pane" ] && ctx_incarnation_safe "$(jq -r '.incarnation' "$meta_source")" || die 'replacement metadata mismatch'
  root="$(ctx_state_root)"; lock="$root/instances/.lifecycle.lock"; store_lock="$root/transactions/.store.lock"; map="$root/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; meta="$root/instances/$instance.meta.json"; cap="$root/instances/$instance.cap"; stage_dir="$root/replacements/$instance"; stage_cap="$stage_dir/rollback-capability"; stage_meta="$stage_dir/rollback-metadata.json"; stage_claim="$stage_dir/old-claim.json"; marker="$root/instances/$instance.replaced"; claim_history="$root/instances/$instance.replaced-old"; fail="${DR_ORCH_TEST_FAIL_REPLACE_AFTER:-}"
  ctx_lock_acquire "$lock" || die 'instance lifecycle lock unavailable'
  if ! ctx_secure_regular "$map" 600 || [ "$(cat "$map")" != "$instance" ] || ! ctx_secure_regular "$meta" 600 || ! ctx_secure_regular "$cap" 600 || [ "$(jq -r '.pane' "$meta")" != "$pane" ]; then ctx_lock_release "$lock"; die 'active instance mapping mismatch'; fi
  socket="$(jq -r '.socket' "$meta")"; epoch="$(jq -r '.epoch' "$meta")"; pid="$(jq -r '.process_pid' "$meta")"; birth="$(jq -r '.process_birth' "$meta")"; current_birth="$(ctx_process_birth "$pid" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ && "$birth" != pending ]] || { ctx_lock_release "$lock"; die 'old runtime process is still active or unbound'; }
  if [ "$current_birth" = "$birth" ] && ctx_process_live "$pid"; then ctx_lock_release "$lock"; die 'old runtime process is still active or unbound'; fi
  if [ -S "$socket" ] && [ "$(tmux -S "$socket" display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null || printf missing)" != 1 ] && tmux -S "$socket" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq "$pane"; then ctx_lock_release "$lock"; die 'old tmux pane is still active'; fi
  ctx_lock_acquire "$store_lock" || { ctx_lock_release "$lock"; die 'transaction store lock unavailable'; }
  instance_has_nonterminal "$instance" && { ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'instance has nonterminal work'; }
  audit_tmp="$(mktemp)"; jq -n -c --arg instance "$instance" --arg task "$(jq -r '.task' "$meta")" '{id:"none",task:$task,instance:$instance,mode:"replace",snapshot_digest:"none",generation:0}' >"$audit_tmp"
  audit_tx "$audit_tmp" instance_replacement_claimed success || { rm -f "$audit_tmp"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'replacement audit failed'; }
  created_seq="$(ctx_next_sequence "$root/instances/.creation-seq")" || { rm -f "$audit_tmp"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'instance sequence reservation failed'; }
  new_meta="$(mktemp)"; jq -c --argjson created_seq "$created_seq" '.created_seq=$created_seq' "$meta_source" >"$new_meta"; chmod 600 "$new_meta"
  old_incarnation="$(jq -r '.incarnation' "$meta")"; new_incarnation="$(jq -r '.incarnation' "$new_meta")"; ctx_incarnation_safe "$old_incarnation" && ctx_incarnation_safe "$new_incarnation" && [ "$old_incarnation" != "$new_incarnation" ] || { rm -f "$audit_tmp" "$new_meta"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'replacement incarnation proof failed'; }
  new_digest="$(ctx_sha256 "$new_meta")"; claim_payload="$(mktemp)"; jq -n -c --arg instance "$instance" --arg pane "$pane" --arg old_incarnation "$old_incarnation" --arg new_incarnation "$new_incarnation" --arg old_epoch "$epoch" --arg old_process_birth "$birth" --arg new_metadata_digest "$new_digest" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{kind:"instance_replacement_claim",instance:$instance,pane:$pane,old_incarnation:$old_incarnation,new_incarnation:$new_incarnation,old_epoch:$old_epoch,old_process_birth:$old_process_birth,new_metadata_digest:$new_metadata_digest,created_at:$created_at}' >"$claim_payload"; chmod 600 "$claim_payload"
  tag="$(ctx_hmac "$cap" "$claim_payload")" || { rm -f "$audit_tmp" "$new_meta" "$claim_payload"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'old capability claim signing failed'; }; claim_envelope="$(mktemp)"; jq -n -c --slurpfile payload "$claim_payload" --arg tag "$tag" '{payload:$payload[0],tag:$tag}' >"$claim_envelope"; chmod 600 "$claim_envelope"; claim_digest="$(ctx_sha256 "$claim_envelope")"
  final_payload="$(mktemp)"; jq -n -c --arg instance "$instance" --arg pane "$pane" --arg old_incarnation "$old_incarnation" --arg new_incarnation "$new_incarnation" --arg new_metadata_digest "$new_digest" --arg old_claim_digest "$claim_digest" '{kind:"instance_replaced",instance:$instance,pane:$pane,old_incarnation:$old_incarnation,new_incarnation:$new_incarnation,new_metadata_digest:$new_metadata_digest,old_claim_digest:$old_claim_digest}' >"$final_payload"; chmod 600 "$final_payload"
  tag="$(ctx_hmac "$cap_source" "$final_payload")" || { rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'new capability finalization signing failed'; }; final_envelope="$(mktemp)"; jq -n -c --slurpfile payload "$final_payload" --arg tag "$tag" '{payload:$payload[0],tag:$tag}' >"$final_envelope"; chmod 600 "$final_envelope"
  for prior in "$marker" "$claim_history"; do if [ -e "$prior" ]; then ctx_secure_regular "$prior" 600 || { rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'unsafe prior replacement proof'; }; rm -f "$prior"; fi; done
  [ ! -e "$stage_dir" ] && mkdir "$stage_dir" && chmod 700 "$stage_dir" || { rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'replacement staging collision'; }
  ctx_atomic_publish "$claim_envelope" "$stage_claim" 600 || { rmdir "$stage_dir"; rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'old capability claim publish failed'; }
  mv "$cap" "$stage_cap" && mv "$meta" "$stage_meta" || { [ ! -e "$stage_cap" ] || mv "$stage_cap" "$cap"; [ ! -e "$stage_meta" ] || mv "$stage_meta" "$meta"; rm -f "$stage_claim"; rmdir "$stage_dir" 2>/dev/null || true; rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'old instance staging failed'; }
  if [ "$fail" = old_key ] || ! ctx_atomic_publish "$cap_source" "$cap" 600; then mv "$stage_cap" "$cap"; mv "$stage_meta" "$meta"; rm -f "$stage_claim"; rmdir "$stage_dir"; rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'replacement capability publish failed'; fi
  if [ "$fail" = new_cap ] || ! ctx_atomic_publish "$new_meta" "$meta" 600; then rm -f "$cap"; mv "$stage_cap" "$cap"; mv "$stage_meta" "$meta"; rm -f "$stage_claim"; rmdir "$stage_dir"; rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'replacement metadata publish failed'; fi
  if [ "$fail" = new_meta ] || ! ctx_atomic_publish "$final_envelope" "$marker" 600; then rm -f "$cap" "$meta"; mv "$stage_cap" "$cap"; mv "$stage_meta" "$meta"; rm -f "$stage_claim"; rmdir "$stage_dir"; rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'replacement finalization marker publish failed'; fi
  if [ "$fail" = map_commit ]; then rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope"; ctx_lock_release "$store_lock"; ctx_lock_release "$lock"; die 'injected post-commit interruption'; fi
  mv "$stage_claim" "$claim_history"; rm -f "$audit_tmp" "$new_meta" "$claim_payload" "$claim_envelope" "$final_payload" "$final_envelope" "$stage_cap" "$stage_meta"; rmdir "$stage_dir"; rm -f "$root/instances/$instance.seq" "$root/instances/$instance.generation" "$root/instances/$instance.current" "$root/instances/$instance.ready.json" "$root/instances/$instance.pressure.json" "$root/instances/$instance.consumed" "$root/events/$instance-"*.json
  ctx_lock_release "$store_lock"; ctx_lock_release "$lock"
}

register_instance() {
  local instance pane cap_source meta_source root map lock tmp count created_seq prepared_meta
  instance="$(arg_value --instance "$@")" || die '--instance is required'; pane="$(arg_value --pane "$@")" || die '--pane is required'; cap_source="$(arg_value --cap-source "$@")" || die '--cap-source is required'; meta_source="$(arg_value --meta-source "$@")" || die '--meta-source is required'
  ctx_instance_safe "$instance" && ctx_pane_safe "$pane" && ctx_secure_regular "$cap_source" 600 && ctx_secure_regular "$meta_source" 600 && ctx_incarnation_safe "$(jq -r '.incarnation' "$meta_source")" || die 'unsafe registration sources'
  root="$(ctx_state_root)"; map="$root/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; lock="$root/instances/.lifecycle.lock"; ctx_lock_acquire "$lock" || die 'instance lifecycle lock unavailable'
  [ ! -e "$map" ] || { ctx_lock_release "$lock"; die 'pane mapping already exists'; }; count="$(find "$root/instances" -maxdepth 1 -name '*.meta.json' -type f | wc -l)"; [ "$count" -lt 16 ] || { ctx_lock_release "$lock"; die 'runtime-instance cap exhausted'; }
  created_seq="$(ctx_next_sequence "$root/instances/.creation-seq")" || { ctx_lock_release "$lock"; die 'instance sequence reservation failed'; }; prepared_meta="$(mktemp)"; jq -c --argjson created_seq "$created_seq" '.created_seq=$created_seq' "$meta_source" >"$prepared_meta"; chmod 600 "$prepared_meta"
  ctx_atomic_publish "$cap_source" "$root/instances/$instance.cap" 600 || { rm -f "$prepared_meta"; ctx_lock_release "$lock"; die 'instance capability publish failed'; }
  ctx_atomic_publish "$prepared_meta" "$root/instances/$instance.meta.json" 600 || { rm -f "$prepared_meta" "$root/instances/$instance.cap"; ctx_lock_release "$lock"; die 'instance metadata publish failed'; }; rm -f "$prepared_meta"
  tmp="$(mktemp)"; printf '%s\n' "$instance" >"$tmp"; ctx_atomic_publish "$tmp" "$map" 600 || { rm -f "$tmp" "$root/instances/$instance.cap" "$root/instances/$instance.meta.json"; ctx_lock_release "$lock"; die 'instance map publish failed'; }; rm -f "$tmp"; ctx_lock_release "$lock"
}

event_payload() {
  local event="$1" tmp instance cap expected actual
  ctx_secure_regular "$event" 600 || return 1
  instance="$(jq -r '.payload.instance // empty' "$event")"; ctx_instance_safe "$instance" || return 1
  cap="$(ctx_state_root)/instances/$instance.cap"; tmp="$(mktemp)"
  jq -c '.payload' "$event" >"$tmp"; expected="$(ctx_hmac "$cap" "$tmp")"; rm -f "$tmp"
  actual="$(jq -r '.tag // empty' "$event")"; [ "$expected" = "$actual" ] || return 1
  jq -c '.payload' "$event"
}

tx_transition() {
  local file="$1" expected="$2" next="$3" tmp lock store_lock instance id current
  store_lock="$(ctx_state_root)/transactions/.store.lock"; ctx_lock_acquire "$store_lock" || return 1
  lock="${file%.json}.lock"; ctx_lock_acquire "$lock" || { ctx_lock_release "$store_lock"; return 1; }
  if [ "$(jq -r '.state' "$file")" != "$expected" ]; then ctx_lock_release "$lock"; ctx_lock_release "$store_lock"; return 1; fi
  tmp="$(mktemp)"; jq -c --arg next "$next" '.state=$next' "$file" >"$tmp"
  if ! ctx_atomic_publish "$tmp" "$file" 600; then rm -f "$tmp"; ctx_lock_release "$lock"; ctx_lock_release "$store_lock"; return 1; fi
  if ctx_terminal_state "$next"; then
    instance="$(jq -r '.instance' "$file")"; id="$(jq -r '.id' "$file")"; current="$(ctx_state_root)/instances/$instance.current"
    if ctx_secure_regular "$current" 600 && [ "$(cat "$current")" = "$id" ]; then rm -f "$current"; fi
  fi
  rm -f "$tmp"; ctx_lock_release "$lock"; ctx_lock_release "$store_lock"
}

tx_snapshot_valid() {
  local file="$1" snapshot task_desc expected
  snapshot="$(jq -r '.workspace+"/"+.snapshot' "$file")"; task_desc="$(jq -r '.workspace+"/"+.task_description' "$file")"
  expected="$(jq -r '.snapshot_digest' "$file")"
  ctx_secure_parent "$snapshot" && ctx_secure_parent "$task_desc" && ctx_secure_regular "$snapshot" 600 && ctx_secure_owner_regular "$task_desc" && [ "$(ctx_identity "$snapshot")" = "$(jq -r '.snapshot_identity' "$file")" ] && [ "$(ctx_identity "$task_desc")" = "$(jq -r '.task_description_identity' "$file")" ] && [ "$(ctx_sha256 "$snapshot")" = "$expected" ] && [ "$(ctx_sha256 "$task_desc")" = "$(jq -r '.task_description_digest' "$file")" ]
}

event_matches_tx() {
  local payload="$1" file="$2" conversation_mode="${3:-same}"
  jq -e --arg mode "$conversation_mode" --slurpfile tx "$file" '
    .transaction==$tx[0].id and .instance==$tx[0].instance and .incarnation==$tx[0].incarnation and .pane==$tx[0].pane and .runtime==$tx[0].runtime and
    (($mode=="same" and .conversation==$tx[0].conversation) or ($mode=="changed" and .conversation!=$tx[0].conversation))
  ' <<<"$payload" >/dev/null
}

instance_active_for_tx() {
  local file="$1" root instance pane map meta pid birth socket epoch
  [ -z "${DR_ORCH_ACTION_EXECUTOR_LOG:-}" ] || return 0
  root="$(ctx_state_root)"; instance="$(jq -r '.instance' "$file")"; pane="$(jq -r '.pane' "$file")"; map="$root/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"; meta="$root/instances/$instance.meta.json"
  ctx_secure_regular "$map" 600 && [ "$(cat "$map")" = "$instance" ] && [ ! -e "$root/instances/$instance.retired" ] && ctx_secure_regular "$meta" 600 || return 1
  [ "$(jq -r '.runtime' "$meta")" = "$(jq -r '.runtime' "$file")" ] && [ "$(jq -r '.incarnation' "$meta")" = "$(jq -r '.incarnation' "$file")" ] && [ "$(jq -r '.task' "$meta")" = "$(jq -r '.task' "$file")" ] && [ "$(jq -r '.runtime_bound' "$meta")" = true ] || return 1
  pid="$(jq -r '.process_pid' "$meta")"; birth="$(jq -r '.process_birth' "$meta")"; [ "$(ctx_process_birth "$pid" 2>/dev/null || true)" = "$birth" ] && ctx_process_live "$pid" || return 1
  socket="$(jq -r '.socket' "$meta")"; epoch="$(jq -r '.epoch' "$meta")"
  if [ "$socket" != unbound ]; then [ -S "$socket" ] && tmux -S "$socket" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq "$pane" && [ "$(tmux -S "$socket" show-options -gv @datarim_context_epoch 2>/dev/null)" = "$epoch" ] || return 1; fi
}

consume_sequence() {
  local payload="$1" root instance sequence consumed lock tmp previous=0
  root="$(ctx_state_root)"; instance="$(jq -r '.instance' <<<"$payload")"; sequence="$(jq -r '.sequence' <<<"$payload")"
  [[ "$sequence" =~ ^[1-9][0-9]*$ ]] || return 1
  consumed="$root/instances/$instance.consumed"; lock="$consumed.lock"
  ctx_lock_acquire "$lock" || return 1
  [ ! -f "$consumed" ] || previous="$(cat "$consumed")"
  if ! [[ "$previous" =~ ^[0-9]+$ ]] || [ "$sequence" -le "$previous" ]; then ctx_lock_release "$lock"; return 1; fi
  tmp="$(mktemp)"; printf '%s\n' "$sequence" >"$tmp"
  if ! ctx_atomic_publish "$tmp" "$consumed" 600; then rm -f "$tmp"; ctx_lock_release "$lock"; return 1; fi
  rm -f "$tmp"; ctx_lock_release "$lock"
}

emit_action() {
  local pane="$1" action="$2"
  if [ -n "${DR_ORCH_ACTION_EXECUTOR_LOG:-}" ]; then printf '%s\n' "$action" >>"$DR_ORCH_ACTION_EXECUTOR_LOG"; return; fi
  # shellcheck source=tmux_manager.sh
  source "$DR_ORCH_DIR/scripts/tmux_manager.sh"; pane_send "$pane" "$action"
}

dispatch() {
  local id event file payload mode runtime action kind claim dispatched pane security_state
  id="$(arg_value --transaction "$@")"; event="$(arg_value --event "$@")"
  [[ "$id" =~ ^[a-f0-9]{32}$ ]] || die 'invalid transaction'
  file="$(ctx_state_root)/transactions/$id.json"; ctx_secure_regular "$file" 600 || die 'transaction not found'
  payload="$(event_payload "$event")" || die 'invalid event integrity'
  event_matches_tx "$payload" "$file" same || die 'event binding mismatch'
  kind="$(jq -r '.kind' <<<"$payload")"; case "$kind" in stop|turn_complete) ;; *) die 'event is not a dispatch boundary' ;; esac
  tx_snapshot_valid "$file" || die 'continuity checkpoint changed after prepare'
  instance_active_for_tx "$file" || die 'runtime instance is no longer active'
  consume_sequence "$payload" || die 'event replay or reordering detected'
  mode="$(jq -r '.mode' "$file")"; runtime="$(jq -r '.runtime' "$file")"; action="$(instruction --runtime "$runtime" --mode "$mode")"
  pane="$(jq -r '.pane' "$file")"; security_state="$(ctx_state_root)/security"; mkdir -p "$security_state"; chmod 700 "$security_state"
  STATE_DIR="$security_state" bash "$DR_ORCH_DIR/scripts/security.sh" is_pane_blocked "$pane" && die 'pane is blocked'
  STATE_DIR="$security_state" bash "$DR_ORCH_DIR/scripts/security.sh" check_cooldown "$pane" decision || die 'decision cooldown blocked dispatch'
  if [ "$mode" = selective_drop ]; then claim=compact_claimed; dispatched=compact_dispatched; else claim=clear_claimed; dispatched=clear_dispatched; fi
  tx_transition "$file" prepared "$claim" || die 'transaction not prepared'
  audit_tx "$file" reset_claimed "$claim" || die 'claim audit failed'
  emit_action "$(jq -r '.pane' "$file")" "$action" || die 'action dispatch failed after claim'
  tx_transition "$file" "$claim" "$dispatched"; audit_tx "$file" reset_dispatched "$dispatched" || die 'dispatch audit failed'
}

complete() {
  local id event file payload
  id="$(arg_value --transaction "$@")"; event="$(arg_value --event "$@")"; file="$(ctx_state_root)/transactions/$id.json"
  ctx_secure_regular "$file" 600 || die 'transaction not found'
  payload="$(event_payload "$event")" || die 'invalid event integrity'
  [ "$(jq -r '.kind' <<<"$payload")" = post_compact ] || die 'not a PostCompact marker'
  event_matches_tx "$payload" "$file" same || die 'event binding mismatch'
  tx_snapshot_valid "$file" || die 'continuity checkpoint changed after dispatch'
  instance_active_for_tx "$file" || die 'runtime instance is no longer active'
  consume_sequence "$payload" || die 'event replay or reordering detected'
  tx_transition "$file" compact_dispatched compact_complete_claimed || die 'not completion-ready'
  tx_transition "$file" compact_complete_claimed completed; audit_tx "$file" compact_completed success || die 'completion audit failed'
}

resume() {
  local id event file payload old new pane task
  id="$(arg_value --transaction "$@")"; event="$(arg_value --event "$@")"; file="$(ctx_state_root)/transactions/$id.json"
  ctx_secure_regular "$file" 600 || die 'transaction not found'
  payload="$(event_payload "$event")" || die 'invalid event integrity'; [ "$(jq -r '.kind' <<<"$payload")" = session_start ] || die 'not SessionStart'
  event_matches_tx "$payload" "$file" changed || die 'event binding mismatch'
  old="$(jq -r '.conversation' "$file")"; new="$(jq -r '.conversation' <<<"$payload")"; [ "$old" != "$new" ] || die 'conversation did not change'
  tx_snapshot_valid "$file" || die 'continuity checkpoint changed after dispatch'
  instance_active_for_tx "$file" || die 'runtime instance is no longer active'
  consume_sequence "$payload" || die 'event replay or reordering detected'
  tx_transition "$file" clear_dispatched resume_claimed || die 'not resume-ready'
  pane="$(jq -r '.pane' "$file")"; task="$(jq -r '.task' "$file")"
  emit_action "$pane" "/dr-next $task" || die 'resume failed after claim'
  tx_transition "$file" resume_claimed resume_dispatched; tx_transition "$file" resume_dispatched completed; audit_tx "$file" resume_completed success || die 'resume audit failed'
}


main() {
  local verb="${1:-}"; [ -n "$verb" ] || die 'verb required'; shift || true
  case "$verb" in evaluate) evaluate "$@" ;; instruction) instruction "$@" ;; prepare) prepare "$@" ;; dispatch) dispatch "$@" ;; complete) complete "$@" ;; resume) resume "$@" ;; reconcile) reconcile "$@" ;; replace) replace "$@" ;; register) register_instance "$@" ;; retire) retire "$@" ;; *) die "unknown verb: $verb" ;; esac
}

main "$@"
