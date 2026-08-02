#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export CONTROLLER="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_window_controller.sh"
  export DR_ORCH_CONTEXT_STATE="$BATS_TEST_TMPDIR/state"
  export DR_ORCH_CONTEXT_TRUST_ROOT="$BATS_TEST_TMPDIR"
  export DR_ORCH_TEST_ALLOW_UNBOUND=1
  chmod 700 "$BATS_TEST_TMPDIR"
  mkdir -p "$DR_ORCH_CONTEXT_STATE"
  chmod 700 "$DR_ORCH_CONTEXT_STATE"
}

seed_task() {
  export WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$WORKSPACE/datarim/snapshots" "$WORKSPACE/datarim/tasks" "$DR_ORCH_CONTEXT_STATE/instances"
  chmod 700 "$WORKSPACE" "$WORKSPACE/datarim" "$WORKSPACE/datarim/snapshots" "$WORKSPACE/datarim/tasks" "$DR_ORCH_CONTEXT_STATE/instances"
  printf '%s\n' '---' 'task_id: TUNE-0167' 'stage: plan' 'recommended_next: /dr-do' '---' >"$WORKSPACE/datarim/snapshots/TUNE-0167.snapshot.md"
  chmod 600 "$WORKSPACE/datarim/snapshots/TUNE-0167.snapshot.md"
  printf '# task description\n' >"$WORKSPACE/datarim/tasks/TUNE-0167-task-description.md"
  chmod 600 "$WORKSPACE/datarim/tasks/TUNE-0167-task-description.md"
  export INSTANCE=0123456789abcdef0123456789abcdef
  export INCARNATION=00000000000000000000000000000000
  printf '%064d\n' 0 >"$DR_ORCH_CONTEXT_STATE/instances/$INSTANCE.cap"; chmod 600 "$DR_ORCH_CONTEXT_STATE/instances/$INSTANCE.cap"
}

prepare_tx() {
  bash "$CONTROLLER" prepare --task TUNE-0167 --workspace "$WORKSPACE" --runtime "$1" --instance "$INSTANCE" --pane pane-1 --conversation conv-1 --mode "$2"
}

evaluate() { run bash "$CONTROLLER" evaluate --used-percent "$1"; }

@test "threshold 0 is no_op" { evaluate 0; [ "$status" -eq 0 ] && [ "$output" = no_op ]; }
@test "threshold 49 is no_op" { evaluate 49; [ "$status" -eq 0 ] && [ "$output" = no_op ]; }
@test "threshold 50 is no_op" { evaluate 50; [ "$status" -eq 0 ] && [ "$output" = no_op ]; }
@test "threshold 74 is no_op" { evaluate 74; [ "$status" -eq 0 ] && [ "$output" = no_op ]; }
@test "threshold 75 is selective_drop" { evaluate 75; [ "$status" -eq 0 ] && [ "$output" = selective_drop ]; }
@test "threshold 89 is selective_drop" { evaluate 89; [ "$status" -eq 0 ] && [ "$output" = selective_drop ]; }
@test "threshold 90 is full_clear" { evaluate 90; [ "$status" -eq 0 ] && [ "$output" = full_clear ]; }
@test "threshold 100 is full_clear" { evaluate 100; [ "$status" -eq 0 ] && [ "$output" = full_clear ]; }
@test "negative pressure is rejected" { evaluate -1; [ "$status" -ne 0 ]; }
@test "pressure above 100 is rejected" { evaluate 101; [ "$status" -ne 0 ]; }
@test "fractional controller pressure is rejected" { evaluate 74.5; [ "$status" -ne 0 ]; }

@test "taught launch label selects enum above its floor" {
  policy="$BATS_TEST_TMPDIR/policy.tsv"
  printf 'deep\tfull_clear\t60\n' >"$policy"; chmod 600 "$policy"
  run env DR_CONTEXT_POLICY_FILE="$policy" DR_CONTEXT_POLICY_LABEL=deep bash "$CONTROLLER" evaluate --used-percent 60
  [ "$status" -eq 0 ] && [ "$output" = full_clear ]
}

@test "taught label cannot act below immutable floor" {
  policy="$BATS_TEST_TMPDIR/policy.tsv"
  printf 'deep\tfull_clear\t40\n' >"$policy"; chmod 600 "$policy"
  run env DR_CONTEXT_POLICY_FILE="$policy" DR_CONTEXT_POLICY_LABEL=deep bash "$CONTROLLER" evaluate --used-percent 49
  [ "$status" -ne 0 ]
}

@test "duplicate taught labels reject the whole file" {
  policy="$BATS_TEST_TMPDIR/policy.tsv"
  printf 'deep\tfull_clear\t60\ndeep\tselective_drop\t70\n' >"$policy"; chmod 600 "$policy"
  run env DR_CONTEXT_POLICY_FILE="$policy" DR_CONTEXT_POLICY_LABEL=deep bash "$CONTROLLER" evaluate --used-percent 80
  [ "$status" -ne 0 ]
}

@test "oversized taught policy rejects the whole file" {
  policy="$BATS_TEST_TMPDIR/policy.tsv"; dd if=/dev/zero bs=17000 count=1 2>/dev/null | tr '\0' x >"$policy"; chmod 600 "$policy"
  run env DR_CONTEXT_POLICY_FILE="$policy" DR_CONTEXT_POLICY_LABEL=deep bash "$CONTROLLER" evaluate --used-percent 90
  [ "$status" -ne 0 ]
}

@test "unknown taught label falls back to defaults" {
  policy="$BATS_TEST_TMPDIR/policy.tsv"
  printf 'deep\tfull_clear\t60\n' >"$policy"; chmod 600 "$policy"
  run env DR_CONTEXT_POLICY_FILE="$policy" DR_CONTEXT_POLICY_LABEL=other bash "$CONTROLLER" evaluate --used-percent 75
  [ "$status" -eq 0 ] && [ "$output" = selective_drop ]
}

@test "codex full clear instruction is byte exact" {
  expected="$BATS_TEST_TMPDIR/expected"; actual="$BATS_TEST_TMPDIR/actual"
  printf '%s\n' '/clear' >"$expected"
  bash "$CONTROLLER" instruction --runtime codex --mode full_clear >"$actual"
  cmp -s "$expected" "$actual"
}

@test "codex selective instruction is literal compact" {
  run bash "$CONTROLLER" instruction --runtime codex --mode selective_drop
  [ "$status" -eq 0 ] && [ "$output" = /compact ]
}

@test "claude selective instruction preserves required pointers" {
  run bash "$CONTROLLER" instruction --runtime claude --mode selective_drop
  [ "$status" -eq 0 ] && [ "$output" = "/compact Preserve active Datarim task pointer last completed phase current plan open verification findings and next action" ]
}

@test "unsupported runtime is rejected" {
  run bash "$CONTROLLER" instruction --runtime other --mode full_clear
  [ "$status" -ne 0 ]
}

@test "unknown mode is rejected" {
  run bash "$CONTROLLER" instruction --runtime codex --mode shell
  [ "$status" -ne 0 ]
}

@test "prepare persists pointers and snapshot digest before action" {
  seed_task
  run prepare_tx codex selective_drop
  tx="$DR_ORCH_CONTEXT_STATE/transactions/$output.json"
  [ "$status" -eq 0 ] && [ -f "$tx" ] && jq -e '.state=="prepared" and .stage=="plan" and (.snapshot_digest|length)==64 and (.task_description|endswith("TUNE-0167-task-description.md"))' "$tx" >/dev/null
}

@test "prepare rejects a symlinked snapshot" {
  seed_task; mv "$WORKSPACE/datarim/snapshots/TUNE-0167.snapshot.md" "$BATS_TEST_TMPDIR/snapshot"; ln -s "$BATS_TEST_TMPDIR/snapshot" "$WORKSPACE/datarim/snapshots/TUNE-0167.snapshot.md"
  run prepare_tx codex full_clear
  [ "$status" -ne 0 ] && [ ! -d "$DR_ORCH_CONTEXT_STATE/transactions" ]
}

@test "prepare rejects a hard-linked snapshot" {
  seed_task; ln "$WORKSPACE/datarim/snapshots/TUNE-0167.snapshot.md" "$BATS_TEST_TMPDIR/snapshot-link"
  run prepare_tx codex full_clear
  [ "$status" -ne 0 ]
}

@test "claimed transaction blocks every later prepare for its instance" {
  seed_task; tx="$(prepare_tx codex full_clear)"; file="$DR_ORCH_CONTEXT_STATE/transactions/$tx.json"; tmp="$BATS_TEST_TMPDIR/claimed"
  jq '.state="clear_claimed"' "$file" >"$tmp"; chmod 600 "$tmp"; mv "$tmp" "$file"
  run prepare_tx codex full_clear
  [ "$status" -ne 0 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/transactions" -name '*.json' | wc -l)" -eq 1 ]
}

@test "concurrent prepare has exactly one winner per runtime instance" {
  seed_task
  prepare_tx codex full_clear >"$BATS_TEST_TMPDIR/a" 2>/dev/null & a=$!
  prepare_tx codex full_clear >"$BATS_TEST_TMPDIR/b" 2>/dev/null & b=$!
  winners=0; wait "$a" && winners=$((winners + 1)); wait "$b" && winners=$((winners + 1))
  [ "$winners" -eq 1 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/transactions" -name '*.json' | wc -l)" -eq 1 ]
}

@test "transaction cap fails closed when all 64 records are protected" {
  seed_task; mkdir -p "$DR_ORCH_CONTEXT_STATE/transactions"; chmod 700 "$DR_ORCH_CONTEXT_STATE/transactions"
  for n in $(seq 1 64); do printf '{"instance":"%032x","state":"prepared"}\n' "$n" >"$DR_ORCH_CONTEXT_STATE/transactions/$(printf '%032x' "$n").json"; chmod 600 "$DR_ORCH_CONTEXT_STATE/transactions/$(printf '%032x' "$n").json"; done
  run prepare_tx codex full_clear
  [ "$status" -ne 0 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/transactions" -name '*.json' | wc -l)" -eq 64 ]
}

@test "transaction cap removes the oldest terminal record first" {
  seed_task; mkdir -p "$DR_ORCH_CONTEXT_STATE/transactions"; chmod 700 "$DR_ORCH_CONTEXT_STATE/transactions"
  for n in $(seq 1 64); do id="$(printf '%032x' "$n")"; printf '{"id":"%s","instance":"%032x","state":"completed","created_at":"2026-01-01T00:00:00Z","created_seq":%d}\n' "$id" "$n" "$n" >"$DR_ORCH_CONTEXT_STATE/transactions/$id.json"; chmod 600 "$DR_ORCH_CONTEXT_STATE/transactions/$id.json"; done
  printf '64\n' >"$DR_ORCH_CONTEXT_STATE/transactions/.creation-seq"; chmod 600 "$DR_ORCH_CONTEXT_STATE/transactions/.creation-seq"
  run prepare_tx codex full_clear
  [ "$status" -eq 0 ] && [ ! -e "$DR_ORCH_CONTEXT_STATE/transactions/00000000000000000000000000000001.json" ] && [ -e "$DR_ORCH_CONTEXT_STATE/transactions/00000000000000000000000000000002.json" ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/transactions" -name '*.json' | wc -l)" -eq 64 ]
}

@test "selective lifecycle claims dispatch then completes exactly once" {
  seed_task; tx="$(prepare_tx codex selective_drop)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"; export DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 75)"
  bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  post="$(bash "$adapter" publish --runtime codex --kind post_compact --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx")"
  bash "$CONTROLLER" complete --transaction "$tx" --event "$post"
  run bash "$CONTROLLER" complete --transaction "$tx" --event "$post"
  [ "$status" -ne 0 ] && [ "$(cat "$DR_ORCH_ACTION_EXECUTOR_LOG")" = /compact ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = completed ]
}

@test "full clear resumes only with a changed conversation" {
  seed_task; tx="$(prepare_tx claude full_clear)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"; export DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions"
  stop="$(bash "$adapter" publish --runtime claude --kind stop --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 90)"
  bash "$CONTROLLER" dispatch --transaction "$tx" --event "$stop"
  same="$(bash "$adapter" publish --runtime claude --kind session_start --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx")"
  run bash "$CONTROLLER" resume --transaction "$tx" --event "$same"
  [ "$status" -ne 0 ]
  changed="$(bash "$adapter" publish --runtime claude --kind session_start --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-2 --transaction "$tx")"
  bash "$CONTROLLER" resume --transaction "$tx" --event "$changed"
  [ "$(printf '%s|' "$(cat "$DR_ORCH_ACTION_EXECUTOR_LOG")")" = $'/clear\n/dr-next TUNE-0167|' ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = completed ]
}

@test "forged integrity tag cannot dispatch" {
  seed_task; tx="$(prepare_tx codex full_clear)"; event="$BATS_TEST_TMPDIR/forged.json"
  jq -n -c --arg i "$INSTANCE" --arg n "$INCARNATION" --arg t "$tx" '{payload:{runtime:"codex",kind:"turn_complete",instance:$i,incarnation:$n,pane:"pane-1",conversation:"conv-1",transaction:$t,sequence:1},tag:"forged"}' >"$event"; chmod 600 "$event"
  run bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  [ "$status" -ne 0 ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = prepared ]
}

@test "snapshot mutation after prepare blocks dispatch" {
  seed_task; tx="$(prepare_tx codex full_clear)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"
  printf '\nchanged\n' >>"$WORKSPACE/datarim/snapshots/TUNE-0167.snapshot.md"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 90)"
  run bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  [ "$status" -ne 0 ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = prepared ]
}

@test "task-description mutation after prepare blocks dispatch" {
  seed_task; tx="$(prepare_tx codex full_clear)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"
  printf '\nchanged\n' >>"$WORKSPACE/datarim/tasks/TUNE-0167-task-description.md"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 90)"
  run bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  [ "$status" -ne 0 ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = prepared ]
}

@test "ancestor permission mutation after prepare blocks dispatch" {
  seed_task; tx="$(prepare_tx codex full_clear)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"
  chmod 770 "$WORKSPACE/datarim/tasks"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 90)"
  run bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  chmod 700 "$WORKSPACE/datarim/tasks"
  [ "$status" -ne 0 ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = prepared ]
}

@test "crash-stale lock owner is reclaimed using process birth" {
  seed_task; lock="$DR_ORCH_CONTEXT_STATE/transactions/.store.lock"; mkdir -p "$lock"; printf '999999 1\n' >"$lock/owner"; chmod 600 "$lock/owner"
  run prepare_tx codex full_clear
  [ "$status" -eq 0 ] && [ -f "$DR_ORCH_CONTEXT_STATE/transactions/$output.json" ]
}

@test "bounded audit records lifecycle identifiers but not raw conversations" {
  seed_task; tx="$(prepare_tx codex selective_drop)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"; export DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 75)"
  bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  post="$(bash "$adapter" publish --runtime codex --kind post_compact --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx")"
  bash "$CONTROLLER" complete --transaction "$tx" --event "$post"
  audit="$DR_ORCH_CONTEXT_STATE/audit/context-window.jsonl"
  [ "$(wc -l <"$audit")" -eq 4 ] && jq -e 'has("transaction") and has("snapshot_digest") and (has("conversation")|not)' "$audit" >/dev/null && ! grep -Eq 'conv-1|capability|RAW_' "$audit"
}

@test "PostCompact marker must match transaction pane and conversation" {
  seed_task; tx="$(prepare_tx codex selective_drop)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"; export DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 75)"
  bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  wrong="$(bash "$adapter" publish --runtime codex --kind post_compact --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-2 --conversation conv-1 --transaction "$tx")"
  run bash "$CONTROLLER" complete --transaction "$tx" --event "$wrong"
  [ "$status" -ne 0 ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = compact_dispatched ]
}

@test "consumed dispatch event sequence cannot be replayed" {
  seed_task; tx="$(prepare_tx codex full_clear)"; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"; export DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions"
  event="$(bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$tx" --used-percent 90)"
  bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  run bash "$CONTROLLER" dispatch --transaction "$tx" --event "$event"
  [ "$status" -ne 0 ] && [ "$(jq -r .state "$DR_ORCH_CONTEXT_STATE/transactions/$tx.json")" = clear_dispatched ]
}

@test "event spool cap refuses a 129th unconsumed envelope" {
  seed_task; adapter="$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh"; mkdir -p "$DR_ORCH_CONTEXT_STATE/events"; chmod 700 "$DR_ORCH_CONTEXT_STATE/events"
  for n in $(seq 1 128); do bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction "$(printf '%032x' "$n")" >/dev/null; done
  run bash "$adapter" publish --runtime codex --kind turn_complete --instance "$INSTANCE" --incarnation "$INCARNATION" --pane pane-1 --conversation conv-1 --transaction 99999999999999999999999999999999
  [ "$status" -ne 0 ] && [ "$(find "$DR_ORCH_CONTEXT_STATE/events" -name '*.json' | wc -l)" -eq 128 ]
}

@test "HMAC capability bytes are never passed through OpenSSL argv" {
  run grep -En 'hexkey:|macopt.*cat' "$REPO_ROOT/plugins/dr-orchestrate/scripts/lib/context-window-state.sh" "$REPO_ROOT/plugins/dr-orchestrate/scripts/context_pressure_adapter.sh" "$REPO_ROOT/plugins/dr-orchestrate/scripts/context_window_controller.sh" "$REPO_ROOT/plugins/dr-orchestrate/scripts/context_window_setup.sh"
  [ "$status" -eq 1 ]
}
